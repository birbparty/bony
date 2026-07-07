## Draw-batch assembly and clipping dispatch for transformed skeletons.

import std/tables

import bony/mesh/deform
import bony/mesh/drawbatch_clipping
import bony/mesh/skinning
import bony/model
import bony/transform/affine
import bony/transform/runtime_constraints

type
  NestedSkeletonMap* = Table[string, SkeletonData]

  DrawBatchBuild = object
    batches: seq[DrawBatch]
    batchSlotIndex: seq[int]
    batchClipPerTriangle: seq[bool]

proc vertex(world: Affine2; x, y, u, v: float64): DrawVertex =
  let point = transformPoint(world, x, y)
  DrawVertex(
    x: point.x,
    y: point.y,
    u: u,
    v: v,
    r: 1.0,
    g: 1.0,
    b: 1.0,
    a: 1.0,
  )


proc skinMeshVertices*(
  data: SkeletonData;
  slotBone: string;
  mesh: MeshAttachment;
  skinningMethod = linearBlendSkinning;
): seq[SkinnedMeshVertex] =
  ## Convenience overload relocated from `bony/mesh/skinning` to break the
  ## former transform <-> skinning import cycle: recomputes worlds via the pure
  ## world-transform pass, then defers to the explicit-worlds overload.
  skinMeshVertices(data, computeWorldTransforms(data), slotBone, mesh, skinningMethod)


proc skinMeshVertices*(
  data: SkeletonData;
  slot: SlotData;
  mesh: MeshAttachment;
  skinningMethod = linearBlendSkinning;
): seq[SkinnedMeshVertex] =
  skinMeshVertices(data, slot.bone, mesh, skinningMethod)


proc meshVertex(sv: SkinnedMeshVertex): DrawVertex =
  ## Wrap an already-world-space skinned mesh vertex into a `DrawVertex`. Unlike
  ## `vertex()`, this does NOT re-apply a world transform (skinning already did)
  ## and it carries the uniform region color (r=g=b=a=1): the v1 mesh record has
  ## no per-vertex color, so a mesh and a region on the same slot are
  ## indistinguishable in color.
  DrawVertex(
    x: sv.x,
    y: sv.y,
    u: sv.u,
    v: sv.v,
    r: 1.0,
    g: 1.0,
    b: 1.0,
    a: 1.0,
  )


