# Lottie Importer Design Spike

This note defines the first `bony` Lottie importer target. It is a clean-room
design derived from the local `bony` specification and capability-level
knowledge only. It is not based on Lottie runtime source, importer code, or
third-party schema text.

## Goal

The importer is a migration tool for skeleton-less, timeline-driven 2D assets.
It converts a conservative subset into a `bony` document that can be played by
the normal CLI and conformance harness.

The importer is not a Lottie player and does not target feature parity or byte
compatibility. It must reject unsupported constructs with diagnostics instead
of silently approximating them unless this document explicitly allows an
approximation.

## Clean-Room Boundary

Implementation may use:

- User-supplied Lottie JSON files as input data.
- This design note, `docs/CLEANROOM.md`, and the binding `bony` spec.
- Public/textbook math for 2D affine transforms, Bezier curve sampling, polygon
  triangulation, color interpolation, and image packing.
- A public Lottie format specification may be proposed later as capability
  context, but it must be recorded in `docs/PROVENANCE.md` before use and must
  not be copied into code or docs. Until then, the implementation is limited to
  the project-owned input contract below.

Implementation must not fetch, inspect, copy, or derive from Lottie runtime
source, renderer source, importer source, generated schema files, or
third-party documentation prose. Field handling must be implemented from the
project-owned input contract below and from user-supplied fixtures that match
that contract. Unsupported or ambiguous constructs are rejected until this note
is updated.

## Importer-Owned Adapter Model

The importer should parse into an intermediate model before constructing
`SkeletonData`:

- `Composition`: width, height, frame rate, start frame, end frame, and ordered
  visual layers.
- `Layer`: stable name, visibility interval, parent reference, transform
  channels, opacity channel, blend mode, and one visual payload.
- `VisualPayload`: image rectangle, vector shape group, or null.
- `AnimatedChannel`: sorted keyframes with interpolation mode and optional
  cubic handles.

This intermediate model is project-owned. The importer should isolate any
input-field names at the parser boundary so the runtime, registry, and
conformance assets remain `bony`-native.

## Project-Owned Input Contract

The first implementation may recognize only the JSON shape described here. The
names below are accepted input keys because this design note owns that parser
contract for `bony`; they must not leak into runtime objects or generated
schema.

Composition object:

- `w`, `h`: positive integer width and height.
- `fr`: positive finite frame rate.
- `ip`, `op`: finite start and end frames, with `op > ip`.
- `assets`: optional array of image assets.
- `layers`: array of visual layers, ordered back-to-front.

Asset object:

- `id`: non-empty string, unique within `assets`.
- `path`: relative image filename under `--assets-dir`.
- `w`, `h`: positive integer pixel dimensions.

Layer object:

- `name`: non-empty stable string. If absent, the importer creates
  `layer_<index>`.
- `kind`: `image` or `shape`. The implementation may accept numeric or string
  input tags only at the parser boundary, but it must normalize them into this
  project-owned kind before validation.
- `parent`: optional layer index or layer name. Parent must appear anywhere in
  the same `layers` array and the graph must be acyclic.
- `in`, `out`: optional finite visibility interval in source frames. Defaults
  are composition `ip` and `op`.
- `blend`: optional string. Only `normal` is accepted initially.
- `transform`: object containing supported transform channels.
- `image`: object for `image` layers.
- `shapes`: array for `shape` layers.

Image layer payload:

- `asset`: required asset `id`.
- `anchor`: optional `[x, y]`, default `[0, 0]`.
- `size`: optional `[w, h]`; if absent, use the referenced asset dimensions.

Shape layer payload:

- `shapes`: ordered array of path records. Intra-layer draw order is array
  order.
- Path records are project-owned objects with `points`, `closed`, optional
  `fill`, and optional `stroke`.
- `points` is an array of cubic path vertices. Each vertex is `[x, y]` for a
  straight segment endpoint or `[x, y, inX, inY, outX, outY]` for explicit cubic
  handles in layer-local coordinates.

Transform object:

- `anchor`, `position`, `scale`, `rotation`, and `opacity` are animated
  channels.
- `anchor` and `position` are 2D vector channels.
- `scale` is a 2D vector channel expressed as percentages where `[100, 100]`
  means identity scale.
- `rotation` is a scalar channel in degrees.
- `opacity` is a scalar channel in the inclusive range `[0, 100]`.
- Non-`100` opacity values are parsed for diagnostics but rejected by the first
  setup-only importer because current `.bony` cannot serialize slot alpha.

