# Transform Composition Contract

This contract defines local-to-world bone transform composition for the Nim
reference runtime, the Dart runtime, and the conformance harness. It fills in
the formulas required by spec section 8.1 before M2 world-transform work.

## Scope

This document owns:

- Local affine matrix construction from `x`, `y`, `rotation`, `scaleX`,
  `scaleY`, `shearX`, and `shearY`.
- Parent rotation, scale/shear, and reflection factoring.
- The five named `transformMode` combinations.
- Degenerate parent-basis fallback behavior.
- Conformance scenarios for per-mode world-transform goldens.

It does not define animation timeline sampling, constraint solver math,
physics integration, or renderer coordinate conversion.

## Coordinate And Storage Rules

- Coordinates are 2D affine transforms in skeleton world units.
- JSON angles are degrees at the file boundary and radians internally.
- Positive rotation is counter-clockwise.
- Matrices are stored and emitted as column-major affine components:

```text
| a c tx |
| b d ty |
| 0 0  1 |
```

The first column `(a, b)` is the transformed local x axis. The second column
`(c, d)` is the transformed local y axis.

Runtime math uses f64/double following `docs/float-math-contract.md`.

## Local Matrix

For a bone local transform:

```text
x, y, rotation, scaleX, scaleY, shearX, shearY
```

compute:

```text
xAngle = rotation + shearX
yAngle = rotation + pi / 2 + shearY

la = cos(xAngle) * scaleX
lb = sin(xAngle) * scaleX
lc = cos(yAngle) * scaleY
ld = sin(yAngle) * scaleY
ltx = x
lty = y
```

`M_local` is:

```text
| la lc ltx |
| lb ld lty |
|  0  0   1 |
```

The operation order is binding: compute both angles, call `cos`/`sin`, then
apply scale terms.

## Parent Factoring

Each child always inherits parent translation. The inherit flags control only
which parts of the parent linear 2x2 matrix affect the child's local basis.

Given parent world linear matrix:

```text
P = | pa pc |
    | pb pd |
```

factor it into:

```text
P = R * F * S
```

where:

- `R` is a proper rotation matrix with determinant `+1`.
- `F` is either identity or x-axis reflection.
- `S` is an upper-triangular scale/shear matrix with non-negative diagonal
  entries.

Constants:

```text
basisEpsilon = 1e-12
```

### Non-Degenerate Factoring

Let:

```text
u = (pa, pb)
v = (pc, pd)
sx = length(u)
detP = pa * pd - pb * pc
reflectionSign = -1 if detP < 0 else +1
```

When `sx > basisEpsilon`, compute:

```text
r0 = u / sx
r1 = perpCCW(r0) = (-r0.y, r0.x)

R = | r0.x r1.x |
    | r0.y r1.y |

F = | 1              0 |
    | 0 reflectionSign |

k = dot(r0, v)
sy = reflectionSign * dot(r1, v)

S = | sx  k |
    |  0 sy |
```

For non-degenerate matrices, `sy` is non-negative by construction. Do not clamp
`sy` in this path. A `normal` child with all inherit flags enabled must
recompose the parent linear matrix exactly, within floating-point evaluation
rules, even when `sy` is very small. The degenerate path is selected only by
the `sx <= basisEpsilon` predicate above.

### Degenerate Factoring

If `sx <= basisEpsilon`, use the second parent column to choose a stable basis:

```text
vy = length(v)
```

If `vy > basisEpsilon`:

```text
r1 = v / vy
r0 = (r1.y, -r1.x)
reflectionSign = +1
R = | r0.x r1.x |
    | r0.y r1.y |
F = identity
S = | 0  0 |
    | 0 vy |
```

If both columns are degenerate:

```text
R = identity
F = identity
S = | 0 0 |
    | 0 0 |
```

Degenerate fallback is deterministic, but rigs that animate a parent basis
through zero scale should not expect continuous rotation factoring at the exact
degenerate frame. Conformance fixtures must include the fallback cases so both
runtimes choose the same result.

## Inherit Flags

For a child with local linear matrix `L`, choose an inherited parent linear
matrix `H`:

```text
H = Hr * Hf * Hs
```

where:

```text
Hr = R if inheritRotation else identity
Hf = F if inheritReflection else identity
Hs = S if inheritScale else identity
```

Then:

```text
worldLinear = H * L
worldTranslation = parentWorldTranslation + P * (x, y)
```

The parent translation offset uses the full parent linear matrix `P`, not `H`.
This means every mode preserves hierarchical positioning while the inherit
flags affect only the child's local axes.

The final world matrix is:

```text
| worldLinear.a worldLinear.c worldTranslation.x |
| worldLinear.b worldLinear.d worldTranslation.y |
|             0             0                  1 |
```

For a root bone, `P`, `R`, `F`, and `H` are identity, parent translation is
`(0, 0)`, and `world = M_local`.

## Transform Modes

`transformMode` is a named presentation of the three inherit flags. The flags
are the canonical stored data; the modes are aliases used by importers, UI, and
fixtures. Only the five flag triples in this table are valid v1 file states.

| transformMode | inheritRotation | inheritScale | inheritReflection |
| --- | --- | --- | --- |
| `normal` | true | true | true |
| `onlyTranslation` | false | false | false |
| `noRotationOrReflection` | false | true | false |
| `noScale` | true | false | true |
| `noScaleOrReflection` | true | false | false |

If a file stores both a mode alias and explicit flags, validation must reject
the file unless they match the table exactly. Canonical emission writes the
flags and may omit the alias.

If a file stores explicit flags without a mode alias, validation must still
reject any flag triple not listed in the table. The general formulas above are
defined for clarity and implementation reuse; they do not authorize extra v1
transform modes.

## Reflection

Reflection is the handedness sign of the parent 2x2 determinant. Negative
child `scaleX` or `scaleY` remains part of the child's local matrix; it is not
moved into the parent reflection factor.

When `inheritReflection = false`, the child does not inherit the parent's
negative determinant sign. When `inheritScale = true`, it can still inherit the
parent's scale and shear magnitudes through `S`.

## Recomposition Order

Implementations must not substitute another decomposition that is merely
visually similar. The recomposition order is:

1. Build `M_local`.
2. Factor the parent linear matrix into `R`, `F`, and `S`.
3. Select `Hr`, `Hf`, and `Hs` from the inherit flags.
4. Compute `H = Hr * Hf * Hs`.
5. Compute `worldLinear = H * localLinear`.
6. Compute `worldTranslation = parentWorldTranslation + P * localTranslation`.
7. Store the world affine matrix.

All matrix multiplications are evaluated left-to-right in the order shown.

## Linear Blend Skinning Boundary

This contract owns bone world matrices. Linear blend skinning consumes those
matrices using the accumulation order in `docs/float-math-contract.md`.
Skinning must not reinterpret inherit flags or decompose world matrices again.

## Conformance Scenarios

The M2 numeric golden suite must include:

- A root bone using rotation, scale, and shear.
- A parent with non-uniform scale and shear, plus one child for each of the
  five transform modes.
- A reflected parent with one child for each of the five transform modes.
- A child with negative local scale, proving local reflection is not folded into
  parent reflection factoring.
- Rejection of the three boolean flag triples not listed in the transform-mode
  table.
- A parent whose first basis column is degenerate but second column is not.
- A parent whose full linear basis is degenerate.
- A hierarchy of at least three bones proving parent translation uses full `P`
  while child axes use selected `H`.
- JSON input that uses a mode alias and canonical output that preserves the
  matching boolean flags.
