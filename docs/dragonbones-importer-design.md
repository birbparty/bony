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
derives the mapping from first principles. The mapping is bijective for non-zero
`scX` and `scY`; Tier 1 additionally restricts to positive scale (see
§Supported Subset).

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
- **Negative scale** (`scX < 0` or `scY < 0`): the mapping formula is
  mathematically valid for negative scale (the angle equations hold when both
  sides share the same negative sign factor). However, Tier 1 rejects negative
  `scX`/`scY` as `unsupportedFeature`. If negative scale is added in a future
  tier, it must not be folded into the reflection factor; that matches
  `docs/transform-composition-contract.md` §Reflection.
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
scY = 1`. Mapping: `rotation = -30°`, `shearY = 30 - 30 = 0`. Bony matrix:

```
xAngle = -30°,  yAngle = -30° + 90° = 60°
[ cos(-30°)   cos(60°)  ] = [  √3/2  1/2  ]
[ sin(-30°)   sin(60°)  ]   [ -1/2   √3/2 ]
```

Bony `rotation = -30°` is a -30° rotation (30° clockwise in Y-up CCW convention),
which is the correct representation of the same physical pose. ✓

For a shear case: `skX = 45°`, `skY = 0°`, `scX = scY = 1`. Mapping:
`rotation = 0°`, `shearY = 0 - 45 = -45°`. Bony `xAngle = 0`, `yAngle = 90 + (-45) = 45°`:

```
[ cos(0°)    cos(45°)  ] = [ 1     √2/2 ]
[ sin(0°)    sin(45°)  ]   [ 0     √2/2 ]
```

The X axis is unrotated; the Y axis leans toward the X axis by 45°. This is
a genuine shear (det = √2/2 ≠ 1), matching the DragonBones skewed-Y interpretation. ✓

## Format Validation Against Sample Data

The following findings are based on examination of `_ske.json` files from the
DragonBonesJS Pixi demo resources at
`~/git/DragonBonesJS/Pixi/Demos/resource/` (user-supplied input data; not
runtime source). These findings supersede any prior assumptions in this document.

### Skew Decomposition: Confirmed Correct

The mapping `rotation = -skY`, `shearY = skY - skX`, `scaleX = scX`,
`scaleY = scY`, `x = x`, `y = -y` was validated against all 20 bones in
`mecha_1004d_ske.json`. Maximum matrix entry error < 1e-8. Including a bone
with genuine shear (`effect_r`: `skX = -46.2343°`, `skY = -23.9186°`,
`scX = 2.1416`, `scY = 2.3753`).

### Animation Structure: Per-Channel Frame Arrays (Correction)

Animation keyframes are **not** a unified `transform` delta on a single `frame`
array. Instead, each bone timeline carries **separate per-channel arrays**:

- `translateFrame`: translation keyframes (x/y additive deltas)
- `rotateFrame`: rotation keyframes (`rotate` = additive delta to both skX and
  skY; optional `clockwise` = arc direction hint)
- `scaleFrame`: scale keyframes (x/y = scale multipliers applied to rest
  scX/scY, final = rest × value; default 1.0)

Each channel is independent; a bone may animate only translation and not
rotation, for example.

### Terminator Frame: Validated

Every channel array ends with a frame whose `duration` is `0`. This is the
terminator: it defines the animation endpoint value (the loop restart point).
The sum of **all** frame durations including the terminator equals
`animation.duration`. Validated: mecha_1004d idle animation, `duration: 60`,
pelvis `translateFrame` durations sum = 30 + 30 + 0 = 60 ✓.

### Rotation Delta: Adds to Both skX and skY

`rotateFrame.rotate` is an additive rotation delta (degrees) applied equally to
both `skX` and `skY`. This preserves the original shear: if a bone had a
non-zero `shearY = skY - skX`, animation does not change it.

Validated: pelvis bone (rest `skX = skY = -174.7594°`), `rotate = -1.5°` at
frame 30. Animated abs `skX = skY = -176.2594°`; `bony.rotation = 176.2594°`;
`bony.shearY = 0` (unchanged). ✓

The `clockwise` field (integer 0 or 1) appears on some `rotateFrame` entries
to resolve arc direction ambiguity when the rotation delta is near ±180°. Tier
1 rejects `clockwise` as `unsupportedFeature`; shortest-arc handling is deferred
to a later tier.

### Translation Delta: Additive (Validated)

`translateFrame` `x` and `y` fields are additive offsets from the rest pose in
DragonBones Y-down coordinates. Default (absent) = 0.

Validated: pelvis bone (rest `x = -0.0889`, `y = 0.543`), frame-30 delta
`x = -1.95`, `y = 0.01`. Bony animated values: `x = -0.0889 + (-1.95) = -2.039`,
`y = -(0.543 + 0.01) = -0.553`. ✓

### Scale Delta: Multiplicative (Validated Structurally)

`scaleFrame` `x` and `y` are scale multipliers applied to the bone's rest
`scX`/`scY` (final = rest × value). Default (absent) = 1.0 (identity).
Validated structurally: all observed rest scales in the sample are near 1.0
(e.g., squash-and-stretch deviations of 0.99, 1.01), so the multiplicative
vs. absolute distinction is **not** numerically discriminated by the sample.
The required scale-channel golden fixture (§Conformance Gate) pins this choice.

### Observed Field Set (Complete)

All field names in `_ske.json` files observed in the sample set:

**Top-level**: `name`, `version`, `compatibleVersion`, `armature`, `frameRate`
(duplicate of armature frameRate), `isGlobal`, `textureAtlas` (inline atlas for
some exports). None affect import; `version` and `armature` are the only parsed
fields.

**ArmatureObject extra fields**: `aabb` (bounding box hint), `defaultActions`,
`ik` (IK constraint list), `canvas` (canvas size hint). None affect Tier 1 bone
or skin import.

**AnimationObject extra fields**: `fadeInTime`, `playTimes`, `blendType`,
`type`, `frame` (global event frames, separate from bone frames), `slot` (slot
channel list), `ffd` (mesh free-form deform channels, always empty in Tier 1
scope).

**rotateFrame**: `duration`, `rotate`, `tweenEasing`, `curve`, `clockwise`.

**translateFrame**: `duration`, `x`, `y`, `tweenEasing`, `curve`.

**scaleFrame**: `duration`, `x`, `y`, `tweenEasing`, `curve`.

**Slot channel types**: `colorFrame` and `displayFrame` (both Tier 1 rejects).

**colorFrame**: `duration`, `tweenEasing`, `curve`, `value`/`color` (both
spellings observed; object with `aM`, `rM`, `gM`, `bM` in 0–100 percent range).

**displayFrame**: `duration`, `value` (integer display index; -1 = hidden).

## Importer-Owned Adapter Model

The importer should parse into an intermediate model before constructing
`SkeletonData`:

- `DbSkeleton`: version string, top-level name, armature list.
- `DbArmature`: name, frame-rate, bone list, slot list, skin list, animation
  list.
- `DbBone`: name, optional parent name, optional `DbTransform` (rest-pose).
- `DbSlot`: name, parent bone name, draw-order index, optional blend mode.
- `DbSkin`: name, display entries per slot.
- `DbDisplay`: name, display type, optional `DbTransform`, optional dimensions.
- `DbAnimation`: name, duration in frames, bone channel list.
- `DbBoneChannels`: bone name, optional translate-frame list, optional
  rotate-frame list, optional scale-frame list.
- `DbTranslateFrame`: duration (frames), x delta, y delta, tween easing, optional
  curve.
- `DbRotateFrame`: duration (frames), rotate delta (degrees), tween easing,
  optional curve, optional clockwise hint.
- `DbScaleFrame`: duration (frames), scX multiplier, scY multiplier, tween
  easing, optional curve.
- `DbTransform`: x, y, skX, skY, scX, scY — all optional with defaults.

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
  "name":     string,           // optional, ignored
  "version":  string,           // required; must start with "5."
  "armature": [ ArmatureObject ]  // required, non-empty
}
```

