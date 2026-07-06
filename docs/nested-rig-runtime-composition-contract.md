# Nested Rig Runtime Composition Contract

Status: **binding**. Owner bead: `bony-xmo6.1` (nested rig runtime
composition contract).

This contract defines the project-owned setup-pose runtime composition rule for
nested rig attachments. The serialized nested rig attachment format is defined
by `docs/nested-rig-attachment-contract.md`; this document does not add keys,
schemas, asset lookup, animation playback, or importer behavior.

## Scope

This slice owns one explicit runtime seam: a host application may call a
nested-composition draw-batch API with:

- A host `SkeletonData`.
- The host world transforms already computed for that skeleton.
- The host active skin name.
- A resolver map from nested skeleton id string to already-loaded child
  `SkeletonData`.

The resolver key is the exact `NestedRigAttachmentData.skeleton` string in Nim
and `NestedRigAttachment.skeleton` string in Dart. Runtime code must not
construct file paths, search the filesystem, fetch assets, or otherwise load
child skeletons in this slice.

The existing `buildDrawBatches` APIs remain backward compatible. Without the
new nested-composition API and resolver input, a slot whose resolved attachment
is a nested rig attachment still emits no `DrawBatch`.

## Attachment Resolution

Host slots resolve their setup attachment through the host active skin using
the existing skin lookup rules from `docs/skin-attachment-set-contract.md`.
When the resolved concrete attachment is a nested rig attachment:

1. The nested attachment emits no direct host geometry of its own.
2. The resolver must contain a child `SkeletonData` keyed by
   `nested.skeleton`.
3. The child active skin is `nested.skin` when non-empty, otherwise `"default"`.
4. The child `animation` string remains stored metadata only. It does not start
   a child animation, state machine, timeline, event pass, physics pass, or
   mixer.

The child active skin must be valid for the resolved child skeleton according
to the child's `hasSkin` semantics. Unknown child skeleton ids and unknown
child skins fail loudly as `unknownRequiredReference`.

## Parent Affine Composition

The host slot's bone world affine is the parent transform for the child
skeleton's setup-pose draw batches.

For a host slot `S` whose bone world affine is `H`, and a child setup-pose batch
whose local child-space world affine is `C`, the composed batch world affine is:

```text
H * C
```

Every child draw vertex position is transformed by `H` after the child batch is
evaluated in child skeleton coordinates. Texture coordinates, vertex colors,
blend mode, texture page, and triangle indices are preserved from the child
batch unless later host clipping changes the geometry.

The child root bones still use their authored setup transforms; the host affine
is an external parent above the child skeleton, not a rewrite of any child bone
local transform. The host active skin does not propagate into the child.

## Draw-Order Insertion

Composed child batches are inserted at the host slot's draw-order position.
Within that insertion point, the child batches preserve the child's own
setup-pose draw order after child skin lookup, child mesh/deform handling, and
child-internal clipping.

If the host nested slot is between host slots `A` and `B`, all composed child
batches appear after batches from `A` and before batches from `B`. If multiple
nested slots appear in host draw order, each nested slot contributes its child
batches at its own host position.

A composed batch keeps the child batch's public `slot`, `bone`, and
`attachment` metadata. Implementations may carry the host slot index internally
while applying host clipping. Consumers must not assume child batch slot or bone
names are globally unique across the composed output.

## Clipping Interaction

Nested composition has two clipping domains.

Child-internal clipping is evaluated inside the child skeleton exactly as it is
for a standalone child. Child clipping attachments resolve only against child
slots, their ranges cover only child draw-order positions, and their geometry is
composed through the host affine with the rest of the child batch output.

Host clipping is evaluated after child batches have been inserted at the host
slot's draw-order position. If a host clipping attachment governs the nested
slot, every composed child batch from that slot is clipped by the host clip in
host world space. Host clip ranges do not inspect or resolve child slots; the
whole child insertion behaves as visible content owned by the host nested slot
for range membership.

The final `DrawBatch.clipId` is deterministic:

- If no host clip applies, the composed batch keeps the child batch `clipId`.
- If a host clip applies, the composed batch's geometry is clipped by the host
  clip and the final `clipId` is the host clip name.

`clipId` is metadata for the most recent clipping domain. Geometry, not a
renderer-side clip stack, is the conformance surface.

## Recursion And Cycles

Nested composition may recurse only through resolver-provided skeletons. The
runtime must track the active skeleton id stack for a composition call. If a
nested attachment resolves to a skeleton id already on that active stack, the
call fails as `cycleDetected`.

The failure must happen before returning partial composed output for the
offending traversal. A conforming implementation may preflight the reachable
nested graph or detect cycles during depth-first composition, but it must not
silently skip recursive content.

Host applications remain responsible for choosing resolver ids that uniquely
identify already-loaded child skeleton data. This slice does not define bundle
packaging, filesystem paths, asset manifests, or automatic dependency loading.

## Error Behavior

Composition failures use the existing load/runtime error categories from
`docs/load-validation-contract.md`:

| Case | Required category |
| --- | --- |
| `nested.skeleton` has no resolver entry | `unknownRequiredReference` |
| `nested.skin` is non-empty and child has no matching skin | `unknownRequiredReference` |
| `nested.skin` is empty and child has no usable `"default"` skin | `unknownRequiredReference` |
| Recursive nested skeleton reference in the active composition stack | `cycleDetected` |
| Resolver output or world-transform input violates the API contract | `schemaViolation` |

Implementations must reject these cases with typed Nim/Dart errors that tests
can classify by category. They must not render a placeholder, drop the child
silently, substitute another skin, or continue with partial content.

## Non-Goals

This slice does not define or implement:

- Nested skeleton asset loading, file lookup, package manifests, or resolver
  caching.
- New serialized fields, registry keys, schemas, or generated wire files.
- Nested animation playback, state-machine playback, event dispatch, or mixer
  layering.
- Nested physics state creation or advancement.
- Runtime retargeting, constraints across host and child skeletons, or
  host-to-child bone binding.
- Importer mapping for DragonBones, Spine, Rive, Live2D, or Lottie.
- Conformance assets or goldens.

## Related Contracts

- `docs/nested-rig-attachment-contract.md` - nested rig serialized record and
  load-time validation.
- `docs/skin-attachment-set-contract.md` - active skin and `"default"` fallback
  attachment lookup.
- `docs/clipping-attachment-contract.md` - clipping range and geometry rules.
- `docs/mesh-attachment-contract.md` - mesh draw-batch and per-triangle clipping
  behavior.
- `docs/transform-composition-contract.md` - affine world transform storage and
  composition rules.
- `docs/load-validation-contract.md` - shared error categories.
