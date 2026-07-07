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
  var currentAnimationName = '';
  var currentBoneTimelines = <BoneTimeline>[];
  var currentSlotTimelines = <SlotTimeline>[];
  var currentDeformTimelines = <DeformTimeline>[];
  var currentEventTimelines = <EventTimeline>[];
  var currentMachineName = '';
  var machineInputs = <StateMachineInput>[];
  var machineLayers = <StateMachineLayer>[];
  var machineListeners = <StateMachineListener>[];
  var currentLayerName = '';
  var currentLayerInitialIndex = 0;
  var currentLayerStates = <StateMachineState>[];
  var currentLayerTransitions = <StateMachineTransition>[];
  var pendingTransitionFrom = '';
  var pendingTransitionTo = '';
  var pendingConditions = <StateMachineCondition>[];
  final seenAnimationNames = <String>{};
  var currentSkinName = '';
  var currentSkinEntries = <SkinEntryData>[];
  var currentSkinBones = <String>[];
  var currentSkinIkConstraints = <String>[];
  var currentSkinTransformConstraints = <String>[];
  var currentSkinPathConstraints = <String>[];
  var currentSkinPhysicsConstraints = <String>[];

  void flushSkin() {
    if (currentSkinName.isEmpty) return;
    skins.add(SkinData(
      name: currentSkinName,
      entries: currentSkinEntries,
      bones: currentSkinBones,
      ikConstraints: currentSkinIkConstraints,
      transformConstraints: currentSkinTransformConstraints,
      pathConstraints: currentSkinPathConstraints,
      physicsConstraints: currentSkinPhysicsConstraints,
    ));
    currentSkinName = '';
    currentSkinEntries = [];
    currentSkinBones = [];
    currentSkinIkConstraints = [];
    currentSkinTransformConstraints = [];
    currentSkinPathConstraints = [];
    currentSkinPhysicsConstraints = [];
  }

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
      header: header,
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

  void flushAnimation() {
    if (currentAnimationName.isEmpty) return;
    if (!seenAnimationNames.add(currentAnimationName)) {
      throw FormatException('duplicate animation name: $currentAnimationName');
    }
    animations.add(AnimationClip(
      name: currentAnimationName,
      duration: _animationDuration(currentBoneTimelines, currentSlotTimelines,
          currentDeformTimelines, currentEventTimelines),
      boneTimelines: currentBoneTimelines,
      slotTimelines: currentSlotTimelines,
      deformTimelines: currentDeformTimelines,
      eventTimelines: currentEventTimelines,
    ));
    currentAnimationName = '';
    currentBoneTimelines = [];
    currentSlotTimelines = [];
    currentDeformTimelines = [];
    currentEventTimelines = [];
  }

  String stateNameAt(List<StateMachineState> states, int index, String ctx) {
    if (index < 0 || index >= states.length) {
      throw FormatException('.bnb $ctx state index is out of range');
    }
    return states[index].name;
  }

  void flushTransition() {
    if (pendingTransitionFrom.isEmpty) return;
    currentLayerTransitions.add(StateMachineTransition(
      fromState: pendingTransitionFrom,
      toState: pendingTransitionTo,
      conditions: pendingConditions,
    ));
    pendingTransitionFrom = '';
    pendingTransitionTo = '';
    pendingConditions = [];
  }

  void flushLayer() {
    if (currentLayerName.isEmpty) return;
    flushTransition();
    machineLayers.add(StateMachineLayer(
      name: currentLayerName,
      states: currentLayerStates,
      initialState: stateNameAt(currentLayerStates, currentLayerInitialIndex,
          'stateMachineLayer.initialStateIndex'),
      transitions: currentLayerTransitions,
    ));
    currentLayerName = '';
    currentLayerInitialIndex = 0;
    currentLayerStates = [];
    currentLayerTransitions = [];
  }

  void flushMachine() {
    if (currentMachineName.isEmpty) return;
    flushLayer();
    stateMachines.add(StateMachineData(
      name: currentMachineName,
      layers: machineLayers,
      inputs: machineInputs,
      listeners: machineListeners,
    ));
    currentMachineName = '';
    machineInputs = [];
    machineLayers = [];
    machineListeners = [];
  }

  // M7 deformer state machine — mirrors Nim semantic.nim decodeSkeletonObjects.
  var deformerPending = false;
  var pendingId = '';
  var pendingParent = '';
  var pendingOrder = 0;
  var pendingKind = DeformerKind.warp;
  WarpLattice? pendingWarp;
  RotationDeformerData? pendingRotation;
  var geometryReady = false;
  var blendPending = false;
  var pendingBlendValueCount = 0;
  var pendingBlendAxes = <ParameterAxis>[];
  var pendingKeyforms = <Keyform>[];

  void flushPending() {
    if (!deformerPending) return;
    if (!geometryReady) {
      throw const FormatException(
          '.bnb deformer header has no following geometry record');
    }
    final DeformerData deformerData;
    if (pendingKind == DeformerKind.warp) {
      deformerData = WarpDeformer(
        id: pendingId,
        parent: pendingParent,
        order: pendingOrder,
        warp: pendingWarp!,
      );
    } else {
      deformerData = RotationDeformer(
        id: pendingId,
        parent: pendingParent,
        order: pendingOrder,
        rotation: pendingRotation!,
      );
    }
    final blend = blendPending && pendingBlendAxes.isNotEmpty
        ? KeyformBlend(
            axes: pendingBlendAxes,
            valueCount: pendingBlendValueCount,
            keyforms: pendingKeyforms,
          )
        : const KeyformBlend();
    deformers.add(DeformerRecord(deformer: deformerData, keyformBlend: blend));
    deformerPending = false;
    geometryReady = false;
    blendPending = false;
    pendingBlendAxes = [];
    pendingKeyforms = [];
  }

  final paramsByName = <String, ParameterAxis>{};

  for (final obj in decodeObjects) {
    switch (obj.typeKey) {
      case wire.bonyTypeKeySkeleton:
        flushSkin();
        flushPending();
        if (header != null)
          throw const FormatException('.bnb: multiple skeleton objects');
        header = SkeletonHeader(
          name: _bStr(obj, wire.bonyPropertyKeyName, strings, 'skeleton.name'),
          version: _bStr(
              obj, wire.bonyPropertyKeyVersion, strings, 'skeleton.version',
              def: '0.1.0'),
        );
      case wire.bonyTypeKeyBone:
        flushSkin();
        flushPending();
        bones.add(BoneData(
          name: _bStr(obj, wire.bonyPropertyKeyName, strings, 'bone.name'),
          parent: _bStr(obj, wire.bonyPropertyKeyParent, strings, 'bone.parent',
              def: ''),
          x: _bF32(obj, wire.bonyPropertyKeyX, 'bone.x', def: 0.0),
          y: _bF32(obj, wire.bonyPropertyKeyY, 'bone.y', def: 0.0),
          rotation: _bF32(obj, wire.bonyPropertyKeyRotation, 'bone.rotation',
              def: 0.0),
          scaleX:
              _bF32(obj, wire.bonyPropertyKeyScaleX, 'bone.scaleX', def: 1.0),
          scaleY:
              _bF32(obj, wire.bonyPropertyKeyScaleY, 'bone.scaleY', def: 1.0),
          shearX:
              _bF32(obj, wire.bonyPropertyKeyShearX, 'bone.shearX', def: 0.0),
          shearY:
              _bF32(obj, wire.bonyPropertyKeyShearY, 'bone.shearY', def: 0.0),
          inheritRotation:
              _bBool(obj, wire.bonyPropertyKeyInheritRotation, def: true),
          inheritScale:
              _bBool(obj, wire.bonyPropertyKeyInheritScale, def: true),
          inheritReflection:
              _bBool(obj, wire.bonyPropertyKeyInheritReflection, def: true),
          transformMode: _bStr(obj, wire.bonyPropertyKeyTransformMode, strings,
              'bone.transformMode',
              def: 'normal'),
          skinRequired: _bBool(obj, wire.bonyPropertyKeySkinRequired),
        ));
      case wire.bonyTypeKeySlot:
        flushSkin();
        flushPending();
        slots.add(SlotData(
          name: _bStr(obj, wire.bonyPropertyKeyName, strings, 'slot.name'),
          bone: _bStr(obj, wire.bonyPropertyKeyBone, strings, 'slot.bone'),
          attachment: _bStr(
              obj, wire.bonyPropertyKeyAttachment, strings, 'slot.attachment',
              def: ''),
        ));
      case wire.bonyTypeKeyRegion:
        flushSkin();
        flushPending();
        regions.add(RegionAttachment(
          name: _bStr(obj, wire.bonyPropertyKeyName, strings, 'region.name'),
          width: _bF32(obj, wire.bonyPropertyKeyWidth, 'region.width'),
          height: _bF32(obj, wire.bonyPropertyKeyHeight, 'region.height'),
          texturePage: _bStr(obj, wire.bonyPropertyKeyTexturePage, strings,
              'region.texturePage',
              def: ''),
          u0: _bF32(obj, wire.bonyPropertyKeyU0, 'region.u0', def: 0.0),
          v0: _bF32(obj, wire.bonyPropertyKeyV0, 'region.v0', def: 0.0),
          u1: _bF32(obj, wire.bonyPropertyKeyU1, 'region.u1', def: 1.0),
          v1: _bF32(obj, wire.bonyPropertyKeyV1, 'region.v1', def: 1.0),
          alphaMode: _bStr(
              obj, wire.bonyPropertyKeyAlphaMode, strings, 'region.alphaMode',
              def: 'straight'),
        ));
      case wire.bonyTypeKeyPointAttachment:
        flushSkin();
        flushPending();
        pointAttachments.add(PointAttachment(
          name: _bStr(
              obj, wire.bonyPropertyKeyName, strings, 'pointAttachment.name'),
          x: _bF32(obj, wire.bonyPropertyKeyX, 'pointAttachment.x'),
          y: _bF32(obj, wire.bonyPropertyKeyY, 'pointAttachment.y'),
          rotation: _bF32(
              obj, wire.bonyPropertyKeyRotation, 'pointAttachment.rotation'),
        ));
      case wire.bonyTypeKeyBoundingBoxAttachment:
        flushSkin();
        flushPending();
        boundingBoxAttachments.add(BoundingBoxAttachment(
          name: _bStr(obj, wire.bonyPropertyKeyName, strings,
              'boundingBoxAttachment.name'),
          vertices: _bPolygonVertices(obj, 'boundingBoxAttachment'),
        ));
      case wire.bonyTypeKeyClippingAttachment:
        flushSkin();
        flushPending();
        clips.add(ClippingAttachment(
          name: _bStr(obj, wire.bonyPropertyKeyName, strings,
              'clippingAttachment.name'),
          vertices: _bPolygonVertices(obj, 'clippingAttachment'),
          untilSlot: _bStr(obj, wire.bonyPropertyKeyUntilSlot, strings,
              'clippingAttachment.untilSlot',
              def: ''),
        ));
      case wire.bonyTypeKeyMeshAttachment:
        flushSkin();
        flushPending();
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
      case wire.bonyTypeKeyNestedRigAttachment:
        flushSkin();
        flushPending();
        nestedRigAttachments.add(NestedRigAttachment(
          name: _bStr(obj, wire.bonyPropertyKeyName, strings,
              'nestedRigAttachment.name'),
          skeleton: _bStr(obj, wire.bonyPropertyKeyNestedSkeleton, strings,
              'nestedRigAttachment.skeleton'),
          skin: _bStr(obj, wire.bonyPropertyKeyNestedSkin, strings,
              'nestedRigAttachment.skin',
              def: ''),
          animation: _bStr(obj, wire.bonyPropertyKeyNestedAnimation, strings,
              'nestedRigAttachment.animation',
              def: ''),
        ));
      case wire.bonyTypeKeySkin:
        flushPending();
        flushSkin();
        currentSkinName =
            _bStr(obj, wire.bonyPropertyKeyName, strings, 'skin.name');
        currentSkinBones = _bIndexList(
            obj, wire.bonyPropertyKeySkinBones, boneNames(), 'skin.bones');
        currentSkinIkConstraints = _bIndexList(
            obj,
            wire.bonyPropertyKeySkinIkConstraints,
            ikNames(),
            'skin.ikConstraints');
        currentSkinTransformConstraints = _bIndexList(
            obj,
            wire.bonyPropertyKeySkinTransformConstraints,
            transformNames(),
            'skin.transformConstraints');
        currentSkinPathConstraints = _bIndexList(
            obj,
            wire.bonyPropertyKeySkinPathConstraints,
            pathNames(),
            'skin.pathConstraints');
        currentSkinPhysicsConstraints = _bIndexList(
            obj,
            wire.bonyPropertyKeySkinPhysicsConstraints,
            physicsNames(),
            'skin.physicsConstraints');
      case wire.bonyTypeKeySkinEntry:
        flushPending();
        if (currentSkinName.isEmpty) {
          throw const FormatException(
              '.bnb skinEntry record without preceding skin');
        }
        currentSkinEntries.add(SkinEntryData(
          slot: _bStr(obj, wire.bonyPropertyKeySlot, strings, 'skinEntry.slot'),
          attachment: _bStr(obj, wire.bonyPropertyKeySkinAttachment, strings,
              'skinEntry.attachment'),
          target: _bStr(
              obj, wire.bonyPropertyKeySkinTarget, strings, 'skinEntry.target'),
        ));
      case wire.bonyTypeKeyPath:
        flushSkin();
        flushPending();
        paths.add(PathConstraintData(
          name: _bStr(obj, wire.bonyPropertyKeyName, strings, 'path.name'),
          bone: _bStr(obj, wire.bonyPropertyKeyBone, strings, 'path.bone'),
          target:
              _bStr(obj, wire.bonyPropertyKeyTarget, strings, 'path.target'),
          path: _bStr(obj, wire.bonyPropertyKeyPath, strings, 'path.path'),
          order: _bVarint(obj, wire.bonyPropertyKeyOrder, def: 0),
          skinRequired: _bBool(obj, wire.bonyPropertyKeySkinRequired),
          position: obj.props.containsKey(wire.bonyPropertyKeyPosition)
              ? _bF32(obj, wire.bonyPropertyKeyPosition, 'path.position')
              : null,
          translateMix: obj.props.containsKey(wire.bonyPropertyKeyTranslateMix)
              ? _bF32(
                  obj, wire.bonyPropertyKeyTranslateMix, 'path.translateMix')
              : null,
          rotateMix: obj.props.containsKey(wire.bonyPropertyKeyRotateMix)
              ? _bF32(obj, wire.bonyPropertyKeyRotateMix, 'path.rotateMix')
              : null,
        ));
      case wire.bonyTypeKeyIkConstraint:
        flushSkin();
        flushPending();
        ikConstraints.add(IkConstraintData(
          name: _bStr(
              obj, wire.bonyPropertyKeyName, strings, 'ikConstraint.name'),
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
      case wire.bonyTypeKeyTransformConstraint:
        flushSkin();
        flushPending();
        transformConstraints.add(TransformConstraintData(
          name: _bStr(obj, wire.bonyPropertyKeyName, strings,
              'transformConstraint.name'),
          bone: _bStr(obj, wire.bonyPropertyKeyBone, strings,
              'transformConstraint.bone'),
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
      case wire.bonyTypeKeyPhysicsConstraint:
        flushSkin();
        flushPending();
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
              ? _bF32(obj, wire.bonyPropertyKeyStrength,
                  'physicsConstraint.strength')
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
      case wire.bonyTypeKeyPathAttachment:
        flushSkin();
        flushPending();
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
      case wire.bonyTypeKeyParameter:
        flushSkin();
        flushPending();
        final name =
            _bStr(obj, wire.bonyPropertyKeyName, strings, 'parameter.name');
        final min =
            _bF32(obj, wire.bonyPropertyKeyParameterMin, 'parameter.min');
        final max =
            _bF32(obj, wire.bonyPropertyKeyParameterMax, 'parameter.max');
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
      case wire.bonyTypeKeyDeformer:
        flushSkin();
        flushPending();
        pendingId =
            _bStr(obj, wire.bonyPropertyKeyDeformerId, strings, 'deformer.id');
        pendingParent = _bStr(
            obj, wire.bonyPropertyKeyParent, strings, 'deformer.parent',
            def: '');
        pendingOrder =
            _bVaruint(obj, wire.bonyPropertyKeyDeformerOrder, def: 0);
        final kindStr = _bStr(
            obj, wire.bonyPropertyKeyDeformerKind, strings, 'deformer.kind');
        if (kindStr == 'warp') {
          pendingKind = DeformerKind.warp;
        } else if (kindStr == 'rotation') {
          pendingKind = DeformerKind.rotation;
        } else {
          throw FormatException(
              '.bnb deformer.kind must be warp or rotation: $kindStr');
        }
        deformerPending = true;
        geometryReady = false;
        blendPending = false;
        pendingBlendAxes = [];
        pendingKeyforms = [];
      case wire.bonyTypeKeyWarpLattice:
        if (!deformerPending || pendingKind != DeformerKind.warp) {
          throw const FormatException(
              '.bnb warpLattice without preceding warp deformer');
        }
        pendingWarp = WarpLattice(
          rows: _bVaruint(obj, wire.bonyPropertyKeyWarpRows, def: 2),
          cols: _bVaruint(obj, wire.bonyPropertyKeyWarpCols, def: 2),
          minX: _bF32(obj, wire.bonyPropertyKeyWarpMinX, 'warpLattice.minX'),
          minY: _bF32(obj, wire.bonyPropertyKeyWarpMinY, 'warpLattice.minY'),
          maxX: _bF32(obj, wire.bonyPropertyKeyWarpMaxX, 'warpLattice.maxX'),
          maxY: _bF32(obj, wire.bonyPropertyKeyWarpMaxY, 'warpLattice.maxY'),
          controlPoints: _bControlPoints(obj, strings),
        );
        geometryReady = true;
      case wire.bonyTypeKeyRotationDeformer:
        if (!deformerPending || pendingKind != DeformerKind.rotation) {
          throw const FormatException(
              '.bnb rotationDeformer without preceding rotation deformer');
        }
        pendingRotation = RotationDeformerData(
          pivotX: _bF32(obj, wire.bonyPropertyKeyRotationPivotX,
              'rotationDeformer.pivotX'),
          pivotY: _bF32(obj, wire.bonyPropertyKeyRotationPivotY,
              'rotationDeformer.pivotY'),
          angleDegrees: _bF32(obj, wire.bonyPropertyKeyRotationAngleDegrees,
              'rotationDeformer.angleDegrees'),
          scaleX: _bF32(obj, wire.bonyPropertyKeyRotationScaleX,
              'rotationDeformer.scaleX',
              def: 1.0),
          scaleY: _bF32(obj, wire.bonyPropertyKeyRotationScaleY,
              'rotationDeformer.scaleY',
              def: 1.0),
          opacity: _bF32(obj, wire.bonyPropertyKeyRotationOpacity,
              'rotationDeformer.opacity',
              def: 1.0),
        );
        geometryReady = true;
      case wire.bonyTypeKeyKeyformBlend:
        if (!deformerPending || !geometryReady) {
          throw const FormatException(
              '.bnb keyformBlend without preceding deformer geometry');
        }
        pendingBlendValueCount =
            _bVaruint(obj, wire.bonyPropertyKeyBlendValueCount, def: 0);
        pendingBlendAxes = _bBlendAxes(obj, strings, paramsByName);
        pendingKeyforms = [];
        blendPending = true;
      case wire.bonyTypeKeyKeyform:
        if (!blendPending) {
          throw const FormatException(
              '.bnb keyform without preceding keyformBlend');
        }
        final coordVals = _bF32Array(obj, wire.bonyPropertyKeyBlendCoordinates,
            pendingBlendAxes.length, 'keyform.coordinates');
        final values = _bF32Array(obj, wire.bonyPropertyKeyBlendValues,
            pendingBlendValueCount, 'keyform.values');
        final coordinates = [
          for (var i = 0; i < pendingBlendAxes.length; i++)
            ParameterSample(
                name: pendingBlendAxes[i].name, value: coordVals[i]),
        ];
        pendingKeyforms.add(Keyform(coordinates: coordinates, values: values));
      case wire.bonyTypeKeyAnimationClip:
        flushSkin();
        flushPending();
        flushAnimation();
        currentAnimationName =
            _bStr(obj, wire.bonyPropertyKeyName, strings, 'animationClip.name');
      case wire.bonyTypeKeyBoneTimeline:
        flushSkin();
        flushPending();
        if (currentAnimationName.isEmpty)
          throw const FormatException(
              '.bnb boneTimeline without animationClip');
        final boneIndex = _bVaruint(obj, wire.bonyPropertyKeyBoneIndex);
        if (boneIndex < 0 || boneIndex >= bones.length) {
          throw const FormatException(
              '.bnb boneTimeline.boneIndex is out of range');
        }
        final payload = obj.props[wire.bonyPropertyKeyTimelineKeys];
        if (payload == null)
          throw const FormatException(
              '.bnb boneTimeline.timelineKeys is required');
        currentBoneTimelines.add(_bBoneTimelineKeys(
          bones[boneIndex].name,
          _bBoneTimelineKind(_bRequiredVaruint(
              obj, wire.bonyPropertyKeyBoneTimelineKind, 'boneTimeline.kind')),
          payload,
          'boneTimeline.timelineKeys',
        ));
      case wire.bonyTypeKeySlotTimeline:
        flushSkin();
        flushPending();
        if (currentAnimationName.isEmpty)
          throw const FormatException(
              '.bnb slotTimeline without animationClip');
        final slotIndex = _bVaruint(obj, wire.bonyPropertyKeySlotIndex);
        if (slotIndex < 0 || slotIndex >= slots.length) {
          throw const FormatException(
              '.bnb slotTimeline.slotIndex is out of range');
        }
        final payload = obj.props[wire.bonyPropertyKeyTimelineKeys];
        if (payload == null)
          throw const FormatException(
              '.bnb slotTimeline.timelineKeys is required');
        currentSlotTimelines.add(_bSlotTimelineKeys(
          slots[slotIndex].name,
          _bSlotTimelineKind(_bRequiredVaruint(
              obj, wire.bonyPropertyKeySlotTimelineKind, 'slotTimeline.kind')),
          payload,
          regions,
          'slotTimeline.timelineKeys',
        ));
      case wire.bonyTypeKeyEventTimeline:
        flushSkin();
        flushPending();
        if (currentAnimationName.isEmpty)
          throw const FormatException(
              '.bnb eventTimeline without animationClip');
        final payload = obj.props[wire.bonyPropertyKeyEventKeys];
        if (payload == null)
          throw const FormatException(
              '.bnb eventTimeline.eventKeys is required');
        currentEventTimelines.add(EventTimeline(
          keys:
              _bEventTimelineKeys(payload, strings, 'eventTimeline.eventKeys'),
        ));
      case wire.bonyTypeKeyDeformTimeline:
        flushSkin();
        // Relies on meshAttachment objects being decoded before deform-timeline
        // objects: the encoder emits meshes (type 3001) before animation clips,
        // and the SM-only reordering above never moves a mesh after a clip, so
        // `meshes` is fully populated for the vertexCount lookup below.
        flushPending();
        if (currentAnimationName.isEmpty)
          throw const FormatException(
              '.bnb deformTimeline without animationClip');
        final skin = _bStr(obj, wire.bonyPropertyKeyDeformSkin, strings,
            'deformTimeline.skin');
        final resolutionData = skinResolutionData();
        if (!resolutionData.hasSkin(skin)) {
          throw FormatException(
              '.bnb deformTimeline references unknown skin: $skin');
        }
        final slot = _bStr(
            obj, wire.bonyPropertyKeySlot, strings, 'deformTimeline.slot');
        final attachment = _bStr(obj, wire.bonyPropertyKeyDeformAttachment,
            strings, 'deformTimeline.attachment');
        final resolvedAttachment =
            resolutionData.resolveSkinAttachmentTarget(skin, slot, attachment);
        if (resolvedAttachment.isEmpty) {
          throw FormatException(
              '.bnb deformTimeline does not resolve through skin lookup: '
              '$skin/$slot/$attachment');
        }
        final vertexCount = _bRequiredVaruint(
            obj,
            wire.bonyPropertyKeyDeformVertexCount,
            'deformTimeline.vertexCount');
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
        currentDeformTimelines.add(DeformTimeline(
          skin: skin,
          slot: slot,
          attachment: attachment,
          vertexCount: vertexCount,
          keys: _bDeformTimelineKeys(
              payload, vertexCount, 'deformTimeline.deformKeys'),
        ));
      case wire.bonyTypeKeyStateMachine:
        flushSkin();
        flushPending();
        flushAnimation();
        flushMachine();
        currentMachineName =
            _bStr(obj, wire.bonyPropertyKeyName, strings, 'stateMachine.name');
      case wire.bonyTypeKeyStateMachineInput:
        flushSkin();
        flushPending();
        flushLayer();
        if (currentMachineName.isEmpty)
          throw const FormatException(
              '.bnb stateMachineInput without stateMachine');
        final kindTag = _bRequiredVaruint(
            obj,
            wire.bonyPropertyKeyStateMachineInputKind,
            'stateMachineInput.kind');
        final name = _bStr(
            obj, wire.bonyPropertyKeyName, strings, 'stateMachineInput.name');
        switch (kindTag) {
          case 0:
            if (obj.props.containsKey(wire.bonyPropertyKeyInputDefaultNumber)) {
              throw const FormatException(
                  '.bnb bool input must not contain number default');
            }
            machineInputs.add(StateMachineInput(
              name: name,
              kind: StateMachineInputKind.bool_,
              defaultBool: _bBool(obj, wire.bonyPropertyKeyInputDefaultBool),
            ));
          case 1:
            if (obj.props.containsKey(wire.bonyPropertyKeyInputDefaultBool)) {
              throw const FormatException(
                  '.bnb number input must not contain bool default');
            }
            machineInputs.add(StateMachineInput(
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
            machineInputs.add(StateMachineInput(
                name: name, kind: StateMachineInputKind.trigger));
          default:
            throw FormatException(
                '.bnb stateMachineInput.kind is invalid: $kindTag');
        }
      case wire.bonyTypeKeyStateMachineLayer:
        flushSkin();
        flushPending();
        flushLayer();
        if (currentMachineName.isEmpty)
          throw const FormatException(
              '.bnb stateMachineLayer without stateMachine');
        currentLayerName = _bStr(
            obj, wire.bonyPropertyKeyName, strings, 'stateMachineLayer.name');
        currentLayerInitialIndex =
            _bVaruint(obj, wire.bonyPropertyKeyInitialStateIndex);
      case wire.bonyTypeKeyStateMachineState:
        flushSkin();
        flushPending();
        flushTransition();
        if (currentLayerName.isEmpty)
          throw const FormatException('.bnb stateMachineState without layer');
        final stateName = _bStr(
            obj, wire.bonyPropertyKeyName, strings, 'stateMachineState.name');
        final kindTag = _bRequiredVaruint(
            obj,
            wire.bonyPropertyKeyStateMachineStateKind,
            'stateMachineState.kind');
        switch (kindTag) {
          case 0:
            if (obj.props
                .containsKey(wire.bonyPropertyKeyStateBlendInputIndex)) {
              throw const FormatException(
                  '.bnb clip state must not contain blend input');
            }
            final clipIndex = _bRequiredVaruint(obj,
                wire.bonyPropertyKeyStateClipIndex, 'stateMachineState.clip');
            if (clipIndex < 0 || clipIndex >= animations.length) {
              throw const FormatException(
                  '.bnb stateMachineState.clip index is out of range');
            }
            currentLayerStates.add(StateMachineState(
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
            if (inputIndex < 0 || inputIndex >= machineInputs.length) {
              throw const FormatException(
                  '.bnb stateMachineState.blendInput index is out of range');
            }
            currentLayerStates.add(StateMachineState(
              name: stateName,
              kind: StateMachineStateKind.blend1d,
              blendInput: machineInputs[inputIndex].name,
              blendClips: <StateMachineBlendClip>[],
            ));
          default:
            throw FormatException(
                '.bnb stateMachineState.kind is invalid: $kindTag');
        }
      case wire.bonyTypeKeyStateMachineBlendClip:
        flushSkin();
        flushPending();
        if (currentLayerStates.isEmpty ||
            currentLayerStates.last.kind != StateMachineStateKind.blend1d) {
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
        final previous = currentLayerStates.removeLast();
        currentLayerStates.add(StateMachineState(
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
      case wire.bonyTypeKeyStateMachineTransition:
        flushSkin();
        flushPending();
        flushTransition();
        if (currentLayerName.isEmpty)
          throw const FormatException(
              '.bnb stateMachineTransition without layer');
        pendingTransitionFrom = stateNameAt(
            currentLayerStates,
            _bRequiredVaruint(obj, wire.bonyPropertyKeyTransitionFromStateIndex,
                'stateMachineTransition.from'),
            'stateMachineTransition.from');
        pendingTransitionTo = stateNameAt(
            currentLayerStates,
            _bRequiredVaruint(obj, wire.bonyPropertyKeyTransitionToStateIndex,
                'stateMachineTransition.to'),
            'stateMachineTransition.to');
      case wire.bonyTypeKeyStateMachineCondition:
        flushSkin();
        flushPending();
        if (pendingTransitionFrom.isEmpty)
          throw const FormatException(
              '.bnb stateMachineCondition without transition');
        final inputIndex = _bRequiredVaruint(
            obj,
            wire.bonyPropertyKeyConditionInputIndex,
            'stateMachineCondition.input');
        if (inputIndex < 0 || inputIndex >= machineInputs.length) {
          throw const FormatException(
              '.bnb stateMachineCondition.input index is out of range');
        }
        final input = machineInputs[inputIndex];
        final kindTag = _bRequiredVaruint(
            obj,
            wire.bonyPropertyKeyStateMachineConditionKind,
            'stateMachineCondition.kind');
        switch (kindTag) {
          case 0:
            if (obj.props
                .containsKey(wire.bonyPropertyKeyConditionNumberValue)) {
              throw const FormatException(
                  '.bnb bool condition must not contain number value');
            }
            pendingConditions.add(StateMachineCondition(
              input: input.name,
              kind: StateMachineConditionKind.boolEquals,
              boolValue: _bBool(obj, wire.bonyPropertyKeyConditionBoolValue,
                  def: true),
            ));
          case 1:
            if (obj.props.containsKey(wire.bonyPropertyKeyConditionBoolValue)) {
              throw const FormatException(
                  '.bnb number condition must not contain bool value');
            }
            pendingConditions.add(StateMachineCondition(
                input: input.name,
                kind: StateMachineConditionKind.numberEquals,
                numberValue: _bF32(
                    obj,
                    wire.bonyPropertyKeyConditionNumberValue,
                    'condition.number')));
          case 2:
            if (obj.props.containsKey(wire.bonyPropertyKeyConditionBoolValue)) {
              throw const FormatException(
                  '.bnb number condition must not contain bool value');
            }
            pendingConditions.add(StateMachineCondition(
                input: input.name,
                kind: StateMachineConditionKind.numberGreater,
                numberValue: _bF32(
                    obj,
                    wire.bonyPropertyKeyConditionNumberValue,
                    'condition.number')));
          case 3:
            if (obj.props.containsKey(wire.bonyPropertyKeyConditionBoolValue)) {
              throw const FormatException(
                  '.bnb number condition must not contain bool value');
            }
            pendingConditions.add(StateMachineCondition(
                input: input.name,
                kind: StateMachineConditionKind.numberGreaterOrEqual,
                numberValue: _bF32(
                    obj,
                    wire.bonyPropertyKeyConditionNumberValue,
                    'condition.number')));
          case 4:
            if (obj.props.containsKey(wire.bonyPropertyKeyConditionBoolValue)) {
              throw const FormatException(
                  '.bnb number condition must not contain bool value');
            }
            pendingConditions.add(StateMachineCondition(
                input: input.name,
                kind: StateMachineConditionKind.numberLess,
                numberValue: _bF32(
                    obj,
                    wire.bonyPropertyKeyConditionNumberValue,
                    'condition.number')));
          case 5:
            if (obj.props.containsKey(wire.bonyPropertyKeyConditionBoolValue)) {
              throw const FormatException(
                  '.bnb number condition must not contain bool value');
            }
            pendingConditions.add(StateMachineCondition(
                input: input.name,
                kind: StateMachineConditionKind.numberLessOrEqual,
                numberValue: _bF32(
                    obj,
                    wire.bonyPropertyKeyConditionNumberValue,
                    'condition.number')));
          case 6:
            if (obj.props.containsKey(wire.bonyPropertyKeyConditionBoolValue) ||
                obj.props
                    .containsKey(wire.bonyPropertyKeyConditionNumberValue)) {
              throw const FormatException(
                  '.bnb trigger condition must not contain values');
            }
            pendingConditions.add(StateMachineCondition(
                input: input.name, kind: StateMachineConditionKind.triggerSet));
          default:
            throw FormatException(
                '.bnb stateMachineCondition.kind is invalid: $kindTag');
        }
      case wire.bonyTypeKeyStateMachineListener:
        flushSkin();
        flushPending();
        flushLayer();
        if (currentMachineName.isEmpty)
          throw const FormatException(
              '.bnb stateMachineListener without stateMachine');
        final listenerName = _bStr(obj, wire.bonyPropertyKeyName, strings,
            'stateMachineListener.name');
        final kindTag = _bRequiredVaruint(
            obj,
            wire.bonyPropertyKeyStateMachineListenerKind,
            'stateMachineListener.kind');
        StateMachineLayer listenerLayer() {
          final layerIndex = _bRequiredVaruint(
              obj,
              wire.bonyPropertyKeyListenerLayerIndex,
              'stateMachineListener.layer');
          if (layerIndex < 0 || layerIndex >= machineLayers.length) {
            throw const FormatException(
                '.bnb stateMachineListener.layer index is out of range');
          }
          return machineLayers[layerIndex];
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
            machineListeners.add(StateMachineListener(
              name: listenerName,
              kind: StateMachineListenerKind.stateEnter,
              layer: layer.name,
              toState: stateNameAt(
                  layer.states,
                  _bRequiredVaruint(
                      obj,
                      wire.bonyPropertyKeyListenerToStateIndex,
                      'stateMachineListener.to'),
                  'stateMachineListener.to'),
            ));
          case 1:
            final layer = listenerLayer();
            if (hasPointerFields()) {
              throw const FormatException(
                  '.bnb lifecycle listener must not contain pointer fields');
            }
            if (obj.props
                .containsKey(wire.bonyPropertyKeyListenerToStateIndex)) {
              throw const FormatException(
                  '.bnb exit listener must not contain to state');
            }
            machineListeners.add(StateMachineListener(
              name: listenerName,
              kind: StateMachineListenerKind.stateExit,
              layer: layer.name,
              fromState: stateNameAt(
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
            machineListeners.add(StateMachineListener(
              name: listenerName,
              kind: StateMachineListenerKind.transition_,
              layer: layer.name,
              fromState: stateNameAt(
                  layer.states,
                  _bRequiredVaruint(
                      obj,
                      wire.bonyPropertyKeyListenerFromStateIndex,
                      'stateMachineListener.from'),
                  'stateMachineListener.from'),
              toState: stateNameAt(
                  layer.states,
                  _bRequiredVaruint(
                      obj,
                      wire.bonyPropertyKeyListenerToStateIndex,
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
                obj.props
                    .containsKey(wire.bonyPropertyKeyListenerToStateIndex)) {
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
            if (inputIndex < 0 || inputIndex >= machineInputs.length) {
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
            final input = machineInputs[inputIndex];
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
                numberValue = _bF32(
                    obj,
                    wire.bonyPropertyKeyListenerNumberValue,
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
            machineListeners.add(StateMachineListener(
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
    }
  }
  flushSkin();
  flushPending();
  flushAnimation();
  flushMachine();

  if (header == null)
    throw const FormatException('.bnb: missing skeleton object');
  return SkeletonData(
    header: header,
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
