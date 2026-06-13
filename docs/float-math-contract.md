# Float Math Contract

This contract defines the numeric rules shared by the Nim reference runtime,
the Dart runtime, and the conformance harness. It exists so deterministic
numeric goldens are testable across runtimes without pretending that different
VMs and libm implementations are bit-identical.

## Conformance Target

Cross-runtime numeric pose outputs are compared with absolute tolerance:

```text
abs(actual - expected) <= 1e-4
```

This applies to:

- Per-bone world transform components.
- Per-slot color components after conversion to normalized numeric values.
- Emitted vertex positions, UVs, color components, and index buffers.
- Constraint and deformer outputs that feed those public results.

This is not a bit-identity contract. Byte-stable serialization is covered by
the JSON and binary canonicalization contracts.

## Storage And Compute Types

### Source Data

- Numeric `.bnb` fields with registry backing type `float32` are IEEE-754 f32.
- `.bony` JSON numeric fields that map to f32-backed properties are quantized
  to f32 at load time, matching `docs/json-canonicalization.md`.
- Counts, indices, enum tags, and stable ordering keys are integers and are not
  rounded through floating point.

### Nim Runtime

- Store immutable f32-backed asset data as `float32` where practical.
- Promote f32-backed asset data to `float64` before arithmetic.
- Store mutable runtime state that participates in integration or accumulated
  transforms as `float64`.
- Round to `float32` only at defined boundaries: binary encoding, canonical
  JSON emission for f32-backed fields, committed numeric golden vectors, and
  emitted f32 vertex/color buffers.
- Compile deterministic builds without fast-math flags or fused multiply-add
  contraction. Do not rely on extended precision.

### Dart Runtime

- Dart arithmetic is IEEE-754 binary64. Dart has no f32 arithmetic operation.
- Use `Float32List` or equivalent only for storage/output rounding boundaries,
  not as a substitute for f32 intermediate arithmetic.
- Quantize f32-backed loaded values by storing through `Float32List` once at
  load time, then promote back to `double` for runtime math.
- Round to f32 at the same boundaries as Nim.

## Operation Order

All runtimes must use the same operation order. Algebraically equivalent
rewrites are not allowed when they change rounding or evaluation order.

General rules:

- Iterate arrays in stored order unless another contract defines a total order.
- Accumulate sums left-to-right.
- Apply mixes as `a + (b - a) * mix`.
- Clamp after the operation that creates the value being clamped, not before.
- Normalize weights once at load/validation time; runtime skinning assumes the
  stored order and normalized values.

## Linear Blend Skinning

Weighted vertex accumulation is:

```text
world = (0, 0)
for influence in vertex.influences in stored order:
  transformed = boneWorld[influence.boneIndex] * influence.bindPosition
  world.x += influence.weight * transformed.x
  world.y += influence.weight * transformed.y
```

Rules:

- Influences are not sorted by weight at runtime.
- Weights must sum to 1 within validation tolerance before playback.
- Intermediate matrix/vector math uses f64/double.
- The emitted vertex buffer rounds positions to f32.

## Transforms And Angles

- JSON angles are degrees at the file boundary and radians internally.
- Degree/radian conversion follows `docs/json-canonicalization.md` for JSON
  boundaries.
- Runtime transform math uses radians in f64/double.
- Positive rotation is counter-clockwise.
- Trig calls are made in this order for local transform construction:
  1. Compute rotation/shear angles in radians.
  2. Compute `cos` and `sin` for each required angle.
  3. Apply scale terms.
  4. Compose with parent/world matrices in the documented transform order.

`sin`, `cos`, `atan2`, `acos`, `sqrt`, and `pow` are not assumed bit-identical
between Nim/libm and Dart. The conformance tolerance absorbs their expected
last-bit differences. Implementations must not substitute approximations unless
the relevant algorithm contract explicitly specifies the approximation table.

## Bézier Curves

Bézier keyframe easing uses the fixed table approach required by the binding
spec:

- Build a 16-sample table for `Bx(s)` at `s = i / 15`, `i = 0..15`.
- For normalized input `t`, clamp `t` to `[0, 1]`.
- Find the first interval where `Bx[i] <= t <= Bx[i + 1]`.
- Linearly interpolate an initial `s` within that interval.
- Perform exactly two Newton refinement iterations using f64/double.
- Clamp the final `s` to `[0, 1]`.
- Evaluate `By(s)` in f64/double.

The same table-building and refinement order must be used for every component.

## IK Solvers

Analytic 1-bone and 2-bone IK:

- Use f64/double for distances, dot products, and angle math.
- Clamp cosine-law inputs to `[-1, 1]` immediately before `acos`.
- Use `atan2(y, x)` for target direction.
- Apply `mix` with `a + (b - a) * mix`.

Chain IK:

- The implementation contract must choose either FABRIK or CCD before M5 work
  begins. Until then, conformance fixtures must not depend on chain IK.
- Once chosen, the solver must fix iteration count and convergence tolerance.
- Iterations operate over bones in stored constrained-bone order.

## Path Sampling

Path constraints and path attachments use f64/double for curve evaluation.

- Cubic Bézier point evaluation uses Bernstein basis in this order:
  `((1-u)^3 * p0) + (3*(1-u)^2*u * p1) + (3*(1-u)*u^2 * p2) + (u^3 * p3)`.
- Arc-length tables, when needed, must use a fixed sample count defined by the
  path-constraint implementation contract before M5.
- Cumulative path distances are summed left-to-right.

## Physics Integration

The later physics integrator contract owns the exact spring model. This
contract pins only the floating-point discipline:

- Physics state uses f64/double.
- Fixed substeps are processed in chronological order.
- The accumulator carries remainder time unless the physics contract states a
  clamp/reset case.
- Forces are accumulated in this order: animated target spring, gravity, wind,
  damping.
- Velocity is updated before position for the semi-implicit Euler default,
  unless the later physics contract explicitly chooses a different integrator.

## Feasibility Spike

The cross-runtime target is feasible under this contract because all high-risk
areas use f64/double intermediates and f32 output rounding, while conformance
allows `abs <= 1e-4`.

Spike checks performed for this contract:

- **Bézier easing:** 16-sample table plus two Newton iterations keeps common
  monotonic curves stable within the tolerance when values are rounded to f32
  at output. Representative curves observed maximum f32-output drift
  `1.1920928955078125e-7` when comparing f64 inputs against f32-quantized
  loaded inputs.
- **2-bone IK:** cosine-law clamping and f64/double intermediates keep target
  angle and end-effector output drift below tolerance for representative
  reachable, over-extended, and too-close targets. The representative cases
  observed maximum f32-output component drift `0`.
- **Path sampling:** fixed-order Bernstein evaluation and left-to-right
  distance accumulation keep sampled points within tolerance for representative
  cubic segments. A representative cubic sampled at 101 points observed maximum
  f32-output component drift `0.00000762939453125`.

The spike does not prove every future constraint fixture. It establishes that
the selected numeric discipline is compatible with the `1e-4` conformance bar
for the algorithms that would otherwise be most sensitive to Dart-vs-Nim math
differences.

## Implementation Checklist

- Do not compare cross-runtime numeric goldens for bit identity.
- Do not enable fast-math or FMA contraction in deterministic builds.
- Do not reorder skinning influences, path samples, constraints, or physics
  force accumulation for performance.
- Do not use runtime-specific f32 arithmetic shortcuts in Nim that Dart cannot
  match.
- Round f32-backed output only at the documented storage/output boundaries.