proc buildDrawBatchBuild(
  data: SkeletonData;
  worlds: seq[Affine2];
  activeSkin: string;
  children: NestedSkeletonMap;
  composeNested: bool;
  activeIds: seq[string];
): DrawBatchBuild =
  ## Internal draw-batch builder. Legacy callers pass `composeNested = false`;
  ## the opt-in nested API passes a host-provided child skeleton map and recurses
  ## through this same path so child clipping happens before parent composition.
  if worlds.len != data.bones.len:
    raise newBonyLoadError(schemaViolation,
      "buildDrawBatches: worlds length " & $worlds.len &
      " must match bone count " & $data.bones.len)
  let activation = activeSkinMembership(data, activeSkin)
  var batches: seq[DrawBatch] = @[]
  var boneIndex = initTable[string, int]()
  var regions = initTable[string, RegionAttachment]()
  var meshes = initTable[string, MeshAttachment]()
  var clips = initTable[string, ClipAttachmentData]()
  var nestedRigs = initTable[string, NestedRigAttachmentData]()
  # Transient deform-timeline override stamped on the posed data by the mixer,
  # keyed by slot name + mesh attachment (the mixer produces one entry per
  # slot/attachment, so keying by slot alone would collapse distinct entries).
  var deformBySlotAttachment = initTable[string, DeformOverride]()

  for index, bone in data.bones:
    boneIndex[bone.name] = index
  for region in data.regions:
    regions[region.name] = region
  for mesh in data.meshAttachments:
    meshes[mesh.name] = mesh
  for clip in data.clippingAttachments:
    clips[clip.name] = clip
  if composeNested:
    for nested in data.nestedRigAttachments:
      nestedRigs[nested.name] = nested
  for override in data.deformOverrides:
    deformBySlotAttachment[override.slot & "\0" & override.attachment] = override

  proc meshInfluencesAreActive(mesh: MeshAttachment): bool =
    for vertex in mesh.vertices:
      for influence in vertex.influences:
        if influence.bone notin boneIndex:
          raise newBonyLoadError(unknownRequiredReference, "mesh influence references unknown bone: " & influence.bone)
        if not activation.bones[boneIndex[influence.bone]]:
          return false
    true

  var slotIndexByName = initTable[string, int]()
  var resolvedSlotAttachment = newSeq[string](data.slots.len)
  for index, slot in data.slots:
    slotIndexByName[slot.name] = index

  # Draw-order slot index of each emitted batch. Batches are a subsequence of the
  # slots (one or more visible batches per drawing slot), so this maps batch ->
  # draw position for computing clip-covered ranges below.
  var batchSlotIndex: seq[int] = @[]
  var batchClipPerTriangle: seq[bool] = @[]
  for slotIdx, slot in data.slots:
    if slot.attachment.len == 0:
      continue
    let slotBoneIndex = boneIndex[slot.bone]
    if not activation.bones[slotBoneIndex]:
      continue
    let attachment = data.resolveSkinAttachmentTarget(activeSkin, slot.name, slot.attachment)
    resolvedSlotAttachment[slotIdx] = attachment
    if attachment.len == 0:
      continue
    if meshes.hasKey(attachment):
      # Keying dispatch on the `meshes` table alone is unambiguous because
      # attachment names are cross-collection unique — validateSkeletonData
      # rejects a mesh name that collides with a region or clip name (model.nim),
      # so a name resolves to at most one of the three tables.
      # Mesh dispatch MUST precede the non-region guard below: a mesh-referencing
      # slot is neither a region nor a clip, so the guard would drop it silently.
      # Skin per-vertex world positions (FK for unweighted, linear-blend for
      # weighted) via the explicit-worlds overload using the worlds we already
      # hold, then emit one batch in this slot's draw-order position. Metadata
      # fields (texturePage/blendMode/clipId/world) mirror the region path so a
      # region and a mesh on the same slot are indistinguishable there.
      let mesh = meshes[attachment]
      if not meshInfluencesAreActive(mesh):
        continue
      # `world` is the slot-bone world used only as batch metadata (mirroring the
      # region path); it does NOT transform the mesh vertices. Skinning consumes
      # the full `worlds` array directly — a weighted vertex blends across its
      # influence bones and ignores slot.bone entirely.
      let world = worlds[boneIndex[slot.bone]]
      var skinned = skinMeshVertices(data, worlds, slot.bone, mesh)
      # Deform-timeline stage: offset skinned vertices by the posed override for
      # this slot/attachment, immediately after skinning and before the M7
      # deformer and clipping stages (normative order — see
      # docs/deform-timeline-contract.md). Region batches are never offset.
      let deformKey = slot.name & "\0" & mesh.name
      if deformKey in deformBySlotAttachment:
        let override = deformBySlotAttachment[deformKey]
        if override.deltas.len == skinned.len:
          skinned = applyDeformDeltas(skinned, override.deltas)
      var meshVerts = newSeq[DrawVertex](skinned.len)
      for i, sv in skinned:
        meshVerts[i] = meshVertex(sv)
      batches.add DrawBatch(
        slot: slot.name,
        bone: slot.bone,
        attachment: attachment,
        texturePage: "",
        blendMode: "normal",
        clipId: "",
        world: world,
        vertices: meshVerts,
        indices: mesh.triangles,
      )
      batchSlotIndex.add slotIdx
      batchClipPerTriangle.add true
      continue
    if composeNested and nestedRigs.hasKey(attachment):
      let nested = nestedRigs[attachment]
      if nested.skeleton in activeIds:
        raise newBonyLoadError(cycleDetected,
          "nested rig composition cycle detected for skeleton: " & nested.skeleton)
      if not children.hasKey(nested.skeleton):
        raise newBonyLoadError(unknownRequiredReference,
          "nested rig child skeleton is not resolved: " & nested.skeleton)
      let childSkin = if nested.skin.len > 0: nested.skin else: "default"
      let child = children[nested.skeleton]
      if not child.hasSkin(childSkin):
        raise newBonyLoadError(unknownRequiredReference,
          "nested rig child skin is not resolved: " & nested.skeleton & "/" & childSkin)
      var nextIds = activeIds
      nextIds.add nested.skeleton
      let hostWorld = worlds[boneIndex[slot.bone]]
      let childBuild = buildDrawBatchBuild(
        child,
        computeWorldTransforms(child, childSkin),
        childSkin,
        children,
        true,
        nextIds,
      )
      for childIndex, childBatch in childBuild.batches:
        batches.add composeBatch(hostWorld, childBatch)
        batchSlotIndex.add slotIdx
        batchClipPerTriangle.add childBuild.batchClipPerTriangle[childIndex]
      continue
    if not regions.hasKey(attachment):
      # A slot whose attachment names a clipping attachment (or any non-region)
      # produces no draw batch. This guard also prevents the `regions[...]`
      # Table lookup below from raising KeyError on a clip-named slot.
      continue
    let region = regions[attachment]
    let index = boneIndex[slot.bone]
    let world = worlds[index]
    let halfWidth = region.width * 0.5
    let halfHeight = region.height * 0.5
    batches.add DrawBatch(
      slot: slot.name,
      bone: slot.bone,
      attachment: attachment,
      texturePage: region.texturePage,
      blendMode: "normal",
      clipId: "",
      world: world,
      vertices: @[
        vertex(world, -halfWidth, -halfHeight, region.u0, region.v0),
        vertex(world, halfWidth, -halfHeight, region.u1, region.v0),
        vertex(world, halfWidth, halfHeight, region.u1, region.v1),
        vertex(world, -halfWidth, halfHeight, region.u0, region.v1),
      ],
      indices: @[0'u16, 1'u16, 2'u16, 2'u16, 3'u16, 0'u16],
    )
    batchSlotIndex.add slotIdx
    batchClipPerTriangle.add false

  # Clip pass: each slot whose attachment names a clipping attachment sets
  # `clipId` on, and geometrically clips, the draw batches in its covered range
  # (the batch after the clip's own slot through `untilSlot` inclusive, else to
  # the end of draw order). The load-time no-overlap invariant guarantees at most
  # one clip is active over any batch, so clips are applied independently.
  if data.clippingAttachments.len > 0:
    let lastSlotIndex = data.slots.len - 1
    for slotIdx, slot in data.slots:
      let slotBoneIndex = boneIndex[slot.bone]
      if not activation.bones[slotBoneIndex]:
        continue
      let attachment = resolvedSlotAttachment[slotIdx]
      if attachment.len == 0 or not clips.hasKey(attachment):
        continue
      let clip = clips[attachment]
      let ownIndex = slotIdx
      let endIndex =
        if clip.untilSlot.len > 0: slotIndexByName[clip.untilSlot]
        else: lastSlotIndex
      # Clip polygon in world space via the clip's own slot's bone world — the
      # same transform the covered region quads are built with.
      let clipWorld = worlds[slotBoneIndex]
      var clipPolygon: seq[ClipPoint] = @[]
      var p = 0
      while p + 1 < clip.vertices.len:
        let point = transformPoint(clipWorld, clip.vertices[p], clip.vertices[p + 1])
        clipPolygon.add clipPoint(
          quantizeF32(point.x, "clip.poly.x"),
          quantizeF32(point.y, "clip.poly.y"),
        )
        p += 2
      for batchIdx in 0 ..< batches.len:
        let sourceSlotIndex = batchSlotIndex[batchIdx]
        if sourceSlotIndex <= ownIndex or sourceSlotIndex > endIndex:
          continue
        if batchClipPerTriangle[batchIdx]:
          # Meshes are a triangle *soup* (explicit index list, shared/interior
          # vertices), so they clip per-triangle via clipDrawBatchTriangles —
          # NOT through clipDrawBatchPolygon, which reinterprets a batch's
          # vertices as one convex boundary ring and would destroy the topology.
          # See docs/mesh-attachment-contract.md ("per-triangle mesh clipping").
          batches[batchIdx].clipId = clip.name
          let clipped = clipDrawBatchTriangles(
            batches[batchIdx].vertices, batches[batchIdx].indices, clipPolygon)
          if clipped.changed:
            batches[batchIdx].vertices = clipped.vertices
            batches[batchIdx].indices = clipped.indices
          continue
        batches[batchIdx].clipId = clip.name
        let clipped = clipDrawBatchPolygon(batches[batchIdx].vertices, clipPolygon)
        if clipped.changed:
          batches[batchIdx].vertices = clipped.vertices
          batches[batchIdx].indices = clipped.indices

  DrawBatchBuild(
    batches: batches,
    batchSlotIndex: batchSlotIndex,
    batchClipPerTriangle: batchClipPerTriangle,
  )