Required keys: `version`, `armature`. Optional known keys (`name`,
`compatibleVersion`, `frameRate`, `isGlobal`, `textureAtlas`) are silently
ignored. Unknown keys beyond these are also silently ignored at the top level.

The importer rejects version strings that do not begin with `"5."`. Earlier
DragonBones versions used different transform semantics; the math above applies
only to `_ske.json` format version 5.x files.

### ArmatureObject

```
{
  "name":      string,                // required
  "frameRate": number,                // required, integer > 0
  "type":      "Armature",           // required; must equal "Armature"
  "bone":      [ BoneObject ],       // required, non-empty
  "slot":      [ SlotObject ],       // optional; absent or empty = no slots
  "skin":      [ SkinObject ],       // optional; absent or empty = no skins
  "animation": [ AnimationObject ]   // optional; absent or empty = static rig
}
```

Required keys: `name`, `frameRate`, `type`, `bone`. Optional known keys
(`slot`, `skin`, `animation`, `aabb`, `defaultActions`, `ik`, `canvas`) are
parsed or silently ignored as noted. Unknown keys beyond these are silently
ignored at the armature level.

A static rig (no `animation` key, or empty `animation` array) is valid input. The
`--setup-only` flag also suppresses any animation present in the file. Both paths
produce identical bony output: bones and skin only, no animation clips.

