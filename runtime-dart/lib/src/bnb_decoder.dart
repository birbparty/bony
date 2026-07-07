part of 'loader.dart';

SkeletonData _bnbDecode(List<_BnbObj> objects, List<String> strings) {
  bool isStateMachineObject(_BnbObj obj) =>
      obj.typeKey >= wire.bonyTypeKeyStateMachine &&
      obj.typeKey <= wire.bonyTypeKeyStateMachineListener;
  final decodeObjects = [
    ...objects.where((obj) => !isStateMachineObject(obj)),
    ...objects.where(isStateMachineObject),
  ];
  SkeletonHeader? header;
  final bones = <BoneData>[];
  final slots = <SlotData>[];
  final regions = <RegionAttachment>[];
  final pointAttachments = <PointAttachment>[];
  final boundingBoxAttachments = <BoundingBoxAttachment>[];
  final paths = <PathConstraintData>[];
  final pathAttachments = <PathAttachment>[];
  final clips = <ClippingAttachment>[];
  final meshes = <MeshAttachment>[];
  final nestedRigAttachments = <NestedRigAttachment>[];
  final ikConstraints = <IkConstraintData>[];
  final transformConstraints = <TransformConstraintData>[];
  final physicsConstraints = <PhysicsConstraintData>[];
  final skins = <SkinData>[];
  final parameters = <ParameterAxis>[];
  final deformers = <DeformerRecord>[];
  final animations = <AnimationClip>[];
  final stateMachines = <StateMachineData>[];
  final paramsByName = <String, ParameterAxis>{};
  final skinBuilder = _SkinBuilder(skins);
  final animationBuilder = _AnimationBuilder(animations);
  final stateMachineBuilder = _StateMachineBuilder(stateMachines);
  final deformerBuilder = _DeformerBuilder(deformers);

  List<String> boneNames() => bones.map((b) => b.name).toList();
  List<String> ikNames() => ikConstraints.map((ik) => ik.name).toList();
  List<String> transformNames() =>
      transformConstraints.map((tc) => tc.name).toList();
  List<String> pathNames() => paths.map((p) => p.name).toList();
  List<String> physicsNames() =>
      physicsConstraints.map((pc) => pc.name).toList();

  SkeletonData skinResolutionData() {
    if (header == null) {
      throw const FormatException('.bnb: missing skeleton object');
    }
    return SkeletonData(
      header: header!,
      bones: bones,
      slots: slots,
      regions: regions,
      paths: paths,
      pathAttachments: pathAttachments,
      pointAttachments: pointAttachments,
      boundingBoxAttachments: boundingBoxAttachments,
      nestedRigAttachments: nestedRigAttachments,
      clippingAttachments: clips,
      meshAttachments: meshes,
      ikConstraints: ikConstraints,
      transformConstraints: transformConstraints,
      physicsConstraints: physicsConstraints,
      skins: skins,
      parameters: parameters,
      deformers: deformers,
    );
  }

  final handlers = <int, void Function(_BnbObj)>{
    wire.bonyTypeKeySkeleton: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      if (header != null)
        throw const FormatException('.bnb: multiple skeleton objects');
      header = SkeletonHeader(
        name: _bStr(obj, wire.bonyPropertyKeyName, strings, 'skeleton.name'),
        version: _bStr(
            obj, wire.bonyPropertyKeyVersion, strings, 'skeleton.version',
            def: '0.1.0'),
      );
    },
    wire.bonyTypeKeyBone: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      bones.add(BoneData(
        name: _bStr(obj, wire.bonyPropertyKeyName, strings, 'bone.name'),
        parent: _bStr(obj, wire.bonyPropertyKeyParent, strings, 'bone.parent',
            def: ''),
        x: _bF32(obj, wire.bonyPropertyKeyX, 'bone.x', def: 0.0),
        y: _bF32(obj, wire.bonyPropertyKeyY, 'bone.y', def: 0.0),
        rotation:
            _bF32(obj, wire.bonyPropertyKeyRotation, 'bone.rotation', def: 0.0),
        scaleX: _bF32(obj, wire.bonyPropertyKeyScaleX, 'bone.scaleX', def: 1.0),
        scaleY: _bF32(obj, wire.bonyPropertyKeyScaleY, 'bone.scaleY', def: 1.0),
        shearX: _bF32(obj, wire.bonyPropertyKeyShearX, 'bone.shearX', def: 0.0),
        shearY: _bF32(obj, wire.bonyPropertyKeyShearY, 'bone.shearY', def: 0.0),
        inheritRotation:
            _bBool(obj, wire.bonyPropertyKeyInheritRotation, def: true),
        inheritScale: _bBool(obj, wire.bonyPropertyKeyInheritScale, def: true),
        inheritReflection:
            _bBool(obj, wire.bonyPropertyKeyInheritReflection, def: true),
        transformMode: _bStr(obj, wire.bonyPropertyKeyTransformMode, strings,
            'bone.transformMode',
            def: 'normal'),
        skinRequired: _bBool(obj, wire.bonyPropertyKeySkinRequired),
      ));
    },
    wire.bonyTypeKeySlot: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      slots.add(SlotData(
        name: _bStr(obj, wire.bonyPropertyKeyName, strings, 'slot.name'),
        bone: _bStr(obj, wire.bonyPropertyKeyBone, strings, 'slot.bone'),
        attachment: _bStr(
            obj, wire.bonyPropertyKeyAttachment, strings, 'slot.attachment',
            def: ''),
      ));
    },
    wire.bonyTypeKeyRegion: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      regions.add(RegionAttachment(
        name: _bStr(obj, wire.bonyPropertyKeyName, strings, 'region.name'),
        width: _bF32(obj, wire.bonyPropertyKeyWidth, 'region.width'),
        height: _bF32(obj, wire.bonyPropertyKeyHeight, 'region.height'),
        texturePage: _bStr(
            obj, wire.bonyPropertyKeyTexturePage, strings, 'region.texturePage',
            def: ''),
        u0: _bF32(obj, wire.bonyPropertyKeyU0, 'region.u0', def: 0.0),
        v0: _bF32(obj, wire.bonyPropertyKeyV0, 'region.v0', def: 0.0),
        u1: _bF32(obj, wire.bonyPropertyKeyU1, 'region.u1', def: 1.0),
        v1: _bF32(obj, wire.bonyPropertyKeyV1, 'region.v1', def: 1.0),
        alphaMode: _bStr(
            obj, wire.bonyPropertyKeyAlphaMode, strings, 'region.alphaMode',
            def: 'straight'),
      ));
    },
    wire.bonyTypeKeyPointAttachment: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      pointAttachments.add(PointAttachment(
        name: _bStr(
            obj, wire.bonyPropertyKeyName, strings, 'pointAttachment.name'),
        x: _bF32(obj, wire.bonyPropertyKeyX, 'pointAttachment.x'),
        y: _bF32(obj, wire.bonyPropertyKeyY, 'pointAttachment.y'),
        rotation: _bF32(
            obj, wire.bonyPropertyKeyRotation, 'pointAttachment.rotation'),
      ));
    },
    wire.bonyTypeKeyBoundingBoxAttachment: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      boundingBoxAttachments.add(BoundingBoxAttachment(
        name: _bStr(obj, wire.bonyPropertyKeyName, strings,
            'boundingBoxAttachment.name'),
        vertices: _bPolygonVertices(obj, 'boundingBoxAttachment'),
      ));
    },
    wire.bonyTypeKeyClippingAttachment: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      clips.add(ClippingAttachment(
        name: _bStr(
            obj, wire.bonyPropertyKeyName, strings, 'clippingAttachment.name'),
        vertices: _bPolygonVertices(obj, 'clippingAttachment'),
        untilSlot: _bStr(obj, wire.bonyPropertyKeyUntilSlot, strings,
            'clippingAttachment.untilSlot',
            def: ''),
      ));
    },
    wire.bonyTypeKeyMeshAttachment: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      final meshWeighted =
          _bBool(obj, wire.bonyPropertyKeyMeshWeighted, def: false);
      meshes.add(MeshAttachment(
        name: _bStr(
            obj, wire.bonyPropertyKeyName, strings, 'meshAttachment.name'),
        weighted: meshWeighted,
        vertices: _bMeshVertices(obj, meshWeighted, strings),
        uvs: _bMeshUvs(obj),
        triangles: _bMeshTriangles(obj),
      ));
    },
    wire.bonyTypeKeyNestedRigAttachment: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      nestedRigAttachments.add(NestedRigAttachment(
        name: _bStr(
            obj, wire.bonyPropertyKeyName, strings, 'nestedRigAttachment.name'),
        skeleton: _bStr(obj, wire.bonyPropertyKeyNestedSkeleton, strings,
            'nestedRigAttachment.skeleton'),
        skin: _bStr(obj, wire.bonyPropertyKeyNestedSkin, strings,
            'nestedRigAttachment.skin',
            def: ''),
        animation: _bStr(obj, wire.bonyPropertyKeyNestedAnimation, strings,
            'nestedRigAttachment.animation',
            def: ''),
      ));
    },
    wire.bonyTypeKeySkin: (obj) {
      deformerBuilder.flush();
      skinBuilder.start(
        name: _bStr(obj, wire.bonyPropertyKeyName, strings, 'skin.name'),
        bones: _bIndexList(
            obj, wire.bonyPropertyKeySkinBones, boneNames(), 'skin.bones'),
        ikConstraints: _bIndexList(obj, wire.bonyPropertyKeySkinIkConstraints,
            ikNames(), 'skin.ikConstraints'),
        transformConstraints: _bIndexList(
            obj,
            wire.bonyPropertyKeySkinTransformConstraints,
            transformNames(),
            'skin.transformConstraints'),
        pathConstraints: _bIndexList(
            obj,
            wire.bonyPropertyKeySkinPathConstraints,
            pathNames(),
            'skin.pathConstraints'),
        physicsConstraints: _bIndexList(
            obj,
            wire.bonyPropertyKeySkinPhysicsConstraints,
            physicsNames(),
            'skin.physicsConstraints'),
      );
    },
    wire.bonyTypeKeySkinEntry: (obj) {
      deformerBuilder.flush();
      skinBuilder.addEntry(SkinEntryData(
        slot: _bStr(obj, wire.bonyPropertyKeySlot, strings, 'skinEntry.slot'),
        attachment: _bStr(obj, wire.bonyPropertyKeySkinAttachment, strings,
            'skinEntry.attachment'),
        target: _bStr(
            obj, wire.bonyPropertyKeySkinTarget, strings, 'skinEntry.target'),
      ));
    },
    wire.bonyTypeKeyPath: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      paths.add(PathConstraintData(
        name: _bStr(obj, wire.bonyPropertyKeyName, strings, 'path.name'),
        bone: _bStr(obj, wire.bonyPropertyKeyBone, strings, 'path.bone'),
        target: _bStr(obj, wire.bonyPropertyKeyTarget, strings, 'path.target'),
        path: _bStr(obj, wire.bonyPropertyKeyPath, strings, 'path.path'),
        order: _bVarint(obj, wire.bonyPropertyKeyOrder, def: 0),
        skinRequired: _bBool(obj, wire.bonyPropertyKeySkinRequired),
        position: obj.props.containsKey(wire.bonyPropertyKeyPosition)
            ? _bF32(obj, wire.bonyPropertyKeyPosition, 'path.position')
            : null,
        translateMix: obj.props.containsKey(wire.bonyPropertyKeyTranslateMix)
            ? _bF32(obj, wire.bonyPropertyKeyTranslateMix, 'path.translateMix')
            : null,
        rotateMix: obj.props.containsKey(wire.bonyPropertyKeyRotateMix)
            ? _bF32(obj, wire.bonyPropertyKeyRotateMix, 'path.rotateMix')
            : null,
      ));
    },
    wire.bonyTypeKeyIkConstraint: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      ikConstraints.add(IkConstraintData(
        name:
            _bStr(obj, wire.bonyPropertyKeyName, strings, 'ikConstraint.name'),
        bones: _bIkBones(obj, strings),
        target: _bStr(
            obj, wire.bonyPropertyKeyTarget, strings, 'ikConstraint.target'),
        order: _bVarint(obj, wire.bonyPropertyKeyOrder, def: 0),
        skinRequired: _bBool(obj, wire.bonyPropertyKeySkinRequired),
        // Absent => null (mix defaults to 1.0, bendPositive to true).
        mix: obj.props.containsKey(wire.bonyPropertyKeyMix)
            ? _bF32(obj, wire.bonyPropertyKeyMix, 'ikConstraint.mix')
            : null,
        bendPositive: obj.props.containsKey(wire.bonyPropertyKeyBendPositive)
            ? _bBool(obj, wire.bonyPropertyKeyBendPositive)
            : null,
      ));
    },
    wire.bonyTypeKeyTransformConstraint: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      transformConstraints.add(TransformConstraintData(
        name: _bStr(
            obj, wire.bonyPropertyKeyName, strings, 'transformConstraint.name'),
        bone: _bStr(
            obj, wire.bonyPropertyKeyBone, strings, 'transformConstraint.bone'),
        target: _bStr(obj, wire.bonyPropertyKeyTarget, strings,
            'transformConstraint.target'),
        order: _bVarint(obj, wire.bonyPropertyKeyOrder, def: 0),
        skinRequired: _bBool(obj, wire.bonyPropertyKeySkinRequired),
        // Absent => null (each mix defaults to 1.0).
        translateMix: obj.props.containsKey(wire.bonyPropertyKeyTranslateMix)
            ? _bF32(obj, wire.bonyPropertyKeyTranslateMix,
                'transformConstraint.translateMix')
            : null,
        rotateMix: obj.props.containsKey(wire.bonyPropertyKeyRotateMix)
            ? _bF32(obj, wire.bonyPropertyKeyRotateMix,
                'transformConstraint.rotateMix')
            : null,
        scaleMix: obj.props.containsKey(wire.bonyPropertyKeyScaleMix)
            ? _bF32(obj, wire.bonyPropertyKeyScaleMix,
                'transformConstraint.scaleMix')
            : null,
        shearMix: obj.props.containsKey(wire.bonyPropertyKeyShearMix)
            ? _bF32(obj, wire.bonyPropertyKeyShearMix,
                'transformConstraint.shearMix')
            : null,
      ));
    },
    wire.bonyTypeKeyPhysicsConstraint: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      if (!obj.props.containsKey(wire.bonyPropertyKeyChannels)) {
        throw const FormatException(
            '.bnb physicsConstraint.channels is required');
      }
      physicsConstraints.add(PhysicsConstraintData(
        name: _bStr(
            obj, wire.bonyPropertyKeyName, strings, 'physicsConstraint.name'),
        bone: _bStr(
            obj, wire.bonyPropertyKeyBone, strings, 'physicsConstraint.bone'),
        // channels is an unsigned varuint bitmask (NOT the signed/zigzag
        // varint used by `order`), matching generated/wire.dart's varuint
        // backingType and the Nim writeVaruintPayload emission.
        channels: physicsChannelsFromMask(
            _bVaruint(obj, wire.bonyPropertyKeyChannels)),
        order: _bVarint(obj, wire.bonyPropertyKeyOrder, def: 0),
        skinRequired: _bBool(obj, wire.bonyPropertyKeySkinRequired),
        // Absent => null (integrator defaults: mass=1.0/physicsMix=1.0/rest 0.0).
        inertia: obj.props.containsKey(wire.bonyPropertyKeyInertia)
            ? _bF32(
                obj, wire.bonyPropertyKeyInertia, 'physicsConstraint.inertia')
            : null,
        strength: obj.props.containsKey(wire.bonyPropertyKeyStrength)
            ? _bF32(
                obj, wire.bonyPropertyKeyStrength, 'physicsConstraint.strength')
            : null,
        damping: obj.props.containsKey(wire.bonyPropertyKeyDamping)
            ? _bF32(
                obj, wire.bonyPropertyKeyDamping, 'physicsConstraint.damping')
            : null,
        mass: obj.props.containsKey(wire.bonyPropertyKeyMass)
            ? _bF32(obj, wire.bonyPropertyKeyMass, 'physicsConstraint.mass')
            : null,
        gravity: obj.props.containsKey(wire.bonyPropertyKeyGravity)
            ? _bF32(
                obj, wire.bonyPropertyKeyGravity, 'physicsConstraint.gravity')
            : null,
        wind: obj.props.containsKey(wire.bonyPropertyKeyWind)
            ? _bF32(obj, wire.bonyPropertyKeyWind, 'physicsConstraint.wind')
            : null,
        physicsMix: obj.props.containsKey(wire.bonyPropertyKeyPhysicsMix)
            ? _bF32(obj, wire.bonyPropertyKeyPhysicsMix,
                'physicsConstraint.physicsMix')
            : null,
      ));
    },
    wire.bonyTypeKeyPathAttachment: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      pathAttachments.add(PathAttachment(
        name: _bStr(
            obj, wire.bonyPropertyKeyName, strings, 'pathAttachment.name'),
        p0x: _bF64(obj, wire.bonyPropertyKeyP0x, 'pathAttachment.p0x'),
        p0y: _bF64(obj, wire.bonyPropertyKeyP0y, 'pathAttachment.p0y'),
        p1x: _bF64(obj, wire.bonyPropertyKeyP1x, 'pathAttachment.p1x'),
        p1y: _bF64(obj, wire.bonyPropertyKeyP1y, 'pathAttachment.p1y'),
        p2x: _bF64(obj, wire.bonyPropertyKeyP2x, 'pathAttachment.p2x'),
        p2y: _bF64(obj, wire.bonyPropertyKeyP2y, 'pathAttachment.p2y'),
        p3x: _bF64(obj, wire.bonyPropertyKeyP3x, 'pathAttachment.p3x'),
        p3y: _bF64(obj, wire.bonyPropertyKeyP3y, 'pathAttachment.p3y'),
      ));
      // --- M7 objects ---
    },
    wire.bonyTypeKeyParameter: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      final name =
          _bStr(obj, wire.bonyPropertyKeyName, strings, 'parameter.name');
      final min = _bF32(obj, wire.bonyPropertyKeyParameterMin, 'parameter.min');
      final max = _bF32(obj, wire.bonyPropertyKeyParameterMax, 'parameter.max');
      final def = obj.props.containsKey(wire.bonyPropertyKeyParameterDefault)
          ? _bF32(
              obj, wire.bonyPropertyKeyParameterDefault, 'parameter.default')
          : 0.0;
      final axis = ParameterAxis(
        name: name,
        minValue: min,
        maxValue: max,
        defaultValue: def,
      );
      parameters.add(axis);
      paramsByName[name] = axis;
    },
    wire.bonyTypeKeyDeformer: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      final kindStr = _bStr(
          obj, wire.bonyPropertyKeyDeformerKind, strings, 'deformer.kind');
      final kind = switch (kindStr) {
        'warp' => DeformerKind.warp,
        'rotation' => DeformerKind.rotation,
        _ => throw FormatException(
            '.bnb deformer.kind must be warp or rotation: $kindStr'),
      };
      deformerBuilder.start(
        id: _bStr(obj, wire.bonyPropertyKeyDeformerId, strings, 'deformer.id'),
        parent: _bStr(
            obj, wire.bonyPropertyKeyParent, strings, 'deformer.parent',
            def: ''),
        order: _bVaruint(obj, wire.bonyPropertyKeyDeformerOrder, def: 0),
        kind: kind,
      );
    },
    wire.bonyTypeKeyWarpLattice: (obj) {
      deformerBuilder.setWarp(WarpLattice(
        rows: _bVaruint(obj, wire.bonyPropertyKeyWarpRows, def: 2),
        cols: _bVaruint(obj, wire.bonyPropertyKeyWarpCols, def: 2),
        minX: _bF32(obj, wire.bonyPropertyKeyWarpMinX, 'warpLattice.minX'),
        minY: _bF32(obj, wire.bonyPropertyKeyWarpMinY, 'warpLattice.minY'),
        maxX: _bF32(obj, wire.bonyPropertyKeyWarpMaxX, 'warpLattice.maxX'),
        maxY: _bF32(obj, wire.bonyPropertyKeyWarpMaxY, 'warpLattice.maxY'),
        controlPoints: _bControlPoints(obj, strings),
      ));
    },
    wire.bonyTypeKeyRotationDeformer: (obj) {
      deformerBuilder.setRotation(RotationDeformerData(
        pivotX: _bF32(
            obj, wire.bonyPropertyKeyRotationPivotX, 'rotationDeformer.pivotX'),
        pivotY: _bF32(
            obj, wire.bonyPropertyKeyRotationPivotY, 'rotationDeformer.pivotY'),
        angleDegrees: _bF32(obj, wire.bonyPropertyKeyRotationAngleDegrees,
            'rotationDeformer.angleDegrees'),
        scaleX: _bF32(
            obj, wire.bonyPropertyKeyRotationScaleX, 'rotationDeformer.scaleX',
            def: 1.0),
        scaleY: _bF32(
            obj, wire.bonyPropertyKeyRotationScaleY, 'rotationDeformer.scaleY',
            def: 1.0),
        opacity: _bF32(obj, wire.bonyPropertyKeyRotationOpacity,
            'rotationDeformer.opacity',
            def: 1.0),
      ));
    },
    wire.bonyTypeKeyKeyformBlend: (obj) {
      deformerBuilder.startBlend(
        valueCount: _bVaruint(obj, wire.bonyPropertyKeyBlendValueCount, def: 0),
        axes: _bBlendAxes(obj, strings, paramsByName),
      );
    },
    wire.bonyTypeKeyKeyform: (obj) {
      final coordVals = _bF32Array(obj, wire.bonyPropertyKeyBlendCoordinates,
          deformerBuilder.blendAxes.length, 'keyform.coordinates');
      final values = _bF32Array(obj, wire.bonyPropertyKeyBlendValues,
          deformerBuilder.blendValueCount, 'keyform.values');
      final coordinates = [
        for (var i = 0; i < deformerBuilder.blendAxes.length; i++)
          ParameterSample(
              name: deformerBuilder.blendAxes[i].name, value: coordVals[i]),
      ];
      deformerBuilder
          .addKeyform(Keyform(coordinates: coordinates, values: values));
    },
    wire.bonyTypeKeyAnimationClip: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      animationBuilder.start(
          _bStr(obj, wire.bonyPropertyKeyName, strings, 'animationClip.name'));
    },
    wire.bonyTypeKeyBoneTimeline: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      animationBuilder.requireActive('.bnb boneTimeline without animationClip');
      final boneIndex = _bVaruint(obj, wire.bonyPropertyKeyBoneIndex);
      if (boneIndex < 0 || boneIndex >= bones.length) {
        throw const FormatException(
            '.bnb boneTimeline.boneIndex is out of range');
      }
      final payload = obj.props[wire.bonyPropertyKeyTimelineKeys];
      if (payload == null)
        throw const FormatException(
            '.bnb boneTimeline.timelineKeys is required');
      animationBuilder.addBoneTimeline(_bBoneTimelineKeys(
        bones[boneIndex].name,
        _bBoneTimelineKind(_bRequiredVaruint(
            obj, wire.bonyPropertyKeyBoneTimelineKind, 'boneTimeline.kind')),
        payload,
        'boneTimeline.timelineKeys',
      ));
    },
    wire.bonyTypeKeySlotTimeline: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      animationBuilder.requireActive('.bnb slotTimeline without animationClip');
      final slotIndex = _bVaruint(obj, wire.bonyPropertyKeySlotIndex);
      if (slotIndex < 0 || slotIndex >= slots.length) {
        throw const FormatException(
            '.bnb slotTimeline.slotIndex is out of range');
      }
      final payload = obj.props[wire.bonyPropertyKeyTimelineKeys];
      if (payload == null)
        throw const FormatException(
            '.bnb slotTimeline.timelineKeys is required');
      animationBuilder.addSlotTimeline(_bSlotTimelineKeys(
        slots[slotIndex].name,
        _bSlotTimelineKind(_bRequiredVaruint(
            obj, wire.bonyPropertyKeySlotTimelineKind, 'slotTimeline.kind')),
        payload,
        regions,
        'slotTimeline.timelineKeys',
      ));
    },
    wire.bonyTypeKeyDrawOrderTimeline: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      animationBuilder
          .requireActive('.bnb drawOrderTimeline without animationClip');
      final payload = obj.props[wire.bonyPropertyKeyDrawOrderKeys];
      if (payload == null) {
        throw const FormatException(
            '.bnb drawOrderTimeline.drawOrderKeys is required');
      }
      animationBuilder.addDrawOrderTimeline(DrawOrderTimeline(
        keys: _bDrawOrderTimelineKeys(
            payload, slots, 'drawOrderTimeline.drawOrderKeys'),
      ));
    },
    wire.bonyTypeKeyEventTimeline: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      animationBuilder
          .requireActive('.bnb eventTimeline without animationClip');
      final payload = obj.props[wire.bonyPropertyKeyEventKeys];
      if (payload == null)
        throw const FormatException('.bnb eventTimeline.eventKeys is required');
      animationBuilder.addEventTimeline(EventTimeline(
        keys: _bEventTimelineKeys(payload, strings, 'eventTimeline.eventKeys'),
      ));
    },
    wire.bonyTypeKeyDeformTimeline: (obj) {
      skinBuilder.flush();
      // Relies on meshAttachment objects being decoded before deform-timeline
      // objects: the encoder emits meshes (type 3001) before animation clips,
      // and the SM-only reordering above never moves a mesh after a clip, so
      // `meshes` is fully populated for the vertexCount lookup below.
      deformerBuilder.flush();
      animationBuilder
          .requireActive('.bnb deformTimeline without animationClip');
      final skin = _bStr(
          obj, wire.bonyPropertyKeyDeformSkin, strings, 'deformTimeline.skin');
      final resolutionData = skinResolutionData();
      if (!resolutionData.hasSkin(skin)) {
        throw FormatException(
            '.bnb deformTimeline references unknown skin: $skin');
      }
      final slot =
          _bStr(obj, wire.bonyPropertyKeySlot, strings, 'deformTimeline.slot');
      final attachment = _bStr(obj, wire.bonyPropertyKeyDeformAttachment,
          strings, 'deformTimeline.attachment');
      final resolvedAttachment =
          resolutionData.resolveSkinAttachmentTarget(skin, slot, attachment);
      if (resolvedAttachment.isEmpty) {
        throw FormatException(
            '.bnb deformTimeline does not resolve through skin lookup: '
            '$skin/$slot/$attachment');
      }
      final vertexCount = _bRequiredVaruint(obj,
          wire.bonyPropertyKeyDeformVertexCount, 'deformTimeline.vertexCount');
      MeshAttachment? mesh;
      for (final m in meshes) {
        if (m.name == resolvedAttachment) {
          mesh = m;
          break;
        }
      }
      if (mesh == null) {
        throw FormatException(
            '.bnb deformTimeline resolved attachment is not a mesh: '
            '$resolvedAttachment');
      }
      if (vertexCount != mesh.vertices.length) {
        throw FormatException(
            '.bnb deformTimeline.vertexCount does not match mesh: '
            '$resolvedAttachment');
      }
      final payload = obj.props[wire.bonyPropertyKeyDeformKeys];
      if (payload == null)
        throw const FormatException(
            '.bnb deformTimeline.deformKeys is required');
      animationBuilder.addDeformTimeline(DeformTimeline(
        skin: skin,
        slot: slot,
        attachment: attachment,
        vertexCount: vertexCount,
        keys: _bDeformTimelineKeys(
            payload, vertexCount, 'deformTimeline.deformKeys'),
      ));
    },
    wire.bonyTypeKeyStateMachine: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      animationBuilder.flush();
      stateMachineBuilder.start(
          _bStr(obj, wire.bonyPropertyKeyName, strings, 'stateMachine.name'));
    },
    wire.bonyTypeKeyStateMachineInput: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      stateMachineBuilder.flushLayer();
      stateMachineBuilder
          .requireActive('.bnb stateMachineInput without stateMachine');
      final kindTag = _bRequiredVaruint(obj,
          wire.bonyPropertyKeyStateMachineInputKind, 'stateMachineInput.kind');
      final name = _bStr(
          obj, wire.bonyPropertyKeyName, strings, 'stateMachineInput.name');
      switch (kindTag) {
        case 0:
          if (obj.props.containsKey(wire.bonyPropertyKeyInputDefaultNumber)) {
            throw const FormatException(
                '.bnb bool input must not contain number default');
          }
          stateMachineBuilder.addInput(StateMachineInput(
            name: name,
            kind: StateMachineInputKind.bool_,
            defaultBool: _bBool(obj, wire.bonyPropertyKeyInputDefaultBool),
          ));
        case 1:
          if (obj.props.containsKey(wire.bonyPropertyKeyInputDefaultBool)) {
            throw const FormatException(
                '.bnb number input must not contain bool default');
          }
          stateMachineBuilder.addInput(StateMachineInput(
            name: name,
            kind: StateMachineInputKind.number,
            defaultNumber: _bF32(obj, wire.bonyPropertyKeyInputDefaultNumber,
                'stateMachineInput.defaultNumber',
                def: 0.0),
          ));
        case 2:
          if (obj.props.containsKey(wire.bonyPropertyKeyInputDefaultBool) ||
              obj.props.containsKey(wire.bonyPropertyKeyInputDefaultNumber)) {
            throw const FormatException(
                '.bnb trigger input must not contain defaults');
          }
          stateMachineBuilder.addInput(StateMachineInput(
              name: name, kind: StateMachineInputKind.trigger));
        default:
          throw FormatException(
              '.bnb stateMachineInput.kind is invalid: $kindTag');
      }
    },
    wire.bonyTypeKeyStateMachineLayer: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      stateMachineBuilder.flushLayer();
      stateMachineBuilder
          .requireActive('.bnb stateMachineLayer without stateMachine');
      stateMachineBuilder.startLayer(
        _bStr(obj, wire.bonyPropertyKeyName, strings, 'stateMachineLayer.name'),
        _bVaruint(obj, wire.bonyPropertyKeyInitialStateIndex),
      );
    },
    wire.bonyTypeKeyStateMachineState: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      stateMachineBuilder.flushTransition();
      stateMachineBuilder
          .requireOpenLayer('.bnb stateMachineState without layer');
      final stateName = _bStr(
          obj, wire.bonyPropertyKeyName, strings, 'stateMachineState.name');
      final kindTag = _bRequiredVaruint(obj,
          wire.bonyPropertyKeyStateMachineStateKind, 'stateMachineState.kind');
      switch (kindTag) {
        case 0:
          if (obj.props.containsKey(wire.bonyPropertyKeyStateBlendInputIndex)) {
            throw const FormatException(
                '.bnb clip state must not contain blend input');
          }
          final clipIndex = _bRequiredVaruint(obj,
              wire.bonyPropertyKeyStateClipIndex, 'stateMachineState.clip');
          if (clipIndex < 0 || clipIndex >= animations.length) {
            throw const FormatException(
                '.bnb stateMachineState.clip index is out of range');
          }
          stateMachineBuilder.addState(StateMachineState(
            name: stateName,
            kind: StateMachineStateKind.clip,
            clipName: animations[clipIndex].name,
            loop: _bBool(obj, wire.bonyPropertyKeyStateLoop),
          ));
        case 1:
          if (obj.props.containsKey(wire.bonyPropertyKeyStateClipIndex) ||
              obj.props.containsKey(wire.bonyPropertyKeyStateLoop)) {
            throw const FormatException(
                '.bnb blend1d state must not contain direct clip fields');
          }
          final inputIndex = _bRequiredVaruint(
              obj,
              wire.bonyPropertyKeyStateBlendInputIndex,
              'stateMachineState.blendInput');
          if (inputIndex < 0 ||
              inputIndex >= stateMachineBuilder.inputs.length) {
            throw const FormatException(
                '.bnb stateMachineState.blendInput index is out of range');
          }
          stateMachineBuilder.addState(StateMachineState(
            name: stateName,
            kind: StateMachineStateKind.blend1d,
            blendInput: stateMachineBuilder.inputs[inputIndex].name,
            blendClips: <StateMachineBlendClip>[],
          ));
        default:
          throw FormatException(
              '.bnb stateMachineState.kind is invalid: $kindTag');
      }
    },
    wire.bonyTypeKeyStateMachineBlendClip: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      if (stateMachineBuilder.currentLayerStates.isEmpty ||
          stateMachineBuilder.currentLayerStates.last.kind !=
              StateMachineStateKind.blend1d) {
        throw const FormatException(
            '.bnb stateMachineBlendClip without blend1d state');
      }
      final clipIndex = _bRequiredVaruint(
          obj,
          wire.bonyPropertyKeyBlendClipAnimationIndex,
          'stateMachineBlendClip.animation');
      if (clipIndex < 0 || clipIndex >= animations.length) {
        throw const FormatException(
            '.bnb stateMachineBlendClip.animation index is out of range');
      }
      final previous = stateMachineBuilder.removeLastState();
      stateMachineBuilder.addState(StateMachineState(
        name: previous.name,
        kind: previous.kind,
        blendInput: previous.blendInput,
        blendClips: [
          ...previous.blendClips,
          StateMachineBlendClip(
            clipName: animations[clipIndex].name,
            value: _bF32(obj, wire.bonyPropertyKeyBlendClipValue,
                'stateMachineBlendClip.value'),
            loop: _bBool(obj, wire.bonyPropertyKeyBlendClipLoop),
          ),
        ],
      ));
    },
    wire.bonyTypeKeyStateMachineTransition: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      stateMachineBuilder.flushTransition();
      stateMachineBuilder
          .requireOpenLayer('.bnb stateMachineTransition without layer');
      stateMachineBuilder.startTransition(
        _stateNameAt(
            stateMachineBuilder.currentLayerStates,
            _bRequiredVaruint(obj, wire.bonyPropertyKeyTransitionFromStateIndex,
                'stateMachineTransition.from'),
            'stateMachineTransition.from'),
        _stateNameAt(
            stateMachineBuilder.currentLayerStates,
            _bRequiredVaruint(obj, wire.bonyPropertyKeyTransitionToStateIndex,
                'stateMachineTransition.to'),
            'stateMachineTransition.to'),
      );
    },
    wire.bonyTypeKeyStateMachineCondition: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      stateMachineBuilder.requirePendingTransition(
          '.bnb stateMachineCondition without transition');
      final inputIndex = _bRequiredVaruint(
          obj,
          wire.bonyPropertyKeyConditionInputIndex,
          'stateMachineCondition.input');
      if (inputIndex < 0 || inputIndex >= stateMachineBuilder.inputs.length) {
        throw const FormatException(
            '.bnb stateMachineCondition.input index is out of range');
      }
      final input = stateMachineBuilder.inputs[inputIndex];
      final kindTag = _bRequiredVaruint(
          obj,
          wire.bonyPropertyKeyStateMachineConditionKind,
          'stateMachineCondition.kind');
      switch (kindTag) {
        case 0:
          if (obj.props.containsKey(wire.bonyPropertyKeyConditionNumberValue)) {
            throw const FormatException(
                '.bnb bool condition must not contain number value');
          }
          stateMachineBuilder.addCondition(StateMachineCondition(
            input: input.name,
            kind: StateMachineConditionKind.boolEquals,
            boolValue:
                _bBool(obj, wire.bonyPropertyKeyConditionBoolValue, def: true),
          ));
        case 1:
          if (obj.props.containsKey(wire.bonyPropertyKeyConditionBoolValue)) {
            throw const FormatException(
                '.bnb number condition must not contain bool value');
          }
          stateMachineBuilder.addCondition(StateMachineCondition(
              input: input.name,
              kind: StateMachineConditionKind.numberEquals,
              numberValue: _bF32(obj, wire.bonyPropertyKeyConditionNumberValue,
                  'condition.number')));
        case 2:
          if (obj.props.containsKey(wire.bonyPropertyKeyConditionBoolValue)) {
            throw const FormatException(
                '.bnb number condition must not contain bool value');
          }
          stateMachineBuilder.addCondition(StateMachineCondition(
              input: input.name,
              kind: StateMachineConditionKind.numberGreater,
              numberValue: _bF32(obj, wire.bonyPropertyKeyConditionNumberValue,
                  'condition.number')));
        case 3:
          if (obj.props.containsKey(wire.bonyPropertyKeyConditionBoolValue)) {
            throw const FormatException(
                '.bnb number condition must not contain bool value');
          }
          stateMachineBuilder.addCondition(StateMachineCondition(
              input: input.name,
              kind: StateMachineConditionKind.numberGreaterOrEqual,
              numberValue: _bF32(obj, wire.bonyPropertyKeyConditionNumberValue,
                  'condition.number')));
        case 4:
          if (obj.props.containsKey(wire.bonyPropertyKeyConditionBoolValue)) {
            throw const FormatException(
                '.bnb number condition must not contain bool value');
          }
          stateMachineBuilder.addCondition(StateMachineCondition(
              input: input.name,
              kind: StateMachineConditionKind.numberLess,
              numberValue: _bF32(obj, wire.bonyPropertyKeyConditionNumberValue,
                  'condition.number')));
        case 5:
          if (obj.props.containsKey(wire.bonyPropertyKeyConditionBoolValue)) {
            throw const FormatException(
                '.bnb number condition must not contain bool value');
          }
          stateMachineBuilder.addCondition(StateMachineCondition(
              input: input.name,
              kind: StateMachineConditionKind.numberLessOrEqual,
              numberValue: _bF32(obj, wire.bonyPropertyKeyConditionNumberValue,
                  'condition.number')));
        case 6:
          if (obj.props.containsKey(wire.bonyPropertyKeyConditionBoolValue) ||
              obj.props.containsKey(wire.bonyPropertyKeyConditionNumberValue)) {
            throw const FormatException(
                '.bnb trigger condition must not contain values');
          }
          stateMachineBuilder.addCondition(StateMachineCondition(
              input: input.name, kind: StateMachineConditionKind.triggerSet));
        default:
          throw FormatException(
              '.bnb stateMachineCondition.kind is invalid: $kindTag');
      }
    },
    wire.bonyTypeKeyStateMachineListener: (obj) {
      skinBuilder.flush();
      deformerBuilder.flush();
      stateMachineBuilder.flushLayer();
      stateMachineBuilder
          .requireActive('.bnb stateMachineListener without stateMachine');
      final listenerName = _bStr(
          obj, wire.bonyPropertyKeyName, strings, 'stateMachineListener.name');
      final kindTag = _bRequiredVaruint(
          obj,
          wire.bonyPropertyKeyStateMachineListenerKind,
          'stateMachineListener.kind');
      StateMachineLayer listenerLayer() {
        final layerIndex = _bRequiredVaruint(
            obj,
            wire.bonyPropertyKeyListenerLayerIndex,
            'stateMachineListener.layer');
        if (layerIndex < 0 || layerIndex >= stateMachineBuilder.layers.length) {
          throw const FormatException(
              '.bnb stateMachineListener.layer index is out of range');
        }
        return stateMachineBuilder.layers[layerIndex];
      }

      bool hasPointerFields() =>
          obj.props.containsKey(wire.bonyPropertyKeyListenerSlotIndex) ||
          obj.props.containsKey(wire.bonyPropertyKeyListenerHelperKind) ||
          obj.props.containsKey(wire.bonyPropertyKeyListenerHelperTarget) ||
          obj.props.containsKey(wire.bonyPropertyKeyListenerInputIndex) ||
          obj.props.containsKey(wire.bonyPropertyKeyListenerBoolValue) ||
          obj.props.containsKey(wire.bonyPropertyKeyListenerNumberValue) ||
          obj.props.containsKey(wire.bonyPropertyKeyListenerHitRadius);

      switch (kindTag) {
        case 0:
          final layer = listenerLayer();
          if (hasPointerFields()) {
            throw const FormatException(
                '.bnb lifecycle listener must not contain pointer fields');
          }
          if (obj.props
              .containsKey(wire.bonyPropertyKeyListenerFromStateIndex)) {
            throw const FormatException(
                '.bnb enter listener must not contain from state');
          }
          stateMachineBuilder.addListener(StateMachineListener(
            name: listenerName,
            kind: StateMachineListenerKind.stateEnter,
            layer: layer.name,
            toState: _stateNameAt(
                layer.states,
                _bRequiredVaruint(obj, wire.bonyPropertyKeyListenerToStateIndex,
                    'stateMachineListener.to'),
                'stateMachineListener.to'),
          ));
        case 1:
          final layer = listenerLayer();
          if (hasPointerFields()) {
            throw const FormatException(
                '.bnb lifecycle listener must not contain pointer fields');
          }
          if (obj.props.containsKey(wire.bonyPropertyKeyListenerToStateIndex)) {
            throw const FormatException(
                '.bnb exit listener must not contain to state');
          }
          stateMachineBuilder.addListener(StateMachineListener(
            name: listenerName,
            kind: StateMachineListenerKind.stateExit,
            layer: layer.name,
            fromState: _stateNameAt(
                layer.states,
                _bRequiredVaruint(
                    obj,
                    wire.bonyPropertyKeyListenerFromStateIndex,
                    'stateMachineListener.from'),
                'stateMachineListener.from'),
          ));
        case 2:
          final layer = listenerLayer();
          if (hasPointerFields()) {
            throw const FormatException(
                '.bnb lifecycle listener must not contain pointer fields');
          }
          stateMachineBuilder.addListener(StateMachineListener(
            name: listenerName,
            kind: StateMachineListenerKind.transition_,
            layer: layer.name,
            fromState: _stateNameAt(
                layer.states,
                _bRequiredVaruint(
                    obj,
                    wire.bonyPropertyKeyListenerFromStateIndex,
                    'stateMachineListener.from'),
                'stateMachineListener.from'),
            toState: _stateNameAt(
                layer.states,
                _bRequiredVaruint(obj, wire.bonyPropertyKeyListenerToStateIndex,
                    'stateMachineListener.to'),
                'stateMachineListener.to'),
          ));
        case 3:
        case 4:
        case 5:
        case 6:
        case 7:
          if (obj.props.containsKey(wire.bonyPropertyKeyListenerLayerIndex) ||
              obj.props
                  .containsKey(wire.bonyPropertyKeyListenerFromStateIndex) ||
              obj.props.containsKey(wire.bonyPropertyKeyListenerToStateIndex)) {
            throw const FormatException(
                '.bnb pointer listener must not contain lifecycle fields');
          }
          final slotIndex = _bRequiredVaruint(
              obj,
              wire.bonyPropertyKeyListenerSlotIndex,
              'stateMachineListener.slot');
          if (slotIndex < 0 || slotIndex >= slots.length) {
            throw const FormatException(
                '.bnb stateMachineListener.slot index is out of range');
          }
          final inputIndex = _bRequiredVaruint(
              obj,
              wire.bonyPropertyKeyListenerInputIndex,
              'stateMachineListener.input');
          if (inputIndex < 0 ||
              inputIndex >= stateMachineBuilder.inputs.length) {
            throw const FormatException(
                '.bnb stateMachineListener.input index is out of range');
          }
          final helperKindTag = _bRequiredVaruint(
              obj,
              wire.bonyPropertyKeyListenerHelperKind,
              'stateMachineListener.helperKind');
          final helperKind = switch (helperKindTag) {
            0 => PointerHelperTargetKind.point,
            1 => PointerHelperTargetKind.boundingBox,
            _ => throw FormatException(
                '.bnb stateMachineListener.helperKind is invalid: $helperKindTag'),
          };
          final input = stateMachineBuilder.inputs[inputIndex];
          bool? boolValue;
          double? numberValue;
          switch (input.kind) {
            case StateMachineInputKind.bool_:
              if (!obj.props
                  .containsKey(wire.bonyPropertyKeyListenerBoolValue)) {
                throw const FormatException(
                    '.bnb pointer bool listener value is required');
              }
              if (obj.props
                  .containsKey(wire.bonyPropertyKeyListenerNumberValue)) {
                throw const FormatException(
                    '.bnb pointer bool listener must not contain number value');
              }
              boolValue = _bBool(obj, wire.bonyPropertyKeyListenerBoolValue);
            case StateMachineInputKind.number:
              if (obj.props
                  .containsKey(wire.bonyPropertyKeyListenerBoolValue)) {
                throw const FormatException(
                    '.bnb pointer number listener must not contain bool value');
              }
              numberValue = _bF32(obj, wire.bonyPropertyKeyListenerNumberValue,
                  'stateMachineListener.numberValue');
            case StateMachineInputKind.trigger:
              if (obj.props
                      .containsKey(wire.bonyPropertyKeyListenerBoolValue) ||
                  obj.props
                      .containsKey(wire.bonyPropertyKeyListenerNumberValue)) {
                throw const FormatException(
                    '.bnb pointer trigger listener must not contain values');
              }
          }
          double? hitRadius;
          switch (helperKind) {
            case PointerHelperTargetKind.point:
              hitRadius = _bF32(obj, wire.bonyPropertyKeyListenerHitRadius,
                  'stateMachineListener.hitRadius');
            case PointerHelperTargetKind.boundingBox:
              if (obj.props
                  .containsKey(wire.bonyPropertyKeyListenerHitRadius)) {
                throw const FormatException(
                    '.bnb pointer bounding-box listener must not contain hitRadius');
              }
          }
          stateMachineBuilder.addListener(StateMachineListener(
            name: listenerName,
            kind: StateMachineListenerKind.values[kindTag],
            slot: slots[slotIndex].name,
            targetKind: helperKind,
            target: _bStr(obj, wire.bonyPropertyKeyListenerHelperTarget,
                strings, 'stateMachineListener.target'),
            hitRadius: hitRadius,
            input: input.name,
            boolValue: boolValue,
            numberValue: numberValue,
          ));
        default:
          throw FormatException(
              '.bnb stateMachineListener.kind is invalid: $kindTag');
      }
    },
  };

  for (final obj in decodeObjects) {
    final handler = handlers[obj.typeKey];
    if (handler == null) {
      throw FormatException(
          '.bnb decoder has no handler for known type ${obj.typeKey}');
    }
    handler(obj);
  }
  skinBuilder.flush();
  deformerBuilder.flush();
  animationBuilder.flush();
  stateMachineBuilder.flushMachine();

  if (header == null)
    throw const FormatException('.bnb: missing skeleton object');
  return SkeletonData(
    header: header!,
    bones: bones,
    slots: slots,
    regions: regions,
    paths: paths,
    pathAttachments: pathAttachments,
    pointAttachments: pointAttachments,
    boundingBoxAttachments: boundingBoxAttachments,
    nestedRigAttachments: nestedRigAttachments,
    clippingAttachments: clips,
    meshAttachments: meshes,
    ikConstraints: ikConstraints,
    transformConstraints: transformConstraints,
    physicsConstraints: physicsConstraints,
    skins: skins,
    parameters: parameters,
    deformers: deformers,
    animations: animations,
    stateMachines: stateMachines,
  );
}

