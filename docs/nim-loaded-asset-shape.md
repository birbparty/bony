# Nim Loaded Asset Shape For Animations And State Machines

This document decides the Nim loaded-asset shape for preserving animation and
state-machine data across `.bony -> .bnb -> .bony` round trips. It is a contract
decision only; it does not implement the new APIs and does not change CLI
state-machine playback behavior.

## Decision

Introduce a project-owned aggregate type, tentatively named `BonyAsset`, instead
of adding animations and state machines directly to `SkeletonData`.

Conceptual shape:

```nim
type
  BonyAsset* = object
    skeleton*: SkeletonData
    animations*: seq[AnimationClip]
    stateMachines*: seq[StateMachine]
```

The aggregate belongs in a module that can import `bony/model`,
`bony/anim/timelines`, and `bony/statemachine/core`, for example a future
`bony/asset.nim` or loader-owned module. It must not live in
`runtime-nim/src/bony/model.nim`.

## Why Not Extend `SkeletonData`

Keep `SkeletonData` as the immutable static setup/deformer model.

Reasons:

- `runtime-nim/src/bony/anim/timelines.nim` imports `bony/model`.
- `runtime-nim/src/bony/statemachine/core.nim` imports both `bony/model` and
  `bony/anim/timelines`.
- Adding `seq[AnimationClip]` and `seq[StateMachine]` fields to
  `SkeletonData` in `model.nim` would create a circular dependency unless the
  existing modules were split or inverted.
- Existing transform, draw, deformer, path, binary, and CLI setup paths consume
  `SkeletonData` as static data. Keeping that type narrow avoids forcing every
  setup-data user to depend on animation/state-machine types.
- Dart already stores animations and state machines on `SkeletonData`, but Nim
  does not need to mirror that exact loaded shape to preserve the same file
  data.

The aggregate is the file-level loaded asset. `SkeletonData` remains the
runtime setup-data payload inside that asset.

## Loader And Writer API Shape

Future implementation should add aggregate APIs while preserving existing
`SkeletonData` APIs:

```nim
proc loadBonyJsonAsset*(text: string): BonyAsset
proc toBonyJson*(asset: BonyAsset): string

proc loadBonyBnbAsset*(input: openArray[byte]): BonyAsset
proc toBonyBnb*(asset: BonyAsset; embeddedAtlas: openArray[byte] = []): seq[byte]
```

Existing APIs remain valid:

```nim
proc loadBonyJson*(text: string): SkeletonData
proc toBonyJson*(data: SkeletonData): string
proc loadBonyBnb*(input: openArray[byte]): SkeletonData
proc loadKnownBonyBnb*(input: openArray[byte]): SkeletonData
proc toBonyBnb*(data: SkeletonData; embeddedAtlas: openArray[byte] = []): seq[byte]
```

Compatibility behavior:

- `loadBonyJson` continues to return only static `SkeletonData`.
- `toBonyJson(SkeletonData)` continues to emit only static setup/deformer data.
- `loadBonyBnb` and `loadKnownBonyBnb` continue to return `SkeletonData`.
- `toBonyBnb(SkeletonData)` continues to emit only currently supported
  setup/deformer records.
- Aggregate APIs own animation/state-machine preservation and should be used by
  conversion tools once the binary records are implemented.

This keeps existing setup/deformer binary APIs working while giving
round-trip tools a lossless asset-level path.

## JSON Preservation

`loadBonyJsonAsset` should parse the same source once into:

- `skeleton`: the result of the existing static JSON load path.
- `animations`: the animation clips currently returned by
  `loadBonyJsonAnimations`, preserving source order rather than table iteration
  order.
- `stateMachines`: the machines currently returned by
  `loadBonyJsonStateMachines`, preserving source order.

The implementation may share parser internals with existing `jsonio.nim`, but
the observable aggregate behavior must be:

```text
loadBonyJsonAsset(.bony).skeleton == loadBonyJson(.bony)
loadBonyJsonAsset(.bony).animations == parsed animations in source order
loadBonyJsonAsset(.bony).stateMachines == parsed state machines in source order
```

`toBonyJson(BonyAsset)` should emit the existing static JSON fields plus
`animations` and `stateMachines` when the corresponding sequences are non-empty.
It should continue using canonical static `toBonyJson(SkeletonData)` rules for
setup/deformer fields, then append aggregate-owned fields using the canonical
ordering chosen by the binary/JSON contract follow-up.

## Binary Preservation

`toBonyBnb(BonyAsset)` should emit:

1. Existing `SkeletonData` object families in the current canonical order.
2. Animation and state-machine object families chosen in
   [binary-animation-state-machine-object-families.md](binary-animation-state-machine-object-families.md).

`loadBonyBnbAsset` should decode known static, animation, and state-machine
records into one `BonyAsset`. It must validate animation and state-machine
references after static objects and animation clips are known:

- Bone/slot/region indices resolve against `asset.skeleton`.
- State-machine clip and blend-clip references resolve against
  `asset.animations`.
- Layer, state, input, transition, and listener references resolve in their
  owning machine scopes.

Existing `loadBonyBnb` / `loadKnownBonyBnb` can remain static-data APIs. Once
animation/state-machine records exist, they may internally call
`loadBonyBnbAsset(input).skeleton` or continue using a static-only decoder, but
their return value must remain `SkeletonData` for compatibility.

## Conversion Path

Lossless animation/state-machine conversion uses aggregate APIs:

```text
.bony text
  -> loadBonyJsonAsset
  -> toBonyBnb(BonyAsset)
  -> loadBonyBnbAsset
  -> toBonyJson(BonyAsset)
  -> .bony text with animations/stateMachines preserved
```

Existing static conversion remains available for callers that intentionally
operate only on `SkeletonData`:

```text
.bony text
  -> loadBonyJson
  -> toBonyBnb(SkeletonData)
  -> loadKnownBonyBnb
  -> toBonyJson(SkeletonData)
```

The CLI `json-to-bnb` and `bnb-to-json` commands should switch to aggregate APIs
only when the binary animation/state-machine records and canonical JSON emission
are implemented. Until then, the current static behavior remains correct for
registered setup/deformer data.

## State-Machine Playback Boundary

Do not remove the existing `.bnb` state-machine playback rejection in
`cli/bony_cli.nim`.

The current CLI path for state-machine execution reads `.bony` text, uses
`loadBonyJson` for static skeleton data, and uses `loadBonyJsonStateMachines`
for state-machine data. It explicitly rejects `.bnb` assets for input-script
state-machine playback. This rejection should remain until a later runtime
implementation bead wires `loadBonyBnbAsset` through playback, input scripts,
pose projection, and conformance coverage.

Preserving state-machine data in `.bnb` is a file conversion contract. It is not
permission to claim `.bnb` state-machine playback support before the runtime
path exists.

## Follow-Up Work

This decision leaves implementation to dependent Beads:

- Define the aggregate type and API module.
- Refactor JSON parser internals so animation order is preserved without
  duplicate parsing where practical.
- Implement aggregate `.bnb` encode/decode after registry keys exist.
- Switch conversion CLI commands to aggregate APIs when binary
  animation/state-machine records are implemented.
- Keep state-machine playback rejection for `.bnb` until a dedicated runtime
  playback Bead removes it with tests.
