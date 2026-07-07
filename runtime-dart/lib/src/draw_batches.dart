part of 'transform.dart';

DrawVertex _vertex(Affine2 world, double lx, double ly, double u, double v) {
  return DrawVertex(
    x: world.a * lx + world.c * ly + world.tx,
    y: world.b * lx + world.d * ly + world.ty,
    u: u,
    v: v,
    r: 1.0,
    g: 1.0,
    b: 1.0,
    a: 1.0,
  );
}

/// Build draw batches for the setup pose, with M7 deformers applied at
/// default parameter values (mirroring the Nim CLI golden-gen pipeline).
///
/// Each slot with a non-empty attachment that resolves to a region becomes one
/// [DrawBatch] with 4 vertices and 6 indices (two triangles).
/// Linear-blend skinning for a mesh attachment's setup vertices, ported fresh to
/// match the Nim `skinMeshVertices` formula and evaluation order
/// (docs/mesh-attachment-contract.md) so both runtimes agree within 1e-4:
///
///   weighted:   worldPos = sum_i weight_i * (boneWorld_i * (bindX_i, bindY_i)),
///               influences accumulated in stored order.
///   unweighted: worldPos = slotBoneWorld * (x, y)  (FK).
///
/// Output x/y/u/v are f32-quantized at the boundary (matching Nim's
/// SkinnedMeshVertex). Meshes carry no per-vertex color in v1, so r=g=b=a=1.
List<DrawVertex> _skinMeshVertices(
  List<Affine2> worlds,
  Map<String, int> boneIndex,
  String slotBone,
  MeshAttachment mesh,
) {
  final out = <DrawVertex>[];
  for (var i = 0; i < mesh.vertices.length; i++) {
    final vertex = mesh.vertices[i];
    final uv = mesh.uvs[i];
    var x = 0.0;
    var y = 0.0;
    if (vertex.weighted) {
      for (final influence in vertex.influences) {
        final w = worlds[boneIndex[influence.bone]!];
        final p = _transformPoint(w, influence.bindX, influence.bindY);
        x += influence.weight * p.x;
        y += influence.weight * p.y;
      }
    } else {
      final p =
          _transformPoint(worlds[boneIndex[slotBone]!], vertex.x, vertex.y);
      x = p.x;
      y = p.y;
    }
    out.add(DrawVertex(
      x: quantizeF32(x),
      y: quantizeF32(y),
      u: quantizeF32(uv.u),
      v: quantizeF32(uv.v),
      r: 1.0,
      g: 1.0,
      b: 1.0,
      a: 1.0,
    ));
  }
  return out;
}

/// Offset skinned mesh [vertices] by a dense per-vertex deform [deltas] list,
/// re-quantizing to f32 at the boundary. Ports `applyDeformDeltas`
/// (runtime-nim/src/bony/mesh/deform.nim:140-153): position is offset, u/v and
/// colour carry through unchanged.
List<DrawVertex> _applyDeformDeltas(
    List<DrawVertex> vertices, List<MeshDelta> deltas) {
  final out = <DrawVertex>[];
  for (var i = 0; i < vertices.length; i++) {
    final v = vertices[i];
    out.add(DrawVertex(
      x: quantizeF32(v.x + deltas[i].x),
      y: quantizeF32(v.y + deltas[i].y),
      u: v.u,
      v: v.v,
      r: v.r,
      g: v.g,
      b: v.b,
      a: v.a,
    ));
  }
  return out;
}

class _DrawBatchBuild {
  const _DrawBatchBuild(
    this.batches,
    this.batchSlotIndex,
    this.batchClipPerTriangle,
  );

  final List<DrawBatch> batches;
  final List<int> batchSlotIndex;
  final List<bool> batchClipPerTriangle;
}

