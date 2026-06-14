# DragonBones Importer Design Spike

This note defines the first `bony` DragonBones importer target. It is a
clean-room design derived from the local `bony` specification, project-owned
contracts, and capability-level knowledge of the public `_ske.json` wire
format. It is not based on DragonBones runtime source, importer code, or
third-party schema text.

## Goal

The importer converts a conservative subset of a DragonBones `_ske.json` file
into a `bony` document playable by the normal CLI and conformance harness. It
is a migration tool, not a compatible runtime. It must reject unsupported
constructs with diagnostics instead of silently approximating them unless this
note explicitly allows an approximation.

## Clean-Room Boundary

Implementation may use:

- User-supplied `_ske.json` files as input data.
- This design note, `docs/CLEANROOM.md`, and the binding `bony` spec.
- Public/textbook math for 2D affine transforms and animation interpolation.
- The DragonBones `_ske.json` wire format at the capability level: field names,
  structural nesting, and numeric semantics are recorded here as an
  importer-owned input contract. This capability context has been recorded in
  `docs/PROVENANCE.md` before use.

Implementation must not fetch, inspect, copy, or derive from DragonBones
runtime source, any DragonBones importer, generated DragonBones schema files,
or DragonBones documentation prose. Field handling must be implemented from the
input contract below and from user-supplied `_ske.json` fixtures. Unsupported
or ambiguous constructs are rejected until this note is updated.

## The Core Design Problem: Skew Decomposition

DragonBones bones are parameterized with `skX` (skewX) and `skY` (skewY)
angles, while `bony` bones use `rotation`, `shearX`, and `shearY`. This section
derives the lossless mapping from first principles.

### DragonBones Local Matrix (Y-Down)

DragonBones uses a Y-down screen coordinate system. The local 2D affine matrix
for a bone in column-major form is:

```
        x-axis column      y-axis column   translation
M_db = [ cos(skY)·scX    -sin(skX)·scY    x ]
       [ sin(skY)·scX     cos(skX)·scY    y ]
       [       0                0         1 ]
```

All angles are in degrees at the wire boundary. The x-axis column is the
transformed local x direction; the y-axis column is the transformed local y
direction. This is consistent with the DragonBones capability-level description
of their two-angle bone parameterization.

### Coordinate System Conversion

`bony` uses Y-up (positive rotation is counter-clockwise per
`docs/transform-composition-contract.md`). Changing from Y-down to Y-up is
equivalent to conjugating by the Y-flip matrix `T = diag(1, -1)`:

```
M_bony = T · M_db · T⁻¹     (T = T⁻¹ since T² = I)
```

Evaluating the conjugation:

```
M_bony = [  cos(skY)·scX    sin(skX)·scY    x  ]
         [ -sin(skY)·scX    cos(skX)·scY   -y  ]
         [       0                0          1  ]
```

Translation Y is negated. The linear 2×2 block changes sign only in the
`(row=1, col=0)` and `(row=0, col=1)` entries.

### Matching to the bony Local Matrix Formula

From `docs/transform-composition-contract.md`, the bony local matrix is:

```
xAngle = rotation + shearX
yAngle = rotation + π/2 + shearY

M_bony = [ cos(xAngle)·scaleX    cos(yAngle)·scaleY    x  ]
         [ sin(xAngle)·scaleX    sin(yAngle)·scaleY    y  ]
         [          0                        0          1  ]
```

Matching column by column against the converted M_bony above:

**Column 0 (x-axis):**

```
cos(xAngle) · scaleX = cos(skY) · scX
sin(xAngle) · scaleX = -sin(skY) · scX
```

Therefore: `xAngle = -skY`, `scaleX = scX`.

**Column 1 (y-axis):**

```
cos(yAngle) · scaleY = sin(skX) · scY
sin(yAngle) · scaleY = cos(skX) · scY
```

`cos(π/2 - skX) = sin(skX)` and `sin(π/2 - skX) = cos(skX)`, therefore:
`yAngle = π/2 - skX`, `scaleY = scY`.

