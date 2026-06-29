# Comparable Feature Set Survey

This note records capability-level feature sets for DragonBones, Spine, and
Rive so `bony` milestone planning can compare against adjacent products without
using them as implementation sources.

Status: informational research snapshot, not a binding `bony` contract.
Research date: 2026-06-29.

## Clean-Room Boundary

Use this document for:

- Naming broad capability areas that users may expect from 2D skeletal,
  deform, and interactive animation tooling.
- Comparing `bony` milestone coverage against comparable products at a feature
  category level.
- Deciding where a future design spike, legal review, or explicit non-goal is
  needed.

Do not use this document, or its source pages, to derive:

- Runtime source, importer source, generated definitions, or example code.
- JSON or binary field layouts, type keys, property keys, exact object ordering,
  file signatures, or schema structure.
- Third-party documentation wording, names for `bony` internal concepts, or
  compatibility claims.

If an implementation task appears to require one of those details, stop and
write a design or legal-review bead instead.

## Source Set

Allowed capability-level sources surveyed:

- DragonBones official feature page:
  `https://dragonbones.github.io/en/animation.html`
- Spine official user-guide and product pages:
  `https://esotericsoftware.com/spine-user-guide`
  `https://esotericsoftware.com/spine-attachments`
  `https://esotericsoftware.com/spine-constraints`
  `https://esotericsoftware.com/spine-animating`
  `https://esotericsoftware.com/spine-skins`
  `https://esotericsoftware.com/spine-events`
  `https://esotericsoftware.com/spine-physics-constraints`
  `https://esotericsoftware.com/spine-runtimes`
- Rive official docs index and capability pages:
  `https://rive.app/docs/llms.txt`
  `https://rive.app/docs/feature-support.md`
  `https://rive.app/docs/editor/manipulating-shapes/manipulating-shapes.md`
  `https://rive.app/docs/editor/manipulating-shapes/bones.md`
  `https://rive.app/docs/editor/manipulating-shapes/meshes.md`
  `https://rive.app/docs/editor/constraints/constraints-overview.md`
  `https://rive.app/docs/editor/state-machine/state-machine.md`
  `https://rive.app/docs/editor/data-binding/overview.md`
  `https://rive.app/docs/editor/animate-mode/animation-mixing.md`

Known excluded material:

- Spine runtime source, exact JSON/binary formats, atlas format details, and
  importer code.
- DragonBones runtime source, importer source, generated schemas, and exact
  `_ske.json` layout beyond the already recorded DragonBones importer design
  boundary in [dragonbones-importer-design.md](dragonbones-importer-design.md).
- Rive runtime source, generated core definitions, exact `.riv` binary format,
  object/type keys, property keys, and linked source snippets. Rive publishes
  detailed runtime-format docs; those pages are a clean-room risk marker, not a
  source for `bony` design.

## Feature Matrix