Multi-armature files: the importer converts the first armature and emits a
`multipleArmatures` diagnostic listing ignored armature names. Exit status is
non-zero unless `--allow-multiple-armatures` is passed.

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
  "name":         string,              // required
  "parent":       string,             // required, references a BoneObject name
  "displayIndex": number,             // optional, integer ≥ 0; default 0
  "color":        ColorMultiplierObject,  // optional; see §Color
  "blendMode":    string              // optional; see §Blend Mode
}
```

`displayIndex` selects which display in the slot's display list is active at the
rest pose. Out-of-range values (negative or beyond the display array length) are
a `schemaViolation`. A `displayIndex` of `-1` (hidden slot) is also rejected as
`unsupportedFeature` in Tier 1.

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
  "name":     string,                  // required
  "duration": number,                  // required, integer frames > 0
  "bone": [ BoneChannelObject ],       // optional; absent or empty = static
  "slot": [ SlotChannelObject ]        // optional; all slot channels rejected in Tier 1
}
```

Other fields (`fadeInTime`, `playTimes`, `blendType`, `type`, `frame`, `ffd`)
are silently ignored.

### BoneChannelObject

A bone's per-channel animation data. All channel arrays are optional; a bone
not listed has no animation (holds rest pose throughout).

```
{
  "name":           string,               // required; references a BoneObject name
  "translateFrame": [ TranslateFrame ],   // optional
  "rotateFrame":    [ RotateFrame ],      // optional
  "scaleFrame":     [ ScaleFrame ]        // optional
}
```

A `BoneChannelObject.name` that does not match any declared bone in the armature
→ `invalidReference`.

### TranslateFrame

```
{
  "duration":    number,        // required, integer ≥ 0; 0 = terminator
  "x":           number,        // optional; additive x delta; default 0
  "y":           number,        // optional; additive y delta; default 0
  "tweenEasing": number | null, // optional; see §Easing
  "curve":       [ number ]     // optional; see §Easing
}
```

### RotateFrame

```
{
  "duration":    number,        // required, integer ≥ 0; 0 = terminator
  "rotate":      number,        // optional; rotation delta in degrees; default 0
  "clockwise":   number,        // optional; 0 or 1; arc direction hint; see §Easing
  "tweenEasing": number | null, // optional; see §Easing
  "curve":       [ number ]     // optional; see §Easing
}
```

### ScaleFrame

```
{
  "duration":    number,        // required, integer ≥ 0; 0 = terminator
  "x":           number,        // optional; scX multiplier; default 1.0
  "y":           number,        // optional; scY multiplier; default 1.0
  "tweenEasing": number | null, // optional; see §Easing
  "curve":       [ number ]     // optional; see §Easing
}
```

### SlotChannelObject

```
{
  "name":         string,               // required; references a SlotObject name
  "colorFrame":   [ ColorFrame ],       // optional; Tier 1: unsupportedFeature
  "displayFrame": [ DisplayFrame ]      // optional; Tier 1: unsupportedFeature
}
```

### ColorFrame