class _SkinBuilder {
  _SkinBuilder(this._skins);

  final List<SkinData> _skins;
  var _name = '';
  var _entries = <SkinEntryData>[];
  var _bones = <String>[];
  var _ikConstraints = <String>[];
  var _transformConstraints = <String>[];
  var _pathConstraints = <String>[];
  var _physicsConstraints = <String>[];

  bool get isActive => _name.isNotEmpty;

  void flush() {
    if (!isActive) return;
    _skins.add(SkinData(
      name: _name,
      entries: _entries,
      bones: _bones,
      ikConstraints: _ikConstraints,
      transformConstraints: _transformConstraints,
      pathConstraints: _pathConstraints,
      physicsConstraints: _physicsConstraints,
    ));
    _name = '';
    _entries = [];
    _bones = [];
    _ikConstraints = [];
    _transformConstraints = [];
    _pathConstraints = [];
    _physicsConstraints = [];
  }

  void start({
    required String name,
    required List<String> bones,
    required List<String> ikConstraints,
    required List<String> transformConstraints,
    required List<String> pathConstraints,
    required List<String> physicsConstraints,
  }) {
    flush();
    _name = name;
    _bones = bones;
    _ikConstraints = ikConstraints;
    _transformConstraints = transformConstraints;
    _pathConstraints = pathConstraints;
    _physicsConstraints = physicsConstraints;
  }