Animated channel:

- Either a constant number/vector value, or an array of keyframes.
- A scalar keyframe is `{ "t": frame, "v": value, "curve": curve }`.
- A vector keyframe is `{ "t": frame, "v": [x, y], "curve": curve }`.
- `curve` is `hold`, `linear`, or `{ "cubic": [x1, y1, x2, y2] }`.
- Keyframes must be sorted by increasing `t`; duplicate frame keys are rejected.

Any input key outside this contract is rejected unless this document is updated
first. The implementation bead must add parser fixtures for every accepted
object above and rejection fixtures for unknown keys inside supported objects.

## First Importable Subset

The first implementation should accept files that satisfy all of these:

- One composition with a finite duration and positive frame rate.
- 2D layers only.
- Static layer ordering, mapped to `bony` slot order.
- Image layers with rectangular bounds and external image references.
- Shape layers only in Tier 2 after rasterization and atlas metadata are
  pinned.
- Static per-layer transform channels for translation, rotation, and scale.
- Per-layer transform animation for translation, rotation, and scale only after
  serialized `bony` animation clips exist.
- `opacity` must be absent, constant `100`, or rejected until slot alpha and
  opacity timelines are serializable.
- Hold, linear, and cubic-eased keyframes for supported animated transform
  channels once the animated importer tier is enabled.
- Parent-child layer transforms where the parent graph is acyclic.
- Normal blend mode only for the first pass.

The importer creates:

- One root bone named from the composition.
- One child bone per imported visual layer.
- One slot per imported visual layer, in source draw order.
- One region attachment per imported image or flattened shape payload.
- Atlas page names, UV rectangles, source-image paths, and packed-pixel output
  are prerequisites for visual-fidelity import because the current `.bony` JSON
  surface does not yet serialize atlas metadata.
- One `bony` animation clip containing supported transform timelines once those
  timelines are serializable in `.bony`.

If animation serialization, atlas metadata, or opacity timelines are not yet
available in `.bony` when the importer implementation starts, the importer must
be staged behind those prerequisites or emit the setup-only, geometry-only tier
defined below. It must not pretend animated input, image placement, atlas UVs,
or opacity were preserved.

## Implementation Tiers

Tier 1 is setup-only and geometry-only:

- Accept static transforms only.
- Reject any non-default opacity, visibility interval shorter than the full
  composition, animated transform, animated shape geometry, or unsupported image
  placement with `unsupportedFeature`.
- Emit `.bony` skeleton/bones/slots/regions that preserve layer hierarchy,
  draw order, dimensions, and setup transforms.
- Do not write `--atlas-out`; the command must reject that option until atlas
  metadata is serializable.

Tier 2 is visual-fidelity setup import:

- Requires serialized atlas page metadata, image references, UV rectangles, and
  pinned rasterization provenance.
- May enable `--atlas-out` and `--rasterize-shapes`.
- Must add image-diff or pixel-hash conformance for generated atlas output.

Tier 3 is animated import:

- Requires serialized `bony` animation clips and CLI playback of nonzero `--t`.
- May accept supported transform timelines.
- Requires numeric pose goldens from `golden-gen`.

Tier 4 is opacity import:

- Requires slot alpha/color serialization and opacity timeline support.
- May accept static or animated opacity.

## Shape Flattening Rule

The first visual-fidelity importer tier is raster-first. A vector shape layer
may be accepted only when it can be rendered at import time into a deterministic
atlas image without requiring runtime vector semantics.

Accepted shape features for flattening:

- Filled closed paths.
- Stroked paths with fixed stroke width.
- Solid color and alpha.
- Static or layer-transform-driven geometry.

Deterministic raster semantics for the first shape tier:

- Nonzero winding fill rule.
- Self-intersecting paths rejected.
- Stroke caps and joins are `butt` and `miter`; miter limit is `4`.
- Stroke width is in composition pixels before layer transform.
- Paths are drawn in source array order.
- Colors are interpreted as non-premultiplied sRGB with alpha and converted to
  the raster backend's deterministic pixel format at atlas-write time.
- Antialiasing must be either disabled or defined by the pinned raster backend
  and covered by image-diff tolerances before image goldens are required.
- Raster dimensions are the tight integer pixel bounds of the transformed shape
  inflated by stroke width, unless the CLI provides an explicit scale/padding
  option.
