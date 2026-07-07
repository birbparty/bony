part of 'loader.dart';

void _validateConvexPolygonVertices(List<double> vertices, String ctx) {
  if (vertices.length < 6 || vertices.length.isOdd) {
    throw FormatException(
        '$ctx.vertices must contain at least three (x, y) pairs');
  }
  const polygonAreaEpsilon = 1e-9;
  for (var vi = 0; vi < vertices.length; vi++) {
    if (!vertices[vi].isFinite) {
      throw FormatException('$ctx.vertices[$vi] must be finite');
    }
  }
  final pointCount = vertices.length ~/ 2;
  var area = 0.0;
  for (var p = 0; p < pointCount; p++) {
    final ax = vertices[2 * p];
    final ay = vertices[2 * p + 1];
    final nx = vertices[2 * ((p + 1) % pointCount)];
    final ny = vertices[2 * ((p + 1) % pointCount) + 1];
    area += ax * ny - nx * ay;
  }
  area *= 0.5;
  if (area.abs() <= polygonAreaEpsilon) {
    throw FormatException('$ctx.vertices polygon area must be non-zero');
  }
  final sign = area > 0.0 ? 1.0 : -1.0;
  for (var p = 0; p < pointCount; p++) {
    final ax = vertices[2 * p];
    final ay = vertices[2 * p + 1];
    final bx = vertices[2 * ((p + 1) % pointCount)];
    final by = vertices[2 * ((p + 1) % pointCount) + 1];
    final cx = vertices[2 * ((p + 2) % pointCount)];
    final cy = vertices[2 * ((p + 2) % pointCount) + 1];
    final turn = (bx - ax) * (cy - by) - (by - ay) * (cx - bx);
    if (turn * sign < -polygonAreaEpsilon) {
      throw FormatException('$ctx.vertices must be convex in v1');
    }
  }
}

enum _AttachmentKind {
  region,
  clipping,
  mesh,
  point,
  boundingBox,
  nestedRig,
}

class _ValidationRegistry {
  final boneNames = <String>{};
  final boneParentByName = <String, String>{};
  final regionNames = <String>{};
  final clipNames = <String>{};
  final meshNames = <String>{};
  final pointNames = <String>{};
  final boundingBoxNames = <String>{};
  final nestedRigNames = <String>{};
  final slotNames = <String>{};
  final pathAttachmentNames = <String>{};
  final pathNames = <String>{};
  final ikNames = <String>{};
  final transformNames = <String>{};
  final physicsNames = <String>{};
  final animationNames = <String>{};

  bool containsSlotAttachment(String name) =>
      regionNames.contains(name) ||
      clipNames.contains(name) ||
      meshNames.contains(name) ||
      pointNames.contains(name) ||
      boundingBoxNames.contains(name) ||
      nestedRigNames.contains(name);

  int slotAttachmentTargetMatches(String name) {
    var matches = 0;
    if (regionNames.contains(name)) matches++;
    if (clipNames.contains(name)) matches++;
    if (meshNames.contains(name)) matches++;
    if (pointNames.contains(name)) matches++;
    if (boundingBoxNames.contains(name)) matches++;
    if (nestedRigNames.contains(name)) matches++;
    return matches;
  }
}

void _registerAttachmentName(
  _ValidationRegistry registry,
  String name,
  _AttachmentKind kind,
  String ctx,
) {
  if (name.isEmpty) throw FormatException('$ctx.name must not be empty');
  switch (kind) {
    case _AttachmentKind.region:
      if (!registry.regionNames.add(name)) {
        throw FormatException('duplicate region name: $name');
      }
    case _AttachmentKind.clipping:
      if (!registry.clipNames.add(name)) {
        throw FormatException('duplicate clipping attachment name: $name');
      }
      if (registry.regionNames.contains(name)) {
        throw FormatException(
            'clipping attachment name collides with a region attachment name: '
            '$name');
      }
    case _AttachmentKind.mesh:
      if (!registry.meshNames.add(name)) {
        throw FormatException('duplicate mesh attachment name: $name');
      }
      if (registry.regionNames.contains(name)) {
        throw FormatException(
            'mesh attachment name collides with a region attachment name: '
            '$name');
      }
      if (registry.clipNames.contains(name)) {
        throw FormatException(
            'mesh attachment name collides with a clipping attachment name: '
            '$name');
      }
    case _AttachmentKind.point:
      if (!registry.pointNames.add(name)) {
        throw FormatException('duplicate point attachment name: $name');
      }
      if (registry.regionNames.contains(name) ||
          registry.clipNames.contains(name) ||
          registry.meshNames.contains(name)) {
        throw FormatException(
            'point attachment name collides with another slot attachment name: '
            '$name');
      }
    case _AttachmentKind.boundingBox:
      if (!registry.boundingBoxNames.add(name)) {
        throw FormatException('duplicate bounding-box attachment name: $name');
      }
      if (registry.regionNames.contains(name) ||
          registry.clipNames.contains(name) ||
          registry.meshNames.contains(name) ||
          registry.pointNames.contains(name)) {
        throw FormatException(
            'bounding-box attachment name collides with another slot attachment name: '
            '$name');
      }
    case _AttachmentKind.nestedRig:
      if (!registry.nestedRigNames.add(name)) {
        throw FormatException('duplicate nested rig attachment name: $name');
      }
      if (registry.regionNames.contains(name) ||
          registry.clipNames.contains(name) ||
          registry.meshNames.contains(name) ||
          registry.pointNames.contains(name) ||
          registry.boundingBoxNames.contains(name)) {
        throw FormatException(
            'nested rig attachment name collides with another slot attachment name: '
            '$name');
      }
  }
}