  void addEntry(SkinEntryData entry) {
    if (!isActive) {
      throw const FormatException(
          '.bnb skinEntry record without preceding skin');
    }
    _entries.add(entry);
  }
}

class _AnimationBuilder {
  _AnimationBuilder(this._animations);

  final List<AnimationClip> _animations;
  final _seenNames = <String>{};
  var _name = '';
  var _boneTimelines = <BoneTimeline>[];
  var _slotTimelines = <SlotTimeline>[];
  DrawOrderTimeline? _drawOrderTimeline;
  var _deformTimelines = <DeformTimeline>[];
  var _eventTimelines = <EventTimeline>[];

  bool get isActive => _name.isNotEmpty;

  void flush() {
    if (!isActive) return;
    if (!_seenNames.add(_name)) {
      throw FormatException('duplicate animation name: $_name');
    }
    _animations.add(AnimationClip(
      name: _name,
      duration: _animationDuration(_boneTimelines, _slotTimelines,
          _drawOrderTimeline, _deformTimelines, _eventTimelines),
      boneTimelines: _boneTimelines,
      slotTimelines: _slotTimelines,
      drawOrderTimeline: _drawOrderTimeline,
      deformTimelines: _deformTimelines,
      eventTimelines: _eventTimelines,
    ));
    _name = '';
    _boneTimelines = [];
    _slotTimelines = [];
    _drawOrderTimeline = null;
    _deformTimelines = [];
    _eventTimelines = [];
  }