proc buildDrawBatches*(data: SkeletonData; worlds: seq[Affine2]; activeSkin = "default"): seq[DrawBatch] =
  ## Build draw batches using caller-supplied world transforms. Callers that have
  ## advanced the stateful physics stage pass the physics-adjusted worlds here so
  ## draw-batch vertices reflect physics. `worlds[i]` must be the world transform
  ## of `data.bones[i]` — same length and index ordering as `computeWorldTransforms`.
  ## Raised (not `doAssert`ed) so the guard survives `-d:danger`: a stripped check
  ## here would reintroduce the silent out-of-bounds read this seam exists to prevent.
  var noChildren = initTable[string, SkeletonData]()
  buildDrawBatchBuild(data, worlds, activeSkin, noChildren, false, @[]).batches


proc buildNestedDrawBatches*(
  data: SkeletonData;
  worlds: seq[Affine2];
  children: NestedSkeletonMap;
  activeSkin = "default";
): seq[DrawBatch] =
  ## Opt-in host-resolved nested rig setup-pose composition. `children` maps each
  ## `NestedRigAttachmentData.skeleton` id to an already-loaded child
  ## `SkeletonData`. Legacy `buildDrawBatches` remains non-composing.
  buildDrawBatchBuild(data, worlds, activeSkin, children, true, @[]).batches


proc buildDrawBatches*(data: SkeletonData): seq[DrawBatch] =
  ## Convenience overload: recompute worlds from the pure world-transform pass.
  ## Use the `worlds` overload when a physics stage has adjusted bone worlds.
  buildDrawBatches(data, computeWorldTransforms(data))


proc buildDrawBatches*(data: SkeletonData; activeSkin: string): seq[DrawBatch] =
  ## Convenience overload for runtime skin selection with pure world transforms.
  buildDrawBatches(data, computeWorldTransforms(data, activeSkin), activeSkin)


proc buildNestedDrawBatches*(
  data: SkeletonData;
  children: NestedSkeletonMap;
  activeSkin = "default";
): seq[DrawBatch] =
  ## Convenience overload for setup-pose nested composition with pure world
  ## transforms.
  buildNestedDrawBatches(data, computeWorldTransforms(data, activeSkin), children, activeSkin)