```
{
  "duration":    number,        // required, integer ≥ 0
  "value":       ColorMultiplierObject,  // optional; or key "color" (alias)
  "tweenEasing": number | null,
  "curve":       [ number ]
}
```

### DisplayFrame

```
{
  "duration": number,           // required, integer ≥ 0
  "value":    number            // optional; display index; -1 = hidden
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

| DragonBones concept          | bony concept                         |
| ---------------------------- | ------------------------------------ |
| Armature                     | `SkeletonData`                       |
| Bone (name, parent)          | `Bone` (name, parent)                |
| Bone rest-pose transform     | Bone `x`, `y`, `rotation`, etc.      |
| Slot (name, parent bone)     | `Slot` (name, bone)                  |
| Skin (name)                  | `Skin` (name)                        |
| Image display in skin        | `RegionAttachment` in skin           |
| Animation (name, duration)   | `AnimationClip` (name)               |
| `translateFrame` channel     | Separate X and Y translation timelines |
| `rotateFrame` channel        | Rotation timeline (shearY stays constant) |
| `scaleFrame` channel         | Separate scaleX and scaleY timelines |
| TranslateFrame/RotateFrame/ScaleFrame with `duration` | Keyframe in property timeline |

### Bone Hierarchy

Bones are emitted in the order they appear in the `bone` array. The importer
validates that:
- Every `parent` reference names a bone declared in the same armature (two-pass:
  collect all names, then validate parents). `invalidReference` if any parent
  name is missing.
- Exactly one root exists (a bone with no `parent`, or with `parent` absent or
  the empty string). `schemaViolation` if zero or multiple roots are found.
- No cycles exist. Use a depth-first ancestor walk; if any bone's parent chain
  does not terminate at the root, emit `cycleDetected`.

DragonBones files exported by standard tools put parents before children, but
the two-pass validation accepts any ordering and avoids spurious
`invalidReference` errors from bottom-up exports.

### Transform Mapping (Rest Pose)

Apply the decomposition from the §Skew Decomposition section to each bone's
`transform` field. Missing `transform` → identity (bony defaults apply, all
fields omitted).

Display `TransformObject` entries inside skin slot-displays represent the
image's placement within the slot's local frame. Apply the same skew
decomposition to obtain a bony attachment offset and rotation. The attachment
`scX` / `scY` map directly to attachment `scaleX` / `scaleY`. The attachment
`y` follows the same negation (`bony.y = -db.y`).

### Animation: Time Basis and Terminator Frame

DragonBones animation time is frame-based. Convert to seconds:

```
time_seconds = cumulative_frame_offset / armature.frameRate
```

`armature.frameRate` is the authoritative rate (required, integer > 0; see
ArmatureObject). A top-level `frameRate`, if present, is ignored even if it
disagrees with the armature value.

Each channel frame's `duration` is the number of frames from that keyframe to
the next. The cumulative offset of keyframe `i` is the sum of `duration` fields
of all prior keyframes in that channel.

Every non-empty channel array must end with a **terminator frame** whose
`duration` is `0`. The terminator defines the animation endpoint value (the
loop-restart pose). The sum of all durations **including the terminator** must
equal `animation.duration`. Validated: mecha_1004d idle, pelvis `translateFrame`
durations 30 + 30 + 0 = 60 = `animation.duration`. ✓

If the sum does not equal `animation.duration` — whether from a missing
terminator (sum < duration) or extra frames (sum > duration) — emit
`schemaViolation`. Both cases are symmetric rejections.

**Start coverage.** The cumulative offset of a channel's first frame is `0` by
definition (no prior durations), so every present channel has an explicit value
at `t = 0`. A property with no channel holds its rest-pose value for the entire
clip and contributes no bony keyframes.

### Animation: Per-Channel Animated Values

Each channel produces an independent bony timeline. The formulas below define
the bone's value **at each DragonBones keyframe sample point**, not a continuous
function of time. The importer emits one bony keyframe per DragonBones channel
frame, carrying that frame's `tweenEasing` as the bony keyframe's interpolation
mode (linear or step). Between keyframes, bony interpolates its own native
channels.

This per-channel decompose-then-emit mapping is valid because the rest-pose
decomposition is **affine** in `(skX, skY)`: `rotation = -skY` and
`shearY = skY - skX`. Linearly interpolating `skX`/`skY` is therefore identical
to linearly interpolating bony `rotation`/`shearY`, so decomposing each keyframe
and letting bony interpolate yields the same path as interpolating the
DragonBones delta and decomposing. For scale, `rest.scX × lerp(m0, m1) =
lerp(rest.scX×m0, rest.scX×m1)`, so the same equivalence holds.

**Translation channel** (`translateFrame`):

```
bony.x[t] = rest.x + translateFrame.x_delta[t]    (x_delta default: 0)
bony.y[t] = -(rest.y + translateFrame.y_delta[t])  (y_delta default: 0)
```

Produces two bony keyframe timelines: one for `x` and one for `y`. Both are
linear (or step) between sampled keyframe values.

**Rotation channel** (`rotateFrame`):

```
abs.skX[t] = rest.skX + rotateFrame.rotate[t]     (rotate default: 0)
abs.skY[t] = rest.skY + rotateFrame.rotate[t]
bony.rotation[t] = -abs.skY[t]
bony.shearY[t]   = rest_bony_shearY                (constant; animation does not change shear)
```

Validated: pelvis bone, `rotate = -1.5°` at frame 30 →
`bony.rotation = 176.2594°`, `bony.shearY = 0` (unchanged from rest). ✓

`bony.shearX` is always `0` (canonical choice; rotation does not introduce shear).

The `clockwise` field on a `RotateFrame` entry (value 0 or 1) is a direction
hint for interpolation when the rotation arc crosses ±180°. Tier 1 rejects
`clockwise` as `unsupportedFeature`; shortest-arc handling is deferred to a
later tier. Conformance fixtures must include a `clockwise` rejection case.

**Scale channel** (`scaleFrame`):

```
bony.scaleX[t] = rest.scX * scaleFrame.x[t]   (x default: 1.0)
bony.scaleY[t] = rest.scY * scaleFrame.y[t]   (y default: 1.0)
```

Produces two bony keyframe timelines: one for `scaleX` and one for `scaleY`.

**Channels that are absent** produce no bony keyframes for that property; the
property holds its rest-pose value throughout the animation.

### Animation: Easing

`tweenEasing` and `curve` fields appear on all per-channel frame types
(`TranslateFrame`, `RotateFrame`, `ScaleFrame`, `ColorFrame`). They control
interpolation between this keyframe and the next.

- `tweenEasing` absent or `null`: step / hold — value holds until next keyframe.
  Bony equivalent: step keyframe.
- `tweenEasing = 0`: linear interpolation. Bony equivalent: linear keyframe.
- Any other numeric `tweenEasing`: reject with `unsupportedFeature` in Tier 1.
  (DragonBones uses non-zero values for ease-in/ease-out weight; mapping to
  bony cubic keyframe curves is deferred.)
- `curve` present (array of four numbers `[cx1, cy1, cx2, cy2]`): Bezier easing.
  Well-formed four-element `curve` → `unsupportedFeature` in Tier 1. Malformed
  `curve` (wrong type, wrong arity) → `schemaViolation`. Confirmed present in
  the sample set (`colorFrame`, `rotateFrame`).

**Last/terminator keyframe**: the terminator frame (`duration = 0`) sets the
endpoint value. It has no successor to tween toward; its easing field is ignored.

**`clockwise` hint**: present on some `rotateFrame` entries to resolve direction
when the `rotate` delta crosses ±180°. Tier 1 rejects `clockwise` as
`unsupportedFeature`; shortest-arc handling is deferred to a later tier.
Conformance fixtures must include a `clockwise` rejection case.

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
- Unknown keys in a `TransformObject` (strict; all 6 fields are listed).
- `displayIndex = -1` (hidden slot) or any out-of-range `displayIndex`.
- `SlotChannelObject` entries (any `colorFrame` or `displayFrame`) →
  `unsupportedFeature`. Slot animation is deferred to a later tier.
- `clockwise` field in `rotateFrame` → `unsupportedFeature` in Tier 1.
- Non-finite angles (`skX`, `skY`) or zero/non-finite scale (`scX`, `scY`) in
  any `TransformObject` → `schemaViolation`.
- Well-formed four-element `curve` arrays → `unsupportedFeature`.
- Malformed `curve` (not array, or not exactly four numbers) → `schemaViolation`.

## CLI Shape

```
bony import-dragonbones input_ske.json output.bony [--assets-dir images/]
```

Initial options:

- `--assets-dir <path>`: directory containing referenced image assets. If absent
  the importer validates structure only and rejects any skin display that
  references an image (since there is no atlas to build from).
- `--setup-only`: emit rest-pose bones and skin only; reject all animation data.
- `--allow-multiple-armatures`: import the first armature, list the others in a
  `multipleArmatures` diagnostic, and exit 0. Without this flag, a
  multi-armature file exits non-zero with the same `multipleArmatures` diagnostic
  before any conversion occurs.

The command fails by default when it would silently drop bones, slots, skin
displays, or animation data. The only allowed silent drops are optional fields
that map to bony defaults.

## Diagnostics

| Code                   | Meaning                                                           |
| ---------------------- | ----------------------------------------------------------------- |
| `unsupportedVersion`   | Version string does not start with `"5."`                         |
| `unsupportedFeature`   | Recognized input that is out of the Tier 1 subset                 |
| `invalidReference`     | Parent bone, slot parent, display, or animation-channel target name missing |
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
- A static rig with no `animation` key (confirming valid empty-animation path).
- An animated bone timeline with at least one `translateFrame`, one
  `rotateFrame`, and one `scaleFrame` channel; linear-interpolation keyframes;
  world matrices sampled via `play --t` golden with hand-computed expected values.
- A single-channel animation (only `translateFrame`) confirming `rotation`,
  `scaleX`, `scaleY`, and `shearY` hold their rest-pose values throughout.
- An animation whose `bone` list omits a rigged bone, confirming that bone holds
  its full rest pose for the clip's duration.
- A step/hold timeline (no tween) producing the correct held value.
- A single-keyframe timeline (last-keyframe hold behavior regardless of easing).
- A timeline whose keyframe durations sum to exactly `animation.duration`.
- A two-skin setup with image display mapping.
- Rejection fixtures for: unsupported version, mesh display, well-formed Bezier
  `curve`, non-zero `tweenEasing`, non-`normal` blend mode, `clockwise` in
  rotateFrame, slot channel (`colorFrame`/`displayFrame`), missing parent bone
  reference, parent cycle, extra `TransformObject` key, non-finite `skX`,
  zero `scX`, `displayIndex = -1`, out-of-range `displayIndex`, and keyframe
  duration sum exceeding `animation.duration`.

Numeric golden output compares the resulting `bony` JSON after canonicalization.
Rejection fixtures assert stable diagnostic code, bone/slot/animation name where
applicable, nonzero exit status, and no partial output file.

## Implementation Gate

Do not start the importer implementation (`bony-g20`) until:

- This design note is merged.
- The Tier 1 conformance fixtures are committed or planned in the implementation
  bead.
- `docs/PROVENANCE.md` records this design note as the capability-context source
  for DragonBones wire-format field names.

The following gates were met during the design spike (see §Format Validation).
Validation evidence is from examination of files in the local DragonBonesJS
clone at `~/git/DragonBonesJS/Pixi/Demos/resource/` (not committed to bony).

- [x] Skew decomposition validated against real `_ske.json` bones (20 bones,
  max error < 1e-8 against mecha_1004d_ske.json, including a shear bone).
- [x] Per-channel animation structure confirmed (translateFrame, rotateFrame,
  scaleFrame with additive/multiplicative semantics and terminator frame).
- [x] Rotation delta confirmed to add to both skX and skY (preserves shearY).
- [x] Terminator frame (duration=0) confirmed; sum of durations = animation.duration.
- [x] Format field survey complete (§Format Validation §Observed Field Set).
- [~] Scale channel semantics: structurally validated only; multiplicative
  vs. absolute not numerically discriminated (rest scales ≈ 1.0 in sample).
  Pinned by the required scale golden fixture in the conformance suite.