  void start(String name) {
    flush();
    _name = name;
  }

  void requireActive(String message) {
    if (!isActive) throw FormatException(message);
  }

  void addBoneTimeline(BoneTimeline timeline) => _boneTimelines.add(timeline);
  void addSlotTimeline(SlotTimeline timeline) => _slotTimelines.add(timeline);
  void addDrawOrderTimeline(DrawOrderTimeline timeline) {
    if (_drawOrderTimeline != null) {
      throw const FormatException(
          '.bnb animationClip has duplicate drawOrderTimeline records');
    }
    _drawOrderTimeline = timeline;
  }

  void addDeformTimeline(DeformTimeline timeline) =>
      _deformTimelines.add(timeline);
  void addEventTimeline(EventTimeline timeline) =>
      _eventTimelines.add(timeline);
}

class _DeformerBuilder {
  _DeformerBuilder(this._deformers);

  final List<DeformerRecord> _deformers;
  var _pending = false;
  var _id = '';
  var _parent = '';
  var _order = 0;
  var _kind = DeformerKind.warp;
  WarpLattice? _warp;
  RotationDeformerData? _rotation;
  var _geometryReady = false;
  var _blendPending = false;
  var _blendValueCount = 0;
  var _blendAxes = <ParameterAxis>[];
  var _keyforms = <Keyform>[];

