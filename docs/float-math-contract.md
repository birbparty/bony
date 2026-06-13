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
- Emitted vertex positions, UVs, and color components.
- Constraint and deformer outputs that feed those public results.

Index buffers, counts, enum tags, names, and topology are exact-equality
outputs. A single index mismatch is a conformance failure, not a tolerated
numeric drift.

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
  JSON emission for f32-backed fields, f32-backed golden vector fields, and
  emitted f32 vertex/color buffers. Per-bone transform goldens may be stored as
  decimal f64 values and compared by tolerance.
- Compile deterministic builds without fast-math flags or fused multiply-add
  contraction. Do not rely on extended precision. CI deterministic builds must
  pass Nim C backend options equivalent to `-ffp-contract=off` when the C
  compiler supports them; do not pass `-ffast-math` or architecture-specific
  flags that change FP semantics.

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
Use the platform standard library for these operations. In Dart, `pow` results
must be converted to `double` before downstream arithmetic.

This section does not define transform composition formulas, inherit modes, or
reflection factoring. It constrains arithmetic order after the transform
composition contract chooses those formulas.

## Bézier Curves

Bézier keyframe easing uses the fixed table approach required by the binding
spec:

- Build a 16-sample table for `Bx(s)` at `s = i / 15`, `i = 0..15`.
- Validate authoring handles before playback: `c1x` and `c2x` must be finite
  and in `[0, 1]`; invalid curves are load errors.
- For normalized input `t`, clamp `t` to `[0, 1]`.
- If `t == 0`, return `0`. If `t == 1`, return `1`.
- Find the first interval where `Bx[i] <= t <= Bx[i + 1]` and
  `Bx[i + 1] > Bx[i]`. If no non-zero-width interval exists, use
  `s = t`.
- Linearly interpolate an initial `s` within that interval. Endpoint ties use
  the earlier non-zero-width interval.
- Perform exactly two Newton refinement iterations using f64/double.
- If a Newton derivative is zero or non-finite, stop refinement and keep the
  current clamped `s`.
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
- The `bony-58f` spike verifies analytic 1-bone/2-bone IK risk only. Chain IK
  needs a follow-up feasibility check in the M5 chain-IK implementation bead
  once FABRIK vs. CCD is selected.

## Path Sampling

Path constraints and path attachments use f64/double for curve evaluation.

- Cubic Bézier point evaluation uses Bernstein basis in this order:
  `((1-u)^3 * p0) + (3*(1-u)^2*u * p1) + (3*(1-u)*u^2 * p2) + (u^3 * p3)`.
- Arc-length tables, when needed, must use a fixed sample count defined by the
  path-constraint implementation contract before M5.
- Cumulative path distances are summed left-to-right.
- This section constrains curve-evaluation arithmetic only. It does not define
  path-constraint semantics such as constant-speed behavior, spacing modes, or
  rotate modes.

## Physics Integration

The later physics integrator contract owns spring constants, channel semantics,
reset behavior, max-substep policy, and clamp cases. This contract freezes the
floating-point order those choices must use:

- Physics state uses f64/double.
- Fixed substeps are processed in chronological order.
- For each substep, start from zero force/acceleration accumulators.
- Accumulate terms in this order when the physics contract enables them:
  animated target spring, gravity, wind, damping.
- Integrate velocity before position. The later physics contract may define
  exact formulas and coefficients, but it must preserve this operation order
  unless it creates a new bead that updates this contract and all dependent
  conformance expectations.

## Feasibility Spike

The cross-runtime target is feasible under this contract because all high-risk
areas use f64/double intermediates and f32 output rounding, while conformance
allows `abs <= 1e-4`.

Spike checks are committed in `docs/spikes/float_math_spike.js` with output in
`docs/spikes/float_math_spike.result.json`. Reproduce them with:

```bash
node docs/spikes/float_math_spike.js
```

The script compares f64-style inputs against f32-quantized loaded inputs with
f32-rounded outputs, using Node 24.11.1 in this session. It is not a substitute
for future Nim-vs-Dart conformance tests; it is the M1 feasibility check that
the chosen numeric discipline leaves margin under `1e-4`.

Spike cases performed for this contract:

- **Bézier easing:** 16-sample table plus two Newton iterations keeps common
  monotonic curves stable within the tolerance when values are rounded to f32
  at output. Representative curves observed maximum f32-output drift
  `1.1920928955078125e-7` when comparing f64 inputs against f32-quantized
  loaded inputs. Cases: `ease`, `ease-in-out`, and `crossing-slopes`, each
  sampled at 101 evenly spaced `t` values.
- **2-bone IK:** cosine-law clamping and f64/double intermediates keep target
  angle and end-effector output drift below tolerance for representative
  reachable, over-extended, and too-close targets. The representative cases
  observed maximum f32-output component drift `0`. Cases: reachable,
  over-extended, too-close, and mixed-quadrant targets.
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