- Pixel bounds use floor for minimum coordinates and ceil for maximum
  coordinates after transform and stroke inflation.
- Atlas pixels are stored as premultiplied RGBA only after the atlas contract
  defines that page format; otherwise shape flattening remains disabled.

Rejected until a later vector tier:

- Path morphing.
- Trim path, dash animation, repeater-like procedural duplication, or merge
  operations.
- Text, glyph outlines, effects, expressions, masks, mattes, 3D cameras,
  lights, time remapping, audio, and scripting.
- Any feature whose result depends on a renderer-specific implementation detail
  that is not defined in `bony`.

The rasterization backend must be deterministic and covered by provenance as a
normal dependency before it becomes required. Generated atlas pixels become
`bony` output, not a hidden dependency on the source format.

## Coordinate And Time Mapping

- Composition pixel space maps to `bony` world units with the composition center
  as the initial root origin unless the CLI exposes an explicit origin option.
- Layer local transform is composed as `T(position) * R(rotation) * S(scale) *
  T(-anchor)`, using column-vector convention in layer-local coordinates.
  Parent layer transforms are applied by assigning the layer bone's parent to
  the parent layer bone and preserving the same local composition.
- Lottie-style frame time maps to seconds as `(frame - startFrame) / frameRate`.
- Keyframes are emitted with monotonically increasing seconds.
- Opacity maps to slot alpha or color-alpha timelines once available.
- Unsupported interpolation handles are rejected unless they can be represented
  by `bony`'s cubic keyframe curve.

## Diagnostics

The importer must produce deterministic diagnostics:

- `unsupportedFeature`: recognized but out-of-subset input.
- `unsupportedRendererSemantic`: input requires a rendering semantic not defined
  by `bony`.
- `invalidReference`: missing parent, image, or layer reference.
- `cycleDetected`: parent graph cycle.
- `schemaViolation`: malformed input shape, non-finite numbers, or wrong
  primitive type.

Diagnostics should include a layer name or index and a short capability label.
They should not include copied source-format prose.

## CLI Shape

Proposed command:

```text
bony import-lottie input.json output.bony --assets-dir images --atlas-out atlas.png
```

Initial options:

- `--setup-only`: emit Tier 1 setup pose only; reject all unsupported animated
  channels, visibility changes, non-default opacity, shape animation, and
  visual-fidelity atlas output.
- `--rasterize-shapes`: allow supported shape flattening.
- `--reject-shapes`: image-layer-only mode for early implementation.
- `--origin center|top-left`: choose composition-to-world origin.

The command must fail by default when it would drop animation, opacity, layers,
image placement, atlas metadata, or visual content.

## Conformance Gate For Implementation

Tier 1 implementation fixtures must cover:

- Image-only composition with two layers and different draw order.
- Parent-child layer transform composition.
- Static translation, rotation, scale, and anchor composition.
- Parser contract fixtures for composition, asset, image layer, shape layer,
  transform channel, and keyframe objects.
- Rejection fixtures for unknown keys in supported objects, text,
  masks/mattes, 3D/camera, time remap, expressions, path morphing, unsupported
  blend modes, duplicate keyframes, invalid references, parent cycles, duplicate
  or empty generated names, asset path traversal, missing external image files,
  non-finite dimensions/frame rates, unsupported interpolation handles,
  non-default opacity, visibility intervals, and any animation in Tier 1.

Tier 1 golden output should compare the resulting `bony` JSON after
canonicalization. Tier 3 must add at least one numeric pose sample from
`golden-gen`. Image-diff goldens may be added only in Tier 2 after the
rasterization backend and atlas page format are pinned.

Negative fixtures must assert stable diagnostic code, layer name or index when
available, capability label, nonzero exit status, and no partial output file.

## Implementation Gate

Do not start the importer implementation until:

- This design note is merged.
- The target `bony` JSON surface can serialize every field the importer claims
  to preserve.
- Atlas metadata, image references, UV rectangles, and page format are
  serializable before Tier 2 visual-fidelity output.
- Animation clips and nonzero-time CLI playback are serializable before Tier 3
  animated output.
- Slot alpha/color and opacity timelines are serializable before Tier 4 opacity
  output.
- Any rasterization dependency is covered by license/provenance evidence.
- The importer fixtures are committed or planned in the implementation bead.