  void flush() {
    if (!_pending) return;
    if (!_geometryReady) {
      throw const FormatException(
          '.bnb deformer header has no following geometry record');
    }
    final DeformerData deformerData;
    if (_kind == DeformerKind.warp) {
      deformerData = WarpDeformer(
        id: _id,
        parent: _parent,
        order: _order,
        warp: _warp!,
      );
    } else {
      deformerData = RotationDeformer(
        id: _id,
        parent: _parent,
        order: _order,
        rotation: _rotation!,
      );
    }
    final blend = _blendPending && _blendAxes.isNotEmpty
        ? KeyformBlend(
            axes: _blendAxes,
            valueCount: _blendValueCount,
            keyforms: _keyforms,
          )
        : const KeyformBlend();
    _deformers.add(DeformerRecord(deformer: deformerData, keyformBlend: blend));
    _clearPending();
  }

  void _clearPending() {
    _pending = false;
    _id = '';
    _parent = '';
    _order = 0;
    _kind = DeformerKind.warp;
    _warp = null;
    _rotation = null;
    _geometryReady = false;
    _blendPending = false;
    _blendValueCount = 0;
    _blendAxes = [];
    _keyforms = [];
  }

  void start({
    required String id,
    required String parent,
    required int order,
    required DeformerKind kind,
  }) {
    flush();
    _clearPending();
    _id = id;
    _parent = parent;
    _order = order;
    _kind = kind;
    _pending = true;
    _geometryReady = false;
    _blendPending = false;
    _blendAxes = [];
    _keyforms = [];
  }