_DrawBatchBuild _buildDrawBatchBuild(
  SkeletonData data,
  List<Affine2> worlds, {
  required String activeSkin,
  required Map<String, SkeletonData> children,
  required bool composeNested,
  required List<String> activeIds,
}) {
  if (worlds.length != data.bones.length) {
    throw FormatException(
        'buildDrawBatches: worlds length ${worlds.length} must match bone count ${data.bones.length}');
  }
  final boneIndex = <String, int>{};
  for (var i = 0; i < data.bones.length; i++) {
    boneIndex[data.bones[i].name] = i;
  }
  final activation = data.activeSkinMembership(activeSkin);
  final attachmentMap = <String, Attachment>{
    for (final attachment in data.allAttachments) attachment.name: attachment,
  };
  // Transient deform-timeline overrides staged on the posed skeleton by
  // applyPose, keyed by slot name + mesh attachment (the mixer produces one
  // entry per slot/attachment).
  final deformMap = <String, List<MeshDelta>>{
    for (final o in data.deformOverrides)
      '${o.slot}\x00${o.attachment}': o.deltas,
  };

  final baseBatches = <DrawBatch>[];
  final batchSlotIndex = <int>[];
  final batchClipPerTriangle = <bool>[];
  final resolvedSlotAttachment = <String, String>{};
  bool meshInfluencesAreActive(MeshAttachment mesh) {
    for (final vertex in mesh.vertices) {
      for (final influence in vertex.influences) {
        final index = boneIndex[influence.bone];
        if (index == null) {
          throw FormatException(
              'mesh influence references unknown bone: ${influence.bone}');
        }
        if (!activation.bones[index]) return false;
      }
    }
    return true;
  }

  for (var slotIdx = 0; slotIdx < data.slots.length; slotIdx++) {
    final slot = data.slots[slotIdx];
    if (slot.attachment.isEmpty) continue;
    final slotBoneIndex = boneIndex[slot.bone]!;
    if (!activation.bones[slotBoneIndex]) continue;
    final attachment = data.resolveSkinAttachmentTarget(
        activeSkin, slot.name, slot.attachment);
    resolvedSlotAttachment[slot.name] = attachment;
    if (attachment.isEmpty) continue;
    switch (attachmentMap[attachment]) {
      case RegionAttachment region:
        final world = worlds[slotBoneIndex];
        final hw = region.width * 0.5;
        final hh = region.height * 0.5;
        baseBatches.add(DrawBatch(
          slot: slot.name,
          bone: slot.bone,
          attachment: attachment,
          blendMode: 'normal',
          texturePage: region.texturePage,
          clipId: '',
          world: world,
          vertices: [
            _vertex(world, -hw, -hh, region.u0, region.v0),
            _vertex(world, hw, -hh, region.u1, region.v0),
            _vertex(world, hw, hh, region.u1, region.v1),
            _vertex(world, -hw, hh, region.u0, region.v1),
          ],
          indices: [0, 1, 2, 2, 3, 0],
        ));
        batchSlotIndex.add(slotIdx);
        batchClipPerTriangle.add(false);
      case MeshAttachment mesh:
        // Skin mesh vertices (FK for unweighted, linear-blend for weighted) and
        // emit one batch in this slot's draw-order position, with metadata
        // mirroring the region path and the Nim reference.
        if (!meshInfluencesAreActive(mesh)) continue;
        final world = worlds[slotBoneIndex];
        var meshVerts = _skinMeshVertices(worlds, boneIndex, slot.bone, mesh);
        // Deform-timeline stage: offset skinned vertices by the posed override
        // for this slot/attachment, immediately after skinning and before the
        // M7 deformer and clipping stages (normative order — see
        // docs/deform-timeline-contract.md).
        final deltas = deformMap['${slot.name}\x00${mesh.name}'];
        if (deltas != null) {
          // Nim's applyDeformDeltas raises schemaViolation on a count mismatch
          // rather than silently rendering the undeformed mesh. Match that: keep
          // the absence guard (no override for this slot/mesh), but a present
          // override whose length disagrees with the skinned vertices is a domain
          // error (defensively unreachable — the loader pins vertexCount ==
          // mesh.vertices.length — but a future invariant break must fail loudly
          // in Dart as it does in Nim, not hide as a static draw).
          if (deltas.length != meshVerts.length) {
            throw FormatException(
                'deform delta count must match skinned vertex count: '
                '${deltas.length} vs ${meshVerts.length}');
          }
          meshVerts = _applyDeformDeltas(meshVerts, deltas);
        }
        baseBatches.add(DrawBatch(
          slot: slot.name,
          bone: slot.bone,
          attachment: attachment,
          blendMode: 'normal',
          texturePage: '',
          clipId: '',
          world: world,
          vertices: meshVerts,
          indices: List<int>.from(mesh.triangles),
        ));
        batchSlotIndex.add(slotIdx);
        batchClipPerTriangle.add(true);
      case NestedRigAttachment nested:
        if (!composeNested) continue;
        if (activeIds.contains(nested.skeleton)) {
          throw FormatException(
              'cycleDetected: nested rig composition cycle detected for skeleton: ${nested.skeleton}');
        }
        final child = children[nested.skeleton];
        if (child == null) {
          throw FormatException(
              'unknownRequiredReference: nested rig child skeleton is not resolved: ${nested.skeleton}');
        }
        final childSkin = nested.skin.isNotEmpty ? nested.skin : 'default';
        if (!child.hasSkin(childSkin)) {
          throw FormatException(
              'unknownRequiredReference: nested rig child skin is not resolved: ${nested.skeleton}/$childSkin');
        }
        final childBuild = _buildDrawBatchBuild(
          child,
          computeWorldTransforms(child, activeSkin: childSkin),
          activeSkin: childSkin,
          children: children,
          composeNested: true,
          activeIds: [...activeIds, nested.skeleton],
        );
        final hostWorld = worlds[slotBoneIndex];
        for (var childIndex = 0;
            childIndex < childBuild.batches.length;
            childIndex++) {
          baseBatches
              .add(_composeBatch(hostWorld, childBuild.batches[childIndex]));
          batchSlotIndex.add(slotIdx);
          batchClipPerTriangle.add(childBuild.batchClipPerTriangle[childIndex]);
        }
      case PathAttachment():
      case PointAttachment():
      case BoundingBoxAttachment():
      case ClippingAttachment():
      case null:
        continue;
    }
  }

  List<DrawBatch> visibleBatches;
  if (data.deformers.isEmpty) {
    visibleBatches = baseBatches;
  } else {
    // Sample each parameter at its default value.
    final samples = data.parameters
        .map((p) => ParameterSample(name: p.name, value: p.defaultValue))
        .toList();
    final efDefs = effectiveDeformers(data.deformers, samples);
    if (efDefs.isEmpty) {
      visibleBatches = baseBatches;
    } else {
      // Apply deformers per batch — each batch uses its own vertices as setup.
      visibleBatches = baseBatches.map((batch) {
        final verts = batch.vertices;
        final positions = verts.map((v) => (x: v.x, y: v.y)).toList();
        final deformed = applyDeformers(positions, efDefs);
        return DrawBatch(
          slot: batch.slot,
          bone: batch.bone,
          attachment: batch.attachment,
          blendMode: batch.blendMode,
          texturePage: batch.texturePage,
          clipId: batch.clipId,
          world: batch.world,
          vertices: [
            for (var i = 0; i < verts.length; i++)
              DrawVertex(
                x: deformed[i].x,
                y: deformed[i].y,
                u: verts[i].u,
                v: verts[i].v,
                r: verts[i].r,
                g: verts[i].g,
                b: verts[i].b,
                a: verts[i].a,
              ),
          ],
          indices: batch.indices,
        );
      }).toList();
    }
  }

  return _DrawBatchBuild(
    _applyClipping(
      data,
      visibleBatches,
      worlds,
      boneIndex,
      resolvedSlotAttachment,
      batchSlotIndex,
      batchClipPerTriangle,
    ),
    batchSlotIndex,
    batchClipPerTriangle,
  );
}

