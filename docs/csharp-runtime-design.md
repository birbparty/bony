# C# Runtime Design Notes (Deferred — No v1 Implementation)

This document records design decisions and open questions for a future managed
.NET C# runtime. It is a design note only — no implementation is planned for
bony v1. It serves as a durable record so that if a C# runtime is built, the
key seams are designed in advance rather than bolted on after the fact.

---

## Motivation

Unity and Godot both have strong .NET ecosystems. A C# port of the bony runtime
would allow bony to run natively in both engines without a native-plugin layer.
The existing Nim runtime and Dart runtime demonstrate that the bony spec is
language-agnostic; C# is the natural third target for game-engine coverage.

---

## Codegen Strategy (Deferred)

The Nim and Dart runtimes are hand-maintained ports of the same specification.
At the scale of three runtimes the duplication is manageable; at four or more,
a codegen layer becomes attractive.

**Proposed approach (future):**

1. Define a canonical intermediate representation (IR) for the bony runtime
   logic — essentially, a language-neutral description of the sampling,
   mixing, and constraint algorithms expressed in terms of bony spec §§1–10
   operations.
2. Generate Nim, Dart, and C# source from the IR, leaving only the host-API
   adapter layer (renderer, asset I/O, engine integration) hand-written per
   target.
3. Codegen eliminates drift between runtimes: a spec change produces a single
   IR patch that fans out to all language targets.

**Prerequisite:** The Nim reference runtime must reach M10 full-featured
status first, so that the codegen IR captures the complete algorithm surface.
Codegen before full feature coverage would require re-fitting the IR at every
milestone, which is more expensive than hand-porting.

---

## Unity Embedder Seam

Unity uses a managed .NET runtime (Mono for player, CoreCLR for Editor). The
bony C# runtime would be a pure-managed assembly with no native-plugin
dependency.

### Asset loading

```
ISkeleton LoadSkeleton(byte[] bnbBytes)
ISkeleton LoadSkeleton(string jsonText)
```

- `ISkeleton` wraps an immutable `SkeletonData` value (mirrors
  `SkeletonData` in Nim / Dart).
- Unity's `Resources.Load<TextAsset>()` or `AssetDatabase` supplies the
  bytes. The bony runtime is agnostic to which Unity loading path is used.

### Rendering adapter

The rendering seam is `IDrawBatchConsumer`:

```csharp
interface IDrawBatchConsumer {
    void Begin();
    void Submit(DrawBatch batch);
    void End();
}
```

- `DrawBatch` is a value struct: slot name, bone name, texture page string,
  blend mode string (open value — unknown values are an error, not silently
  ignored), vertex array, index array.
- Unity renderer implements `IDrawBatchConsumer` using `Graphics.DrawMesh`
  or a `MeshRenderer` + `MaterialPropertyBlock` combination for each batch.
- The tint-black shader (dark/light two-colour blending) requires a custom
  shader; see `docs/drawbatch-raylib-contract.md` §Color And Two-Color Tint
  for the blend formula.

### Per-instance state