  void setWarp(WarpLattice warp) {
    if (!_pending || _kind != DeformerKind.warp) {
      throw const FormatException(
          '.bnb warpLattice without preceding warp deformer');
    }
    _warp = warp;
    _geometryReady = true;
  }

  void setRotation(RotationDeformerData rotation) {
    if (!_pending || _kind != DeformerKind.rotation) {
      throw const FormatException(
          '.bnb rotationDeformer without preceding rotation deformer');
    }
    _rotation = rotation;
    _geometryReady = true;
  }

  void startBlend({
    required int valueCount,
    required List<ParameterAxis> axes,
  }) {
    if (!_pending || !_geometryReady) {
      throw const FormatException(
          '.bnb keyformBlend without preceding deformer geometry');
    }
    _blendValueCount = valueCount;
    _blendAxes = axes;
    _keyforms = [];
    _blendPending = true;
  }

  void addKeyform(Keyform keyform) {
    if (!_blendPending) {
      throw const FormatException(
          '.bnb keyform without preceding keyformBlend');
    }
    _keyforms.add(keyform);
  }

  int get blendValueCount => _blendValueCount;
  List<ParameterAxis> get blendAxes => _blendAxes;
}

class _StateMachineBuilder {
  _StateMachineBuilder(this._stateMachines);