### Solving for bony Parameters

Substituting into the bony angle formulas:

```
xAngle = rotation + shearX = -skY
yAngle = rotation + π/2 + shearY = π/2 - skX
```

Choose `shearX = 0` (canonical: rotation carries the primary angle):

```
rotation = -skY
shearY = (π/2 - skX) - rotation - π/2 = -skX - rotation = -skX + skY = skY - skX
```

### Final Mapping (all angles in degrees)

| DragonBones field | bony field   | Formula         |
| ----------------- | ------------ | --------------- |
| `x`               | `x`          | `x`             |
| `y`               | `y`          | `-y`            |
| `skY`             | `rotation`   | `-skY`          |
| *(implicit zero)* | `shearX`     | `0` (omit)      |
| `skX`, `skY`      | `shearY`     | `skY - skX`     |
| `scX`             | `scaleX`     | `scX`           |
| `scY`             | `scaleY`     | `scY`           |

### Special Cases

- **Pure rotation** (`skX == skY`): `rotation = -skX`, `shearY = 0` — a
  standard rigid rotation with no shear, as expected.
- **Identity** (`skX = skY = 0`, `scX = scY = 1`): all bony fields are at
  their defaults.
- **Negative scale** (`scX < 0` or `scY < 0`): preserved directly in bony's
  `scaleX` / `scaleY`. DragonBones negative scale is local; it must not be
  folded into any reflection factor. This matches `docs/transform-composition-
  contract.md` §Reflection.
- **Omitted DragonBones fields**: missing `skX` defaults to `0.0`; missing
  `skY` defaults to `0.0`; missing `scX` defaults to `1.0`; missing `scY`
  defaults to `1.0`. Apply these defaults before the mapping, not after.

### Verification Sketch

For the identity case: `skX = skY = 0`, `scX = scY = 1`, `x = y = 0`.
Applying the mapping: `rotation = 0`, `shearY = 0`. Bony `xAngle = 0 + 0 = 0`,
`yAngle = 0 + π/2 + 0 = π/2`. Matrix:

```
[ cos(0)·1    cos(π/2)·1    0 ] = [ 1  0  0 ]
[ sin(0)·1    sin(π/2)·1    0 ]   [ 0  1  0 ]
[     0            0        1 ]   [ 0  0  1 ]
```

Identity. ✓

For a pure 30° CW rotation in DragonBones (Y-down): `skX = skY = 30`, `scX =
scY = 1`. Mapping: `rotation = -30`, `shearY = 30 - 30 = 0`. Bony matrix:

```
xAngle = -30°,  yAngle = -30° + 90° = 60°
[ cos(-30°)   cos(60°)  ] = [  √3/2  1/2  ]
[ sin(-30°)   sin(60°)  ]   [ -1/2   √3/2 ]
```

A 30° CCW rotation in Y-up coordinates, which is the correct handedness flip
for the same physical pose. ✓

## Importer-Owned Adapter Model

The importer should parse into an intermediate model before constructing
`SkeletonData`:

- `DbSkeleton`: version string, top-level name, armature list.
- `DbArmature`: name, frame-rate, bone list, slot list, skin list, animation
  list.
- `DbBone`: name, optional parent name, optional length hint, optional
  `DbTransform` (rest-pose transform).
- `DbSlot`: name, parent bone name, draw-order index, optional blend mode.
- `DbSkin`: name, display entries per slot.
- `DbDisplay`: name, display type, optional `DbTransform`, optional
  width/height for image displays.
- `DbAnimation`: name, duration in frames, bone timeline list.
- `DbBoneTimeline`: bone name, keyframe list.
- `DbKeyframe`: duration-offset in frames, optional `DbTransform` delta,
  tween-easing value or null, optional Bezier curve handles.
- `DbTransform`: x, y, skX, skY, scX, scY — all optional with the defaults
  listed above.

This intermediate model is project-owned. The importer isolates input-field
names at the parser boundary so runtime objects and conformance assets remain
`bony`-native.