`SkeletonInstance` wraps a `ref SkeletonData` (or `readonly struct` depending
on the C# targeting tier) plus per-frame mutable bone transforms, slot
attachment state, and constraint cache. It is the unit passed to the animation
state machine and renderer each frame.

```csharp
var data   = BonyLoader.Load(bytes);
var inst   = new SkeletonInstance(data);
var anim   = new AnimationState(data);

// Per-frame:
anim.Update(deltaTime);
anim.Apply(inst);
inst.UpdateWorldTransforms();
var batches = inst.BuildDrawBatches();
consumer.Begin();
foreach (var b in batches) consumer.Submit(b);
consumer.End();
```

### Unity-specific considerations

- **Burst / Jobs**: The bone transform and draw-batch build passes are
  data-parallel and suitable for `IJob` / `Burst` compilation, provided the
  `SkeletonData` is either stored as a `BlobAsset` or pinned during the job.
  This is a perf optimisation, not an API requirement.
- **Asset serialisation**: `SkeletonData` should be serialisable as a
  `ScriptableObject` for baking into Unity's asset database, eliminating the
  JSON/BNB parse at runtime. The serialised form is opaque to the bony spec —
  it is a Unity-specific cache.

---

## Godot Embedder Seam

Godot 4 supports C# via GodotSharp/.NET 6+. The bony C# runtime would ship
as a pure-managed GodotSharp class library — no GDExtension (C/C++) layer
required.

### Asset loading

Godot's `FileAccess` or `ResourceLoader` supplies bytes; the bony loader API
is the same as the Unity seam above.

### Rendering adapter

Godot exposes `CanvasItem.DrawMesh()` and `RenderingServer.CanvasItemAddMesh()`
for mesh batches. The adapter wraps `DrawBatch` into `ArrayMesh` instances with
a `SurfaceTool`.

```csharp
class BonyCanvasItem : Node2D {
    public override void _Draw() {
        foreach (var b in _batches) {
            // Build ArrayMesh from b.Vertices / b.Indices
            // Apply material with b.BlendMode and b.TexturePage
            DrawMesh(mesh, material, transform);
        }
    }
}
```

### Godot-specific considerations

- **Signals**: Listener events from `StateMachineRuntime` (stateEnter,
  stateExit, transition) map naturally to Godot signals.
- **Export variables**: `StateMachineInput` values can be exposed as
  `[Export]` properties for editor wiring.

---

## Conformance-Vector Compatibility

The bony conformance harness (`conformance/`) runs numeric and image checks
against the Nim reference. A C# runtime must pass the same suite.

### Numeric compatibility

The conformance golden format (`bony.numeric-golden.v1`) records bone world
transforms and slot draw order as full-precision `float64` values. Numeric
comparison uses **absolute tolerance `1e-4`** (not significant-figure
rounding); string and integer fields are compared exactly. See
`conformance/README.md` §Numeric golden format and `docs/float-math-contract.md`
for the binding rules. C# `double` (IEEE 754 64-bit) matches Nim `float64`;
all cross-runtime numeric contracts apply unchanged.

Specific gate: `scripts/ci/conformance_run.py` invokes the CLI's `golden-gen`
subcommand. A C# runtime would need a companion CLI (`bony-cs`) that implements
the same `golden-gen` interface and emits the same JSON format.

### Image compatibility

The image gate (`scripts/ci/image_diff_check.py`) runs `bony play` and compares
against `conformance/goldens/`. A C# `bony-cs play` command would need to
produce pixel-identical output to the Nim software rasterizer, or the gate must
be extended to allow a per-runtime reference image (currently unimplemented).

The simplest approach: C# uses the same software rasterizer algorithm as
`runtime-nim/src/render/software_rasterizer.nim` (deterministic triangle fill,
bilinear UV sampling). The image gate (`scripts/ci/image_diff_check.py`)
allows ≤1 per-channel delta per pixel, so implementation-level rounding
differences are tolerated. This avoids needing per-runtime image goldens.

---

## Open Questions (To Resolve Before Implementation Starts)

1. **Codegen vs hand-port**: Is the bony spec stable enough at C# start time
   to commit to codegen? Or is hand-porting still cheaper at that scale?

2. **Burst / DOTS compatibility**: If Unity's Burst/Jobs path is desired, the
   data model must be `unmanaged`-compatible (no heap references in hot structs).
   This constrains `SkeletonData` to a `BlobAsset`-friendly form, which may
   diverge from the Dart idiom.

3. **IL2CPP stripping**: Unity's IL2CPP strips unused generics. Any generic
   animation timeline type must be anchored via `[Preserve]` or a link.xml.

4. **GodotSharp version floor**: Godot 4.2+ ships .NET 6 support. GDScript
   interop (exposing `[Signal]` from C# bony classes) requires Godot 4.1+.

5. **Image conformance strategy**: Bit-identical rasterizer output, or
   per-runtime golden images? The former is simpler; the latter is needed if
   Unity/Godot GPU rendering (not the software rasterizer) is used for the
   conformance image gate.

---

## Non-Goals for v1

- No C# runtime is implemented in bony v1.
- No codegen infrastructure is implemented in v1.
- No Unity package (.unitypackage or UPM) is published in v1.
- No Godot asset library entry is registered in v1.

These are recorded as deferred obligations, not active work items.