  final List<StateMachineData> _stateMachines;
  var _name = '';
  var _inputs = <StateMachineInput>[];
  var _layers = <StateMachineLayer>[];
  var _listeners = <StateMachineListener>[];
  var _currentLayerName = '';
  var _currentLayerInitialIndex = 0;
  var _currentLayerStates = <StateMachineState>[];
  var _currentLayerTransitions = <StateMachineTransition>[];
  var _pendingTransitionFrom = '';
  var _pendingTransitionTo = '';
  var _pendingConditions = <StateMachineCondition>[];

  bool get isActive => _name.isNotEmpty;
  bool get hasOpenLayer => _currentLayerName.isNotEmpty;
  bool get hasPendingTransition => _pendingTransitionFrom.isNotEmpty;
  List<StateMachineInput> get inputs => _inputs;
  List<StateMachineLayer> get layers => _layers;
  List<StateMachineState> get currentLayerStates => _currentLayerStates;

  void flushTransition() {
    if (!hasPendingTransition) return;
    _currentLayerTransitions.add(StateMachineTransition(
      fromState: _pendingTransitionFrom,
      toState: _pendingTransitionTo,
      conditions: _pendingConditions,
    ));
    _pendingTransitionFrom = '';
    _pendingTransitionTo = '';
    _pendingConditions = [];
  }