List<DrawBatch> buildDrawBatches(
  SkeletonData data, {
  String activeSkin = 'default',
}) {
  final worlds = computeWorldTransforms(data, activeSkin: activeSkin);
  return _buildDrawBatchBuild(
    data,
    worlds,
    activeSkin: activeSkin,
    children: const {},
    composeNested: false,
    activeIds: const [],
  ).batches;
}

List<DrawBatch> buildNestedDrawBatches(
  SkeletonData data,
  Map<String, SkeletonData> children, {
  String activeSkin = 'default',
  List<Affine2>? worlds,
}) {
  return _buildDrawBatchBuild(
    data,
    worlds ?? computeWorldTransforms(data, activeSkin: activeSkin),
    activeSkin: activeSkin,
    children: children,
    composeNested: true,
    activeIds: const [],
  ).batches;
}

/// Populate `clipId` and geometrically clip covered draw batches, mirroring the
/// Nim reference (`runtime-nim/src/bony/transform.nim`). For each slot whose
/// attachment names a clipping attachment, the covered range is the batch after
/// the clip's own slot through `untilSlot` inclusive (else to the end of draw
/// order). The load-time no-overlap invariant guarantees at most one clip is
/// active per batch. Returns the input unchanged when there are no clips.
List<DrawBatch> _applyClipping(
  SkeletonData data,
  List<DrawBatch> batches,
  List<Affine2> worlds,
  Map<String, int> boneIndex,
  Map<String, String> resolvedSlotAttachment,
  List<int> batchSlotIndex,
  List<bool> batchClipPerTriangle,
) {
  if (data.clippingAttachments.isEmpty) return batches;

  final slotIndexByName = <String, int>{};
  for (var i = 0; i < data.slots.length; i++) {
    slotIndexByName[data.slots[i].name] = i;
  }
  final clipMap = <String, ClippingAttachment>{
    for (final c in data.clippingAttachments) c.name: c,
  };
  final lastSlotIndex = data.slots.length - 1;

  final result = List<DrawBatch>.from(batches);
  for (var slotIdx = 0; slotIdx < data.slots.length; slotIdx++) {
    final slot = data.slots[slotIdx];
    final attachment = resolvedSlotAttachment[slot.name] ?? '';
    if (attachment.isEmpty) continue;
    final clip = clipMap[attachment];
    if (clip == null) continue;
    final ownIndex = slotIdx;
    final endIndex = clip.untilSlot.isNotEmpty
        ? slotIndexByName[clip.untilSlot]!
        : lastSlotIndex;
    // Clip polygon in world space via the clip's own slot's bone world — the
    // same transform the covered region quads are built with.
    final clipWorld = worlds[boneIndex[slot.bone]!];
    final clipPolygon = <ClipPoint>[];
    for (var p = 0; p + 1 < clip.vertices.length; p += 2) {
      final point =
          _transformPoint(clipWorld, clip.vertices[p], clip.vertices[p + 1]);
      clipPolygon.add(ClipPoint(quantizeF32(point.x), quantizeF32(point.y)));
    }
    for (var b = 0; b < result.length; b++) {
      final sourceSlotIndex = batchSlotIndex[b];
      if (sourceSlotIndex <= ownIndex || sourceSlotIndex > endIndex) continue;
      final batch = result[b];
      // Mesh batches clip per-triangle; region batches clip as a convex ring.
      final clipped = batchClipPerTriangle[b]
          ? clipDrawBatchTriangles(batch.vertices, batch.indices, clipPolygon)
          : clipDrawBatchPolygon(batch.vertices, clipPolygon);
      result[b] = DrawBatch(
        slot: batch.slot,
        bone: batch.bone,
        attachment: batch.attachment,
        blendMode: batch.blendMode,
        texturePage: batch.texturePage,
        clipId: clip.name,
        world: batch.world,
        vertices: clipped.changed ? clipped.vertices : batch.vertices,
        indices: clipped.changed ? clipped.indices : batch.indices,
      );
    }
  }
  return result;
}