| Feature area | DragonBones | Spine | Rive | `bony` planning implication |
| --- | --- | --- | --- | --- |
| Primary authoring model | Armature-oriented skeletal animation with image pieces and animation data. | Skeletons with bones, slots, attachments, skins, constraints, timelines, and exports for runtimes. | Artboards containing vector/raster content, animation timelines, rigging tools, components, and runtime state machines. | Treat "skeleton/armature/artboard" as comparable product categories only. Keep `bony` model names project-owned. |
| Bone hierarchy | Bone-bound images and armatures; nested animation symbols are a visible product feature. | Bones drive slots and attachments; skins can activate extra bones. | Bones can form chains; child graphics can inherit bone transforms; vertices can be bound to bones. | `bony` should continue validating hierarchy, parent order, and nested/composition goals from project-owned contracts. |
| Slots, draw order, and visibility | Image pieces compose an armature; avatar-style swaps are highlighted. | Slots group attachments, control visible attachment and color, and participate in draw order and keyed visibility. | Solos, groups, draw-order animation, components, and data-bound swaps cover similar composition needs. | Plan any future skin/avatar/component work as a `bony` concept, not as imported slot or solo semantics. |
| Visual attachment classes | Texture atlas images, movie clips, mesh/FFD content, and nested animation symbols. | Region, mesh, bounding-box, clipping, path, and point attachments. | Vector shapes/paths, procedural shapes, raster assets, text, clipping, trim path, meshes, and layouts. | Keep `bony` v1 focused on its current attachment and draw-batch contracts; use missing visual categories to drive explicit non-goals or design spikes. |
| Mesh and deformation | Meshes, FFD, and vertex skinning are first-class public features. | Mesh attachments, linked meshes, weights, and deform animation are documented feature areas. | Meshes, vertex editing, bone binding, and weighted deformation are documented rigging features. | Current M4/M7 coverage is in the right comparable class; future work should strengthen conformance assets and renderer coverage before broadening features. |
| Constraints and inverse kinematics | IK and constraints are advertised as rigging tools. | IK, path, transform, and physics constraints are separate user-guide areas; constraint order and mix are authoring concepts. | Distance, follow-path, IK, rotation, scale, transform, translation, and scroll constraints are documented. | Compare constraint families by behavior category. Do not copy solver ordering, parameter names, or runtime data layout from comparable docs. |
| Animation timelines | Timeline keyframes, motion tweening, frame sequences, curve editing, and onion skin are product features. | Keys, curves, graph/dopesheet workflows, slot attachment/color keys, draw-order keys, events, and physics reset controls are documented. | Keys, interpolation, timeline, draw-order animation, animation mixing, and state-machine playback are documented. | Future timeline work should be validated through `bony` numeric goldens at nonzero time and input scripts, not through vendor examples. |
| Runtime interactivity | Runtime image swapping and preview/publish workflows are highlighted, but no comparable state-machine surface was found in the surveyed DragonBones feature page. | Runtimes support playback, blending, procedural skeleton manipulation, and event handling; editor-authored event keys are runtime callbacks. | State machines, listeners, events, scripting, and data binding are central product features. | Rive is the strongest comparable for M8-style interactivity. Use only behavior categories: states, transitions, inputs/listeners/events, and data-bound properties. |
| Skins, avatars, and reuse | Avatar-style image changes and nested symbols are highlighted. | Skins reuse animations with different attachments; skins can include bones and constraints. | Components, solos, data binding, and runtime asset/artboard/image swapping support reusable interactive content. | A future `bony` skin/avatar milestone needs its own model and acceptance criteria. Comparable docs justify the category, not the design. |
| Events and audio | Movie-clip and publish workflows imply timeline playback; the surveyed feature page does not define a runtime event model. | Events are timeline triggers intended for runtime handling; audio events are editor/export features but playback is application-owned at runtime. | Events, listeners, audio events, and runtime event handling are documented. | Keep event semantics application-facing and deterministic. Audio playback should remain outside core runtime unless a project-owned design says otherwise. |
| Text, vector, and layout | The surveyed feature page centers on image pieces, mesh, armature, and movie clips. | Spine primarily targets image/mesh skeletal animation; point/bounding/path/clipping attachments cover non-rendered or helper geometry. | Text, vector paths, procedural shapes, responsive layouts, scrolling, N-slicing, and data-bound UI are documented. | These are likely `bony` v2+ or explicit non-goals unless promoted by a local design bead. |
| Export/runtime surface | DragonBones advertises JSON data and texture-atlas export. | Spine exports JSON or binary skeleton data plus texture atlas; runtimes load those exports. | Rive exports `.riv` runtime files and has multiple platform runtimes with feature-support tracking. | This reinforces `bony`'s `.bony`/`.bnb` split and conformance gates, but exact external format layouts remain excluded. |
| Platform/runtime ecosystem | DragonBones historically targeted game pipelines and H5/device publishing. | Spine lists many official toolkit runtimes plus generic C/C++/C#/Haxe/TypeScript runtimes. | Rive documents Web, React, React Native, Flutter, Apple, Android, C++, Unity, Unreal, and other runtimes with per-feature support. | Cross-runtime conformance remains a core differentiator for `bony`. Use platform coverage as product context, not as runtime architecture source. |
| Tooling/import/export | DragonBones advertises texture packing and import from layered images and other animation data. | Spine documents texture packing, PSD import, command-line tooling, and a skeleton viewer. | Rive documents runtime export, editor imports, marketplace/community assets, and runtime demos. | Keep importer work gated by design spikes. Spine importer remains blocked for legal review; DragonBones design exists; Rive importer is not planned by this survey. |

## Comparable-Derived Planning Questions

Use these as prompts for future `next-milestone` work:

- Do we need a project-owned skin/avatar/component model, or is attachment swap
  sufficient for v1?
- Which constraint families are already covered by `bony` contracts, which need
  stronger conformance assets, and which are explicit non-goals?
- Does M8 interactivity need more Rive-comparable coverage around listeners,
  events, data-bound values, or animation mixing?
- Should text/vector/layout features be recorded as v2+ non-goals to prevent
  accidental scope creep?
- Are existing DragonBones and Lottie importers enough for migration tooling, or
  should a separate Rive/Spine import policy bead be filed before any importer
  is discussed?

## Maintenance Rule

Comparable products change. Any future update to this file must:

1. Recheck official vendor docs at the time of the update.
2. Add or revise a provenance entry in [PROVENANCE.md](PROVENANCE.md).
3. Keep exact wire formats, runtime source, generated definitions, and copied
   wording out of this repository.
4. Prefer adding `bony` design questions over importing third-party concepts
   directly.