## Project-Owned Input Contract

The importer recognizes the following JSON shapes. Names below are accepted
input keys because this design note owns the parser contract; they must not
leak into bony runtime objects.

### Top-Level Object

```
{
  "name":    string,            // optional, ignored
  "version": string,            // required; must start with "5."
  "armature": [ ArmatureObject ]
}
```

The importer rejects version strings that do not begin with `"5."`. Earlier
DragonBones versions used different transform semantics; the math above applies
only to `_ske.json` format version 5.x files.

### ArmatureObject

```
{
  "name":      string,          // required
  "frameRate": number,          // required, > 0
  "type":      "Armature",      // must be present and equal "Armature"
  "bone":      [ BoneObject ],  // required, non-empty
  "slot":      [ SlotObject ],  // required
  "skin":      [ SkinObject ],  // required
  "animation": [ AnimationObject ]   // required
}
```

Multi-armature files: the importer converts the first armature and emits a
diagnostic listing ignored armature names for any additional armatures.

### BoneObject

```
{
  "name":      string,          // required
  "parent":    string,          // optional; absent = root bone
  "length":    number,          // optional, ignored (bony has no bone-length field)
  "transform": TransformObject  // optional; absent = identity
}
```

### SlotObject

```
{
  "name":     string,           // required
  "parent":   string,           // required, references a BoneObject name
  "displayIndex": number,       // optional, integer; default 0
  "color":    ColorMultiplierObject  // optional; see §Color
  "blendMode": string           // optional; see §Blend Mode
}
```

### SkinObject

```
{
  "name":    string,            // required; "" = default skin
  "slot": [ SlotDisplayObject ] // required
}
```

### SlotDisplayObject

```
{
  "name":    string,            // slot name
  "display": [ DisplayObject ]  // display list for this slot
}
```

### DisplayObject

```
{
  "name":  string,              // required; image asset name
  "type":  string,              // required; "image" is supported; others → diagnostic
  "transform": TransformObject, // optional; slot-relative transform for image pivot
  "width":  number,             // optional, ignored (atlas lookup provides dimensions)
  "height": number              // optional, ignored
}
```

Mesh (`"type": "mesh"`) and bounding-box (`"type": "boundingBox"`) displays
are rejected with `unsupportedFeature`.

### TransformObject

```
{
  "x":  number,  // optional, default 0
  "y":  number,  // optional, default 0
  "skX": number, // optional, default 0 (degrees)
  "skY": number, // optional, default 0 (degrees)
  "scX": number, // optional, default 1
  "scY": number  // optional, default 1
}
```

Any additional field in a `TransformObject` is rejected as `schemaViolation`.

### AnimationObject

```
{
  "name":     string,           // required
  "duration": number,           // required, integer frames > 0
  "bone": [ BoneTimelineObject ] // optional; absent = static animation
}
```

### BoneTimelineObject

```
{
  "name":  string,              // required, references a BoneObject name
  "frame": [ KeyframeObject ]   // required, non-empty
}
```

### KeyframeObject

```
{
  "duration":    number,        // required, integer frames ≥ 1
  "tweenEasing": number | null, // optional; see §Easing
  "curve":       [ number ],    // optional; four Bezier control values; see §Easing
  "transform":   TransformObject // optional; delta transform from rest pose
}
```

### ColorMultiplierObject

```
{
  "rM": number,  // optional, default 100 (percent, 0–100 mapped to 0.0–1.0)
  "gM": number,
  "bM": number,
  "aM": number
}
```

Slot color multipliers map to bony slot color timelines if the target bony
model supports them; otherwise rejected with `unsupportedFeature`.

### Blend Mode

DragonBones `blendMode` values: `"normal"`, `"add"`, `"multiply"`, `"screen"`.
Only `"normal"` (the default) is in the first supported subset. Others produce
`unsupportedFeature`.

## Structural Mapping to bony

