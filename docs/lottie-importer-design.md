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

Implementation must not fetch, inspect, copy, or derive from Lottie runtime
source, renderer source, importer source, or generated schema files. Field
handling should be implemented from the importer-owned adapter model below and
from observed user input fixtures, with unsupported or ambiguous constructs
rejected until documented here.

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

## First Importable Subset

The first implementation should accept files that satisfy all of these:

- One composition with a finite duration and positive frame rate.
- 2D layers only.
- Static layer ordering, mapped to `bony` slot order.
- Image layers with rectangular bounds and external image references.
- Shape layers that can be flattened by the importer to a static raster image
  at import time.
- Per-layer transform animation for translation, rotation, scale, and opacity.
- Hold, linear, and cubic-eased keyframes for supported transform channels.
- Parent-child layer transforms where the parent graph is acyclic.
- Normal blend mode only for the first pass.

The importer creates:

- One root bone named from the composition.
- One child bone per imported visual layer.
- One slot per imported visual layer, in source draw order.
- One region attachment per imported image or flattened shape payload.
- One generated atlas entry per imported raster payload.
- One `bony` animation clip containing supported transform and opacity
  timelines once those timelines are serializable in `.bony`.

If animation serialization is not yet available in `.bony` when the importer
implementation starts, the importer must be staged behind that prerequisite or
emit a documented setup-pose-only diagnostic mode. It must not pretend animated
input was preserved.

## Shape Flattening Rule

The first importer is raster-first. A vector shape layer may be accepted only
when it can be rendered at import time into a deterministic atlas image without
requiring runtime vector semantics.

Accepted shape features for flattening:

- Filled closed paths.
- Stroked paths with fixed stroke width.
- Solid color and alpha.
- Static or layer-transform-driven geometry.

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
- Layer anchor, position, scale, and rotation are composed into the layer bone's
  local transform. The importer must document and test the exact multiplication
  order it chooses before implementation closes.
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

- `--setup-only`: emit setup pose and atlas output, rejecting animation only if
  transform timelines are present.
- `--rasterize-shapes`: allow supported shape flattening.
- `--reject-shapes`: image-layer-only mode for early implementation.
- `--origin center|top-left`: choose composition-to-world origin.

The command must fail by default when it would drop animation, layers, or visual
content.

## Conformance Gate For Implementation

The importer implementation bead must add fixtures that cover:

- Image-only composition with two layers and different draw order.
- Parent-child layer transform composition.
- Translation, rotation, scale, and opacity animation using hold, linear, and
  cubic-eased keys.
- Shape flattening for a filled closed path if `--rasterize-shapes` ships.
- Rejection fixtures for text, masks/mattes, 3D/camera, time remap, expressions,
  and path morphing.

Golden output should compare the resulting `bony` JSON after canonicalization
and at least one numeric pose sample from `golden-gen`. Image-diff goldens may
be added once the rasterization backend is pinned.

## Implementation Gate

Do not start the importer implementation until:

- This design note is merged.
- The target `bony` JSON surface can serialize every field the importer claims
  to preserve.
- Any rasterization dependency is covered by license/provenance evidence.
- The importer fixtures are committed or planned in the implementation bead.