void _validateBones(SkeletonData data, _ValidationRegistry registry) {
  final seenBones = <String>{};
  for (var i = 0; i < data.bones.length; i++) {
    final b = data.bones[i];
    final ctx = 'bones[$i]';
    if (b.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (!registry.boneNames.add(b.name)) {
      throw FormatException('duplicate bone name: ${b.name}');
    }
    registry.boneParentByName[b.name] = b.parent;
  }
  // Second pass: parent ordering (parent must appear before child).
  for (var i = 0; i < data.bones.length; i++) {
    final b = data.bones[i];
    if (b.parent.isNotEmpty) {
      if (!registry.boneNames.contains(b.parent)) {
        throw FormatException('unknown parent bone: ${b.parent}');
      }
      if (!seenBones.contains(b.parent)) {
        throw FormatException(
          'bone parent must appear before child: ${b.name}',
        );
      }
    }
    seenBones.add(b.name);
  }
}

void _validateAttachments(SkeletonData data, _ValidationRegistry registry) {
  for (var i = 0; i < data.regions.length; i++) {
    final r = data.regions[i];
    final ctx = 'regions[$i]';
    if (r.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (r.width < 0 || r.height < 0) {
      throw FormatException('$ctx dimensions must be non-negative');
    }
    if (r.u0 < 0.0 ||
        r.u0 > 1.0 ||
        r.v0 < 0.0 ||
        r.v0 > 1.0 ||
        r.u1 < 0.0 ||
        r.u1 > 1.0 ||
        r.v1 < 0.0 ||
        r.v1 > 1.0) {
      throw FormatException('$ctx UV coordinates must be in 0..1');
    }
    if (r.u0 > r.u1 || r.v0 > r.v1) {
      throw FormatException('$ctx UV rectangle must be ordered');
    }
    if (r.alphaMode != 'straight' && r.alphaMode != 'premultiplied') {
      throw FormatException('$ctx.alphaMode must be straight or premultiplied');
    }
    if (r.texturePage.isEmpty &&
        (r.u0 != 0.0 ||
            r.v0 != 0.0 ||
            r.u1 != 1.0 ||
            r.v1 != 1.0 ||
            r.alphaMode != 'straight')) {
      throw FormatException(
          '$ctx.texturePage is required for region texture metadata');
    }
    _registerAttachmentName(registry, r.name, _AttachmentKind.region, ctx);
  }

  // Clipping attachment names share the slot.attachment namespace with regions
  // (a slot may reference either). Mirrors the Nim loader's widened check and
  // the region/clip name-collision guard (runtime-nim/src/bony/model.nim).
  for (var i = 0; i < data.clippingAttachments.length; i++) {
    final c = data.clippingAttachments[i];
    final ctx = 'clippingAttachments[$i]';
    _registerAttachmentName(registry, c.name, _AttachmentKind.clipping, ctx);
    _validateConvexPolygonVertices(c.vertices, ctx);
  }

  // Mesh attachment names also share the slot.attachment namespace with regions
  // and clips. Mirror the Nim loader's cross-collection uniqueness guard
  // (runtime-nim/src/bony/model.nim): a mesh name must not collide with a region
  // or clip name.
  for (var i = 0; i < data.meshAttachments.length; i++) {
    final m = data.meshAttachments[i];
    final ctx = 'meshAttachments[$i]';
    _registerAttachmentName(registry, m.name, _AttachmentKind.mesh, ctx);
    // Geometry/reference invariants (a)-(g), ported from Nim
    // validateMeshAttachment (runtime-nim/src/bony/model.nim) so a malformed mesh
    // that Nim rejects at load is rejected here too — not accepted silently or
    // crashed on later in _skinMeshVertices. See docs/mesh-attachment-contract.md.
    if (m.vertices.isEmpty) {
      throw FormatException('$ctx must contain at least one vertex');
    }
    if (m.uvs.length != m.vertices.length) {
      throw FormatException('$ctx.uvs count must match vertex count');
    }
    for (final uv in m.uvs) {
      if (uv.u < 0.0 || uv.u > 1.0 || uv.v < 0.0 || uv.v > 1.0) {
        throw FormatException('$ctx.uvs must be in 0..1');
      }
    }
    if (m.triangles.isEmpty || m.triangles.length % 3 != 0) {
      throw FormatException('$ctx.triangles must contain index triplets');
    }
    for (final index in m.triangles) {
      if (index < 0 || index >= m.vertices.length) {
        throw FormatException('$ctx triangle index out of range');
      }
    }
    for (var vi = 0; vi < m.vertices.length; vi++) {
      final v = m.vertices[vi];
      if (v.weighted != m.weighted) {
        throw FormatException('$ctx vertices must match mesh weighted flag');
      }
      if (v.weighted) {
        if (v.influences.isEmpty) {
          throw FormatException(
              '$ctx.vertices[$vi] weighted vertex must contain at least one influence');
        }
        var sum = 0.0;
        for (final influence in v.influences) {
          if (influence.bone.isEmpty) {
            throw FormatException('$ctx influence bone must not be empty');
          }
          if (influence.weight < 0.0) {
            throw FormatException('$ctx influence weight must be non-negative');
          }
          if (!registry.boneNames.contains(influence.bone)) {
            throw FormatException(
                'unknown mesh influence bone: ${influence.bone}');
          }
          sum += influence.weight;
        }
        // weightSumTolerance = 1e-4 in the Nim reference.
        if ((sum - 1.0).abs() > 1e-4) {
          throw FormatException(
              '$ctx.vertices[$vi] weighted influences must sum to 1');
        }
      } else if (v.influences.isNotEmpty) {
        throw FormatException(
            '$ctx.vertices[$vi] unweighted vertex must not contain influences');
      }
    }
  }

  for (var i = 0; i < data.pointAttachments.length; i++) {
    final p = data.pointAttachments[i];
    final ctx = 'pointAttachments[$i]';
    _registerAttachmentName(registry, p.name, _AttachmentKind.point, ctx);
    if (!p.x.isFinite || !p.y.isFinite || !p.rotation.isFinite) {
      throw FormatException('$ctx transform fields must be finite');
    }
  }

  for (var i = 0; i < data.boundingBoxAttachments.length; i++) {
    final b = data.boundingBoxAttachments[i];
    final ctx = 'boundingBoxAttachments[$i]';
    _registerAttachmentName(registry, b.name, _AttachmentKind.boundingBox, ctx);
    _validateConvexPolygonVertices(b.vertices, ctx);
  }

  for (var i = 0; i < data.nestedRigAttachments.length; i++) {
    final n = data.nestedRigAttachments[i];
    final ctx = 'nestedRigAttachments[$i]';
    if (n.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (n.skeleton.isEmpty) {
      throw FormatException('$ctx.skeleton must not be empty');
    }
    _registerAttachmentName(registry, n.name, _AttachmentKind.nestedRig, ctx);
  }
}

List<String> _validateSlots(SkeletonData data, _ValidationRegistry registry) {
  final resolvedSlotAttachments = List<String>.filled(data.slots.length, '');
  for (var i = 0; i < data.slots.length; i++) {
    final s = data.slots[i];
    final ctx = 'slots[$i]';
    if (s.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (!registry.boneNames.contains(s.bone)) {
      throw FormatException('unknown slot bone: ${s.bone}');
    }
    if (data.skins.isEmpty &&
        s.attachment.isNotEmpty &&
        !registry.containsSlotAttachment(s.attachment)) {
      throw FormatException('unknown slot attachment: ${s.attachment}');
    }
    if (data.skins.isEmpty) {
      resolvedSlotAttachments[i] = s.attachment;
    }
    if (!registry.slotNames.add(s.name)) {
      throw FormatException('duplicate slot name: ${s.name}');
    }
  }
  return resolvedSlotAttachments;
}

void _validateSkins(
  SkeletonData data,
  _ValidationRegistry registry,
  List<String> resolvedSlotAttachments,
) {
  if (data.skins.isNotEmpty) {
    final skinNames = <String>{};
    var defaultCount = 0;
    final skinEntryTargets = <String, String>{};
    for (var si = 0; si < data.skins.length; si++) {
      final skin = data.skins[si];
      final skinCtx = 'skins[$si]';
      if (skin.name.isEmpty) {
        throw FormatException('$skinCtx.name must not be empty');
      }
      if (!skinNames.add(skin.name)) {
        throw FormatException('duplicate skin name: ${skin.name}');
      }
      if (skin.name == 'default') defaultCount++;

      final seenEntries = <String>{};
      for (var ei = 0; ei < skin.entries.length; ei++) {
        final entry = skin.entries[ei];
        final entryCtx = '$skinCtx.entries[$ei]';
        if (entry.slot.isEmpty) {
          throw FormatException('$entryCtx.slot must not be empty');
        }
        if (entry.attachment.isEmpty) {
          throw FormatException('$entryCtx.attachment must not be empty');
        }
        if (entry.target.isEmpty) {
          throw FormatException('$entryCtx.target must not be empty');
        }
        if (!registry.slotNames.contains(entry.slot)) {
          throw FormatException('unknown skin entry slot: ${entry.slot}');
        }
        final localKey = '${entry.slot}\x00${entry.attachment}';
        if (!seenEntries.add(localKey)) {
          throw FormatException(
              'duplicate skin entry: ${skin.name}/${entry.slot}/${entry.attachment}');
        }

        final targetMatches =
            registry.slotAttachmentTargetMatches(entry.target);
        if (targetMatches == 0) {
          throw FormatException('unknown skin entry target: ${entry.target}');
        }
        if (targetMatches > 1) {
          throw FormatException('ambiguous skin entry target: ${entry.target}');
        }
        skinEntryTargets['${skin.name}\x00$localKey'] = entry.target;
      }
    }
    if (defaultCount != 1) {
      throw const FormatException(
          'skins must contain exactly one default skin');
    }
    for (var i = 0; i < data.slots.length; i++) {
      final slot = data.slots[i];
      if (slot.attachment.isEmpty) {
        resolvedSlotAttachments[i] = '';
        continue;
      }
      final key = 'default\x00${slot.name}\x00${slot.attachment}';
      final target = skinEntryTargets[key];
      if (target == null) {
        throw FormatException(
            'slot attachment does not resolve through default skin: '
            '${slot.name}/${slot.attachment}');
      }
      resolvedSlotAttachments[i] = target;
    }
  }
}

void _validateClipRanges(
  SkeletonData data,
  List<String> resolvedSlotAttachments,
) {
  // Clipping range + no-overlap validation (mirror the Nim loader). A clip's
  // range starts at the slot that references it and runs through untilSlot
  // inclusive (else to the end of draw order); untilSlot must name a known slot
  // strictly after the clip's own slot, and ranges may not overlap.
  if (data.clippingAttachments.isNotEmpty) {
    final slotIndexByName = <String, int>{};
    for (var i = 0; i < data.slots.length; i++) {
      slotIndexByName[data.slots[i].name] = i;
    }
    final clipByName = <String, ClippingAttachment>{
      for (final c in data.clippingAttachments) c.name: c,
    };
    for (final c in data.clippingAttachments) {
      if (c.untilSlot.isNotEmpty && !slotIndexByName.containsKey(c.untilSlot)) {
        throw FormatException(
            'clipping attachment untilSlot names unknown slot: ${c.untilSlot}');
      }
    }
    final lastSlotIndex = data.slots.length - 1;
    var activeUntil = -1;
    var activeName = '';
    for (var slotIdx = 0; slotIdx < data.slots.length; slotIdx++) {
      final s = data.slots[slotIdx];
      final attachment = resolvedSlotAttachments[slotIdx];
      if (attachment.isEmpty || !clipByName.containsKey(attachment)) {
        continue;
      }
      final clip = clipByName[attachment]!;
      final ownIndex = slotIdx;
      final endIndex = clip.untilSlot.isNotEmpty
          ? slotIndexByName[clip.untilSlot]!
          : lastSlotIndex;
      if (endIndex <= ownIndex) {
        throw FormatException(
            "clipping attachment '$attachment' on slot '${s.name}' has an "
            "empty range (untilSlot at or before the clip's own slot)");
      }
      if (ownIndex <= activeUntil) {
        throw FormatException(
            "clipping ranges overlap: '$attachment' begins while "
            "'$activeName' is still active");
      }
      activeUntil = endIndex;
      activeName = attachment;
    }
  }
}

void _validateConstraints(SkeletonData data, _ValidationRegistry registry) {
  for (var i = 0; i < data.pathAttachments.length; i++) {
    final pa = data.pathAttachments[i];
    final ctx = 'pathAttachments[$i]';
    if (pa.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (!registry.pathAttachmentNames.add(pa.name)) {
      throw FormatException('duplicate path attachment name: ${pa.name}');
    }
  }

  for (var i = 0; i < data.paths.length; i++) {
    final p = data.paths[i];
    final ctx = 'paths[$i]';
    if (p.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (!registry.boneNames.contains(p.bone)) {
      throw FormatException('unknown path constraint bone: ${p.bone}');
    }
    if (!registry.boneNames.contains(p.target)) {
      throw FormatException('unknown path constraint target: ${p.target}');
    }
    if (!registry.pathAttachmentNames.contains(p.path)) {
      throw FormatException('unknown path constraint path: ${p.path}');
    }
    if (!registry.pathNames.add(p.name)) {
      throw FormatException('duplicate path constraint name: ${p.name}');
    }
  }

  // IK constraint validation, mirroring runtime-nim (model.nim). Applied on both
  // the JSON and .bnb load paths so Dart rejects exactly what Nim rejects.
  for (var i = 0; i < data.ikConstraints.length; i++) {
    final ik = data.ikConstraints[i];
    final ctx = 'ikConstraints[$i]';
    if (ik.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (!registry.ikNames.add(ik.name)) {
      throw FormatException('duplicate ik constraint name: ${ik.name}');
    }
    if (ik.bones.isEmpty) {
      throw FormatException('$ctx.bones must not be empty');
    }
    for (final boneName in ik.bones) {
      if (!registry.boneNames.contains(boneName)) {
        throw FormatException('unknown ik constraint bone: $boneName');
      }
    }
    // The chain must be contiguous root->tip: each bone after the first is the
    // direct child of the preceding one.
    for (var c = 1; c < ik.bones.length; c++) {
      if (registry.boneParentByName[ik.bones[c]] != ik.bones[c - 1]) {
        throw FormatException(
            '$ctx.bones must form a contiguous parent-to-child chain '
            '(root to tip): ${ik.bones[c]} is not a child of ${ik.bones[c - 1]}');
      }
    }
    if (!registry.boneNames.contains(ik.target)) {
      throw FormatException('unknown ik constraint target: ${ik.target}');
    }
    final mix = ik.mix;
    if (mix != null && (mix < 0.0 || mix > 1.0)) {
      throw FormatException('$ctx.mix must be in [0, 1]');
    }
  }

  // Transform constraint validation, mirroring runtime-nim (model.nim): unique
  // name, known bone/target refs, each present mix finite and in [0, 1].
  for (var i = 0; i < data.transformConstraints.length; i++) {
    final tc = data.transformConstraints[i];
    final ctx = 'transformConstraints[$i]';
    if (tc.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (!registry.transformNames.add(tc.name)) {
      throw FormatException('duplicate transform constraint name: ${tc.name}');
    }
    if (!registry.boneNames.contains(tc.bone)) {
      throw FormatException('unknown transform constraint bone: ${tc.bone}');
    }
    if (!registry.boneNames.contains(tc.target)) {
      throw FormatException(
          'unknown transform constraint target: ${tc.target}');
    }
    for (final entry in <String, double?>{
      'translateMix': tc.translateMix,
      'rotateMix': tc.rotateMix,
      'scaleMix': tc.scaleMix,
      'shearMix': tc.shearMix,
    }.entries) {
      final v = entry.value;
      if (v != null && (v.isNaN || v.isInfinite || v < 0.0 || v > 1.0)) {
        throw FormatException('$ctx.${entry.key} must be in [0, 1]');
      }
    }
  }

  for (var i = 0; i < data.physicsConstraints.length; i++) {
    final pc = data.physicsConstraints[i];
    final ctx = 'physicsConstraints[$i]';
    if (pc.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (!registry.physicsNames.add(pc.name)) {
      throw FormatException('duplicate physics constraint name: ${pc.name}');
    }
    if (!registry.boneNames.contains(pc.bone)) {
      throw FormatException('unknown physics constraint bone: ${pc.bone}');
    }
    if (pc.channels.isEmpty) {
      throw FormatException('$ctx.channels must enable at least one channel');
    }
    // Bounds mirror the eval-time physicsParams: finite everywhere, mass >= 0,
    // physicsMix in [0, 1]. Absent (null) params take integrator defaults.
    for (final entry in <String, double?>{
      'inertia': pc.inertia,
      'strength': pc.strength,
      'damping': pc.damping,
      'gravity': pc.gravity,
      'wind': pc.wind,
    }.entries) {
      final v = entry.value;
      if (v != null && (v.isNaN || v.isInfinite)) {
        throw FormatException('$ctx.${entry.key} must be finite');
      }
    }
    final mass = pc.mass;
    if (mass != null && (mass.isNaN || mass.isInfinite || mass < 0.0)) {
      throw FormatException('$ctx.mass must be non-negative');
    }
    final mix = pc.physicsMix;
    if (mix != null &&
        (mix.isNaN || mix.isInfinite || mix < 0.0 || mix > 1.0)) {
      throw FormatException('$ctx.physicsMix must be in [0, 1]');
    }
  }
}

void _validateSkinRequired(SkeletonData data, _ValidationRegistry registry) {
  if (data.skins.isNotEmpty) {
    final requiredBones = {
      for (final b in data.bones)
        if (b.skinRequired) b.name,
    };
    final requiredIk = {
      for (final ik in data.ikConstraints)
        if (ik.skinRequired) ik.name,
    };
    final requiredTransform = {
      for (final tc in data.transformConstraints)
        if (tc.skinRequired) tc.name,
    };
    final requiredPath = {
      for (final p in data.paths)
        if (p.skinRequired) p.name,
    };
    final requiredPhysics = {
      for (final pc in data.physicsConstraints)
        if (pc.skinRequired) pc.name,
    };

    Set<String> ensureMembership(
      List<String> refs,
      Set<String> valid,
      Set<String> required,
      String ctx,
      String domain,
    ) {
      final out = <String>{};
      for (final ref in refs) {
        if (ref.isEmpty) {
          throw FormatException('$ctx must not contain empty references');
        }
        if (!out.add(ref)) {
          throw FormatException(
              'duplicate skinRequired membership reference in $ctx: $ref');
        }
        if (!valid.contains(ref)) {
          throw FormatException(
              'unknown skinRequired $domain membership: $ref');
        }
        if (!required.contains(ref)) {
          throw FormatException(
              'skinRequired $domain membership references non-required item: $ref');
        }
      }
      return out;
    }

    for (final bone in data.bones) {
      if (bone.skinRequired) continue;
      var parent = bone.parent;
      while (parent.isNotEmpty) {
        if (requiredBones.contains(parent)) {
          throw FormatException(
              'non-required bone has a skinRequired ancestor: ${bone.name}');
        }
        parent = registry.boneParentByName[parent] ?? '';
      }
    }

    var defaultBones = <String>{};
    var defaultIk = <String>{};
    var defaultTransform = <String>{};
    var defaultPath = <String>{};
    var defaultPhysics = <String>{};
    for (var si = 0; si < data.skins.length; si++) {
      final skin = data.skins[si];
      final ctx = 'skins[$si]';
      final skinBones = ensureMembership(
          skin.bones, registry.boneNames, requiredBones, '$ctx.bones', 'bone');
      final skinIk = ensureMembership(skin.ikConstraints, registry.ikNames,
          requiredIk, '$ctx.ikConstraints', 'ikConstraint');
      final skinTransform = ensureMembership(
          skin.transformConstraints,
          registry.transformNames,
          requiredTransform,
          '$ctx.transformConstraints',
          'transformConstraint');
      final skinPath = ensureMembership(
          skin.pathConstraints,
          registry.pathNames,
          requiredPath,
          '$ctx.pathConstraints',
          'pathConstraint');
      final skinPhysics = ensureMembership(
          skin.physicsConstraints,
          registry.physicsNames,
          requiredPhysics,
          '$ctx.physicsConstraints',
          'physicsConstraint');
      if (skin.name == 'default') {
        defaultBones = skinBones;
        defaultIk = skinIk;
        defaultTransform = skinTransform;
        defaultPath = skinPath;
        defaultPhysics = skinPhysics;
      }
    }

    void requireDefaultRequiredBone(String boneName, String constraintName) {
      if (requiredBones.contains(boneName) &&
          !defaultBones.contains(boneName)) {
        throw FormatException(
            'non-required $constraintName depends on skinRequired bone not active for every skin: $boneName');
      }
    }

    for (final ik in data.ikConstraints) {
      if (ik.skinRequired) continue;
      for (final boneName in ik.bones) {
        requireDefaultRequiredBone(boneName, 'ikConstraint ${ik.name}');
      }
      requireDefaultRequiredBone(ik.target, 'ikConstraint ${ik.name}');
    }
    for (final tc in data.transformConstraints) {
      if (tc.skinRequired) continue;
      requireDefaultRequiredBone(tc.bone, 'transformConstraint ${tc.name}');
      requireDefaultRequiredBone(tc.target, 'transformConstraint ${tc.name}');
    }
    for (final path in data.paths) {
      if (path.skinRequired) continue;
      requireDefaultRequiredBone(path.bone, 'pathConstraint ${path.name}');
      requireDefaultRequiredBone(path.target, 'pathConstraint ${path.name}');
    }
    for (final pc in data.physicsConstraints) {
      if (pc.skinRequired) continue;
      requireDefaultRequiredBone(pc.bone, 'physicsConstraint ${pc.name}');
    }

    void requireActiveRequiredBone(
        Set<String> activeBones, String boneName, String ctx) {
      if (requiredBones.contains(boneName) && !activeBones.contains(boneName)) {
        throw FormatException(
            '$ctx depends on inactive required bone: $boneName');
      }
    }

    void checkActiveBoneClosure(Set<String> activeBones, String ctx) {
      for (final bone in data.bones) {
        if (!activeBones.contains(bone.name)) continue;
        var parent = bone.parent;
        while (parent.isNotEmpty) {
          if (requiredBones.contains(parent) && !activeBones.contains(parent)) {
            throw FormatException(
                "$ctx activates required bone '${bone.name}' without required ancestor '$parent'");
          }
          parent = registry.boneParentByName[parent] ?? '';
        }
      }
    }

    for (var si = 0; si < data.skins.length; si++) {
      final skin = data.skins[si];
      final ctx =
          skin.name == 'default' ? "skin 'default'" : "skin '${skin.name}'";
      final activeBones = skin.name == 'default'
          ? defaultBones
          : {
              ...defaultBones,
              ...ensureMembership(skin.bones, registry.boneNames, requiredBones,
                  'skins[$si].bones', 'bone'),
            };
      final activeIk = skin.name == 'default'
          ? defaultIk
          : {
              ...defaultIk,
              ...ensureMembership(skin.ikConstraints, registry.ikNames,
                  requiredIk, 'skins[$si].ikConstraints', 'ikConstraint'),
            };
      final activeTransform = skin.name == 'default'
          ? defaultTransform
          : {
              ...defaultTransform,
              ...ensureMembership(
                  skin.transformConstraints,
                  registry.transformNames,
                  requiredTransform,
                  'skins[$si].transformConstraints',
                  'transformConstraint'),
            };
      final activePath = skin.name == 'default'
          ? defaultPath
          : {
              ...defaultPath,
              ...ensureMembership(skin.pathConstraints, registry.pathNames,
                  requiredPath, 'skins[$si].pathConstraints', 'pathConstraint'),
            };
      final activePhysics = skin.name == 'default'
          ? defaultPhysics
          : {
              ...defaultPhysics,
              ...ensureMembership(
                  skin.physicsConstraints,
                  registry.physicsNames,
                  requiredPhysics,
                  'skins[$si].physicsConstraints',
                  'physicsConstraint'),
            };

      checkActiveBoneClosure(activeBones, ctx);
      for (final ik in data.ikConstraints) {
        if (ik.skinRequired && activeIk.contains(ik.name)) {
          for (final boneName in ik.bones) {
            requireActiveRequiredBone(
                activeBones, boneName, "$ctx ikConstraint '${ik.name}'");
          }
          requireActiveRequiredBone(
              activeBones, ik.target, "$ctx ikConstraint '${ik.name}'");
        }
      }
      for (final tc in data.transformConstraints) {
        if (tc.skinRequired && activeTransform.contains(tc.name)) {
          requireActiveRequiredBone(
              activeBones, tc.bone, "$ctx transformConstraint '${tc.name}'");
          requireActiveRequiredBone(
              activeBones, tc.target, "$ctx transformConstraint '${tc.name}'");
        }
      }
      for (final path in data.paths) {
        if (path.skinRequired && activePath.contains(path.name)) {
          requireActiveRequiredBone(
              activeBones, path.bone, "$ctx pathConstraint '${path.name}'");
          requireActiveRequiredBone(
              activeBones, path.target, "$ctx pathConstraint '${path.name}'");
        }
      }
      for (final pc in data.physicsConstraints) {
        if (pc.skinRequired && activePhysics.contains(pc.name)) {
          requireActiveRequiredBone(
              activeBones, pc.bone, "$ctx physicsConstraint '${pc.name}'");
        }
      }
    }
  }
}

void _validateAnimations(SkeletonData data, _ValidationRegistry registry) {
  registry.animationNames.addAll(data.animations.map((a) => a.name));
  for (var ai = 0; ai < data.animations.length; ai++) {
    final anim = data.animations[ai];
    final ctx = 'animations[$ai](${anim.name})';
    for (var bi = 0; bi < anim.boneTimelines.length; bi++) {
      final tl = anim.boneTimelines[bi];
      if (!registry.boneNames.contains(tl.bone)) {
        throw FormatException(
            '$ctx.boneTimelines[$bi]: unknown bone: ${tl.bone}');
      }
    }
    for (var si = 0; si < anim.slotTimelines.length; si++) {
      final tl = anim.slotTimelines[si];
      if (!registry.slotNames.contains(tl.slot)) {
        throw FormatException(
            '$ctx.slotTimelines[$si]: unknown slot: ${tl.slot}');
      }
    }
  }
}

void _validateDeformers(SkeletonData data) {
  // M7 deformer validation.
  final deformerIds = <String>{};
  final deformerOrders = <int>{};
  for (var di = 0; di < data.deformers.length; di++) {
    final rec = data.deformers[di];
    final def = rec.deformer;
    final ctx = 'deformers[$di](${def.id})';
    if (def.id.isEmpty) throw FormatException('$ctx.id must not be empty');
    if (!deformerIds.add(def.id)) {
      throw FormatException('duplicate deformer id: ${def.id}');
    }
    if (!deformerOrders.add(def.order)) {
      throw FormatException('duplicate deformer order: ${def.order}');
    }
    if (def.parent.isNotEmpty && !deformerIds.contains(def.parent)) {
      throw FormatException(
          '$ctx: parent deformer not found or not ordered before child: ${def.parent}');
    }
    switch (def) {
      case WarpDeformer(:final warp):
        if (warp.rows < 2)
          throw FormatException(
              '$ctx warp.rows must be >= 2, got ${warp.rows}');
        if (warp.cols < 2)
          throw FormatException(
              '$ctx warp.cols must be >= 2, got ${warp.cols}');
        final expectedPts = warp.rows * warp.cols;
        if (warp.controlPoints.length != expectedPts) {
          throw FormatException(
              '$ctx warp.controlPoints: expected $expectedPts, got ${warp.controlPoints.length}');
        }
        if (warp.maxX <= warp.minX) {
          throw FormatException(
              '$ctx warp bounds: maxX (${warp.maxX}) must be > minX (${warp.minX})');
        }
        if (warp.maxY <= warp.minY) {
          throw FormatException(
              '$ctx warp bounds: maxY (${warp.maxY}) must be > minY (${warp.minY})');
        }
      case RotationDeformer():
        break;
    }
  }
}

void _validateStateMachines(SkeletonData data, _ValidationRegistry registry) {
  // M8 state machine cross-reference validation.
  for (var smi = 0; smi < data.stateMachines.length; smi++) {
    final sm = data.stateMachines[smi];
    final smCtx = 'stateMachines[$smi](${sm.name})';
    final inputNames = <String>{for (final inp in sm.inputs) inp.name};
    final inputsByName = <String, StateMachineInput>{
      for (final inp in sm.inputs) inp.name: inp,
    };
    final layerStateNames = <String, Set<String>>{};
    for (var li = 0; li < sm.layers.length; li++) {
      final layer = sm.layers[li];
      final lCtx = '$smCtx.layers[$li](${layer.name})';
      final stateNames = <String>{for (final s in layer.states) s.name};
      layerStateNames[layer.name] = stateNames;
      for (var si = 0; si < layer.states.length; si++) {
        final state = layer.states[si];
        final sCtx = '$lCtx.states[$si](${state.name})';
        if (state.kind == StateMachineStateKind.clip) {
          if (!registry.animationNames.contains(state.clipName)) {
            throw FormatException(
                '$sCtx.clip references unknown animation: ${state.clipName}');
          }
        } else if (state.kind == StateMachineStateKind.blend1d) {
          if (!inputNames.contains(state.blendInput)) {
            throw FormatException(
                '$sCtx.blendInput references unknown input: ${state.blendInput}');
          }
          for (var bci = 0; bci < state.blendClips.length; bci++) {
            final bc = state.blendClips[bci];
            if (!registry.animationNames.contains(bc.clipName)) {
              throw FormatException(
                  '$sCtx.blendClips[$bci].clip references unknown animation: ${bc.clipName}');
            }
          }
        }
      }
      for (var ti = 0; ti < layer.transitions.length; ti++) {
        final tr = layer.transitions[ti];
        final trCtx = '$lCtx.transitions[$ti]';
        if (!stateNames.contains(tr.fromState)) {
          throw FormatException(
              '$trCtx.fromState references unknown state: ${tr.fromState}');
        }
        if (!stateNames.contains(tr.toState)) {
          throw FormatException(
              '$trCtx.toState references unknown state: ${tr.toState}');
        }
        for (var ci = 0; ci < tr.conditions.length; ci++) {
          final cond = tr.conditions[ci];
          if (!inputNames.contains(cond.input)) {
            throw FormatException(
                '$trCtx.conditions[$ci].input references unknown input: ${cond.input}');
          }
        }
      }
    }
    for (var li = 0; li < sm.listeners.length; li++) {
      final lst = sm.listeners[li];
      final lstCtx = '$smCtx.listeners[$li](${lst.name})';
      switch (lst.kind) {
        case StateMachineListenerKind.stateEnter:
        case StateMachineListenerKind.stateExit:
        case StateMachineListenerKind.transition_:
          final lstStates = layerStateNames[lst.layer];
          if (lstStates == null) {
            throw FormatException(
                '$lstCtx.layer references unknown layer: ${lst.layer}');
          }
          if (lst.kind == StateMachineListenerKind.stateEnter ||
              lst.kind == StateMachineListenerKind.transition_) {
            if (!lstStates.contains(lst.toState)) {
              throw FormatException(
                  '$lstCtx.toState references unknown state: ${lst.toState}');
            }
          }
          if (lst.kind == StateMachineListenerKind.stateExit ||
              lst.kind == StateMachineListenerKind.transition_) {
            if (!lstStates.contains(lst.fromState)) {
              throw FormatException(
                  '$lstCtx.fromState references unknown state: ${lst.fromState}');
            }
          }
          if (lst.slot.isNotEmpty ||
              lst.target.isNotEmpty ||
              lst.input.isNotEmpty ||
              lst.hitRadius != null ||
              lst.boolValue != null ||
              lst.numberValue != null) {
            throw FormatException(
                '$lstCtx lifecycle listener has pointer fields');
          }
        case StateMachineListenerKind.pointerDown:
        case StateMachineListenerKind.pointerUp:
        case StateMachineListenerKind.pointerEnter:
        case StateMachineListenerKind.pointerExit:
        case StateMachineListenerKind.pointerMove:
          if (lst.layer.isNotEmpty ||
              lst.fromState.isNotEmpty ||
              lst.toState.isNotEmpty) {
            throw FormatException(
                '$lstCtx pointer listener has lifecycle fields');
          }
          final slotIndex = data.slots.indexWhere((s) => s.name == lst.slot);
          if (slotIndex < 0) {
            throw FormatException(
                '$lstCtx.slot references unknown slot: ${lst.slot}');
          }
          final helperExists = switch (lst.targetKind) {
            PointerHelperTargetKind.point =>
              registry.pointNames.contains(lst.target),
            PointerHelperTargetKind.boundingBox =>
              registry.boundingBoxNames.contains(lst.target),
          };
          if (!helperExists) {
            throw FormatException(
                '$lstCtx.target references unknown helper attachment: ${lst.target}');
          }
          final setupMatches = data.slots[slotIndex].attachment == lst.target;
          var skinMatches = false;
          for (final skin in data.skins) {
            for (final entry in skin.entries) {
              if (entry.slot == lst.slot && entry.target == lst.target) {
                skinMatches = true;
                break;
              }
            }
            if (skinMatches) break;
          }
          if (!setupMatches && !skinMatches) {
            throw FormatException(
                '$lstCtx.target does not resolve through slot setup or skins: '
                '${lst.slot}/${lst.target}');
          }
          final input = inputsByName[lst.input];
          if (input == null) {
            throw FormatException(
                '$lstCtx.input references unknown input: ${lst.input}');
          }
          switch (input.kind) {
            case StateMachineInputKind.bool_:
              if (lst.boolValue == null) {
                throw FormatException(
                    '$lstCtx.value is required for bool pointer listeners');
              }
              if (lst.numberValue != null) {
                throw FormatException(
                    '$lstCtx bool pointer listener must not have number value');
              }
            case StateMachineInputKind.number:
              if (lst.boolValue != null) {
                throw FormatException(
                    '$lstCtx number pointer listener must not have bool value');
              }
              final value = lst.numberValue;
              if (value == null || !value.isFinite) {
                throw FormatException(
                    '$lstCtx.value is required and finite for number pointer listeners');
              }
            case StateMachineInputKind.trigger:
              if (lst.boolValue != null || lst.numberValue != null) {
                throw FormatException(
                    '$lstCtx trigger pointer listener must not have value');
              }
          }
          switch (lst.targetKind) {
            case PointerHelperTargetKind.point:
              final radius = lst.hitRadius;
              if (radius == null || !radius.isFinite || radius < 0.0) {
                throw FormatException(
                    '$lstCtx.hitRadius is required and non-negative for point pointer listeners');
              }
            case PointerHelperTargetKind.boundingBox:
              if (lst.hitRadius != null) {
                throw FormatException(
                    '$lstCtx.hitRadius is invalid for boundingBox pointer listeners');
              }
          }
      }
    }
  }
}

void _validate(SkeletonData data) {
  if (data.header.name.isEmpty) {
    throw const FormatException('skeleton.name must not be empty');
  }

  final registry = _ValidationRegistry();
  _validateBones(data, registry);
  _validateAttachments(data, registry);
  final resolvedSlotAttachments = _validateSlots(data, registry);
  _validateSkins(data, registry, resolvedSlotAttachments);
  _validateClipRanges(data, resolvedSlotAttachments);
  _validateConstraints(data, registry);
  _validateSkinRequired(data, registry);
  _validateAnimations(data, registry);
  _validateDeformers(data);
  _validateStateMachines(data, registry);
}