| DragonBones concept      | bony concept                      |
| ------------------------ | --------------------------------- |
| Armature                 | `SkeletonData`                    |
| Bone (name, parent)      | `Bone` (name, parent)             |
| Bone rest-pose transform | Bone `x`, `y`, `rotation`, etc.   |
| Slot (name, parent bone) | `Slot` (name, bone)               |
| Skin (name)              | `Skin` (name)                     |
| Image display in skin    | `RegionAttachment` in skin        |
| Animation (name)         | `AnimationClip` (name)            |
| Bone timeline            | Per-bone property timelines       |
| Keyframe (duration, transform delta) | Keyframe in property timeline |

### Bone Hierarchy

Bones are emitted in the order they appear in the `bone` array. The importer
validates that:
- Every `parent` reference names a bone already declared earlier in the list
  (DragonBones convention: parents precede children).
- The root has no `parent` field (or an empty/null parent).
- No cycles exist. If any bone's parent chain does not terminate at a root,
  emit `cycleDetected`.

### Transform Mapping (Rest Pose)

Apply the decomposition from the §Skew Decomposition section to each bone's
`transform` field. Missing `transform` → identity (bony defaults apply, all
fields omitted).

Display `TransformObject` entries inside skin slot-displays represent the
image's placement within the slot's local frame. Apply the same skew
decomposition to obtain a bony attachment offset and rotation. The attachment
`scX` / `scY` map directly to attachment `scaleX` / `scaleY`. The attachment
`y` follows the same negation (`bony.y = -db.y`).

### Animation: Time Basis

DragonBones animation time is frame-based. Convert to seconds:

```
time_seconds = cumulative_frame_offset / armature.frameRate
```

Each `KeyframeObject` contributes `duration` frames. The cumulative offset of
keyframe `i` is the sum of `duration` fields of all prior keyframes in the
timeline. The first keyframe always begins at `t = 0`.

### Animation: Delta Transform Application

DragonBones animation keyframes carry a *delta* `TransformObject` relative to
the bone's rest pose. To obtain the absolute bone transform at keyframe `i`:

```
abs.x   = rest.x + delta.x      (no negation: delta is already in DB coord)
abs.y   = rest.y + delta.y      (negate after summing: bony.y = -(rest.y + delta.y))
abs.skX = rest.skX + delta.skX
abs.skY = rest.skY + delta.skY
abs.scX = rest.scX * delta.scX  (scale composes multiplicatively)
abs.scY = rest.scY * delta.scY
```

Then apply the skew decomposition to the absolute `(skX, skY, scX, scY, x, y)`
to obtain bony keyframe values. Scale defaults in `delta` are `1.0` (identity
multiplicative), not `0.0`.

If the importer encounters a timeline with no keyframe at `t = 0`, emit an
implicit keyframe at `t = 0` using the rest-pose transform (delta = identity).

### Animation: Easing

`tweenEasing` and `curve` control interpolation between this keyframe and the
next:

- `tweenEasing` absent or `null`: step / hold interpolation — no tween (the
  bony equivalent is a step keyframe; the value holds until the next keyframe).
- `tweenEasing = 0`: linear interpolation between keyframes.
- Any other numeric `tweenEasing` value: reject with `unsupportedFeature` in
  the first supported subset. Note: DragonBones uses non-zero easing values to
  encode ease-in / ease-out weight; mapping these to bony cubic keyframe curves
  is deferred.
- `curve` present (four numbers `[cx1, cy1, cx2, cy2]`): Bezier easing. Reject
  with `unsupportedFeature` in the first subset; the bony cubic keyframe format
  can eventually absorb these once the mapping is pinned.

## Supported Subset — Tier 1

Tier 1 is the implementation gate for `bony-g20`. Tier 1 support covers:

- Single-armature `_ske.json` files at format version 5.x.
- Bone hierarchy with rest-pose transforms.
- Default skin with image-type region displays.
- Animations with bone-only timelines (no slot color timelines, no FK/IK
  keyframes on constraint objects).
- Linear interpolation (`tweenEasing = 0`) and step/hold keyframes (`tweenEasing`
  absent or null).