  void flushLayer() {
    if (!hasOpenLayer) return;
    flushTransition();
    _layers.add(StateMachineLayer(
      name: _currentLayerName,
      states: _currentLayerStates,
      initialState: _stateNameAt(_currentLayerStates, _currentLayerInitialIndex,
          'stateMachineLayer.initialStateIndex'),
      transitions: _currentLayerTransitions,
    ));
    _currentLayerName = '';
    _currentLayerInitialIndex = 0;
    _currentLayerStates = [];
    _currentLayerTransitions = [];
  }

  void flushMachine() {
    if (!isActive) return;
    flushLayer();
    _stateMachines.add(StateMachineData(
      name: _name,
      layers: _layers,
      inputs: _inputs,
      listeners: _listeners,
    ));
    _name = '';
    _inputs = [];
    _layers = [];
    _listeners = [];
  }

  void start(String name) {
    flushMachine();
    _name = name;
  }

  void requireActive(String message) {
    if (!isActive) throw FormatException(message);
  }

  void requireOpenLayer(String message) {
    if (!hasOpenLayer) throw FormatException(message);
  }

  void requirePendingTransition(String message) {
    if (!hasPendingTransition) throw FormatException(message);
  }

  void addInput(StateMachineInput input) => _inputs.add(input);

  void startLayer(String name, int initialStateIndex) {
    flushLayer();
    _currentLayerName = name;
    _currentLayerInitialIndex = initialStateIndex;
  }

  void addState(StateMachineState state) => _currentLayerStates.add(state);

  StateMachineState removeLastState() => _currentLayerStates.removeLast();

  void startTransition(String from, String to) {
    flushTransition();
    _pendingTransitionFrom = from;
    _pendingTransitionTo = to;
  }

  void addCondition(StateMachineCondition condition) {
    if (!hasPendingTransition) {
      throw const FormatException(
          '.bnb stateMachineCondition without transition');
    }
    _pendingConditions.add(condition);
  }

  void addListener(StateMachineListener listener) => _listeners.add(listener);
}

String _stateNameAt(List<StateMachineState> states, int index, String ctx) {
  if (index < 0 || index >= states.length) {
    throw FormatException('.bnb $ctx state index is out of range');
  }
  return states[index].name;
}