- Positive `scX`, `scY` only; negative scale → `unsupportedFeature` in Tier 1.

Everything not in Tier 1 produces a diagnostic and non-zero exit status by
default. A future `--allow-drop=<feature>` flag may allow silent drops for
exploratory use.

### Explicitly Rejected

- Format version < 5.x (including 4.x and earlier).
- Multiple armatures beyond the first (partial support with diagnostic).
- Mesh and bounding-box displays.
- Slot color multipliers.
- Non-`normal` blend modes.
- IK constraints, transform constraints, path constraints defined in the JSON.
- Non-zero / non-null `tweenEasing` other than `0`.
- `curve` Bezier easing.
- Negative scale.
- Image atlas references not resolvable through the `--assets-dir` option.
- Any top-level key other than `name`, `version`, `armature`, `frameRate` in the
  armature object, `bone`, `slot`, `skin`, and `animation`.
- DragonBones `timelineType` fields or slot/constraint timeline entries beyond
  bone-transform timelines.

## CLI Shape

```
bony import-dragonbones input_ske.json output.bony [--assets-dir images/]
```

Initial options:

- `--assets-dir <path>`: directory containing referenced image assets. If absent
  the importer validates structure only and rejects any skin display that
  references an image (since there is no atlas to build from).
- `--setup-only`: emit rest-pose bones and skin only; reject all animation data.
- `--allow-multiple-armatures`: import the first armature silently, list the
  others in diagnostics, exit 0 instead of non-zero.

The command fails by default when it would silently drop bones, slots, skin
displays, or animation data. The only allowed silent drops are optional fields
that map to bony defaults.

## Diagnostics

| Code                   | Meaning                                                           |
| ---------------------- | ----------------------------------------------------------------- |
| `unsupportedVersion`   | Version string does not start with `"5."`                         |
| `unsupportedFeature`   | Recognized input that is out of the Tier 1 subset                 |
| `invalidReference`     | Parent bone, slot parent, or display name missing                 |
| `cycleDetected`        | Bone parent chain contains a cycle                                |
| `schemaViolation`      | Malformed input: wrong type, non-finite number, extra field, etc. |
| `multipleArmatures`    | File contains more than one armature (unless `--allow-multiple…`) |
| `missingAsset`         | Image display cannot be located under `--assets-dir`              |

Each diagnostic includes: code, armature name, bone/slot/animation name when
available, and a short human-readable message. Diagnostic text must not copy
DragonBones documentation prose.

## Conformance Gate for Implementation

Tier 1 implementation fixtures must cover:

- A two-bone hierarchy (root + child) with a non-trivial rest-pose transform
  on each bone, verifying the skew decomposition produces the correct bony JSON.
- A pure-rotation bone (`skX == skY`) confirming `shearY = 0`.
- A shearing bone (`skX ≠ skY`) confirming `shearY = skY - skX`.
- Negative `y` DragonBones → positive `y` bony (coordinate flip).
- An animated bone timeline with linear-interpolation keyframes sampling to
  expected world matrices via the CLI `play --t` golden.
- A step/hold timeline (no tween) producing the correct held value.
- A two-skin setup with image display mapping.
- Rejection fixtures for unsupported version, mesh display, Bezier easing,
  non-zero `tweenEasing`, non-`normal` blend mode, missing parent reference,
  parent cycle, and extra top-level field.

Numeric golden output compares the resulting `bony` JSON after canonicalization.
Rejection fixtures assert stable diagnostic code, bone/slot/animation name where
applicable, nonzero exit status, and no partial output file.

## Implementation Gate

Do not start the importer implementation (`bony-g20`) until:

- This design note is merged.
- The skew decomposition math has been validated against at least one
  user-supplied `_ske.json` sample file and the computed rest-pose matrix
  matches the expected visual pose.
- The Tier 1 conformance fixtures are committed or planned in the implementation
  bead.
- `docs/PROVENANCE.md` records this design note as the capability-context source
  for DragonBones wire-format field names.
