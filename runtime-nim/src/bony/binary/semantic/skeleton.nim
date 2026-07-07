type PendingDeformerState = enum
  pdNone
  pdAwaitingGeometry
  pdAwaitingBlend


type PendingDeformer = object
  state: PendingDeformerState
  id: string
  parent: string
  order: uint32
  deformerKind: DeformerKind
  warp: WarpLattice
  rotation: RotationDeformer
  hasBlend: bool
  blendValueCount: int
  blendAxes: seq[ParameterAxis]
  keyforms: seq[Keyform]


proc clear(pending: var PendingDeformer) =
  pending = PendingDeformer()


proc start(
  pending: var PendingDeformer;
  id, parent: string;
  order: uint32;
  deformerKind: DeformerKind;
) =
  pending.clear()
  pending.state = pdAwaitingGeometry
  pending.id = id
  pending.parent = parent
  pending.order = order
  pending.deformerKind = deformerKind


proc requirePendingKind(pending: PendingDeformer; deformerKind: DeformerKind; message: string) =
  if pending.state != pdAwaitingGeometry or pending.deformerKind != deformerKind:
    raise newBonyLoadError(schemaViolation, message)


proc setWarp(pending: var PendingDeformer; warp: WarpLattice) =
  pending.requirePendingKind(warpDeformerKind, ".bnb warpLattice record without preceding warp deformer")
  pending.warp = warp
  pending.state = pdAwaitingBlend


proc setRotation(pending: var PendingDeformer; rotation: RotationDeformer) =
  pending.requirePendingKind(rotationDeformerKind, ".bnb rotationDeformer record without preceding rotation deformer")
  pending.rotation = rotation
  pending.state = pdAwaitingBlend


proc startBlend(pending: var PendingDeformer; axes: seq[ParameterAxis]; valueCount: int) =
  if pending.state != pdAwaitingBlend:
    raise newBonyLoadError(schemaViolation, ".bnb keyformBlend record without preceding deformer geometry")
  pending.blendAxes = axes
  pending.blendValueCount = valueCount
  pending.keyforms = @[]
  pending.hasBlend = true


proc addKeyform(pending: var PendingDeformer; keyform: Keyform) =
  if not pending.hasBlend:
    raise newBonyLoadError(schemaViolation, ".bnb keyform record without preceding keyformBlend")
  pending.keyforms.add keyform


proc emitPendingDeformer(
  loadedDeformers: var seq[DeformerRecord];
  pending: PendingDeformer;
) =
  var deformerObj: Deformer
  case pending.deformerKind
  of warpDeformerKind:
    deformerObj = Deformer(id: pending.id, parent: pending.parent, order: pending.order, kind: warpDeformerKind, warp: pending.warp)
    validateWarpLattice(pending.warp)
  of rotationDeformerKind:
    deformerObj = Deformer(id: pending.id, parent: pending.parent, order: pending.order, kind: rotationDeformerKind, rotation: pending.rotation)
    validateRotationDeformer(pending.rotation)
  if pending.hasBlend:
    let blend = keyformBlend(pending.blendAxes, pending.keyforms)
    loadedDeformers.add DeformerRecord(deformer: deformerObj, keyformBlend: blend)
  else:
    loadedDeformers.add DeformerRecord(deformer: deformerObj, keyformBlend: KeyformBlend())


proc decodeSkeletonObjects(objects: openArray[BnbObjectRecord]; strings: BnbStringTable): SkeletonData =
  var hasSkeleton = false
  var headerValue: SkeletonHeader
  var bones: seq[BoneData]
  var slots: seq[SlotData]
  var regions: seq[RegionAttachment]
  var pointAttachments: seq[PointAttachmentData]
  var boundingBoxAttachments: seq[BoundingBoxAttachmentData]
  var nestedRigAttachments: seq[NestedRigAttachmentData]
  var pathAttachments: seq[PathAttachmentData]
  var clips: seq[ClipAttachmentData]
  var meshes: seq[MeshAttachment]
  var paths: seq[PathConstraintData]
  var ikConstraints: seq[IkConstraintData]
  var transformConstraints: seq[TransformConstraintData]
  var physicsConstraints: seq[PhysicsConstraintData]
  var skins: seq[SkinData]
  var loadedParameters: seq[ParameterAxis]
  var loadedDeformers: seq[DeformerRecord]

  var pendingDeformer: PendingDeformer
  var currentSkinName = ""
  var currentSkinEntries: seq[SkinEntryData] = @[]
  var currentSkinBones: seq[string] = @[]
  var currentSkinIkConstraints: seq[string] = @[]
  var currentSkinTransformConstraints: seq[string] = @[]
  var currentSkinPathConstraints: seq[string] = @[]
  var currentSkinPhysicsConstraints: seq[string] = @[]

  template flushPendingIfAny() =
    case pendingDeformer.state
    of pdNone:
      discard
    of pdAwaitingGeometry:
      raise newBonyLoadError(schemaViolation, ".bnb deformer header has no following geometry record")
    of pdAwaitingBlend:
      emitPendingDeformer(loadedDeformers, pendingDeformer)
      pendingDeformer.clear()

  template flushSkinIfAny() =
    if currentSkinName.len > 0:
      skins.add skinData(
        currentSkinName,
        currentSkinEntries,
        bones = currentSkinBones,
        ikConstraints = currentSkinIkConstraints,
        transformConstraints = currentSkinTransformConstraints,
        pathConstraints = currentSkinPathConstraints,
        physicsConstraints = currentSkinPhysicsConstraints,
      )
      currentSkinName = ""
      currentSkinEntries = @[]
      currentSkinBones = @[]
      currentSkinIkConstraints = @[]
      currentSkinTransformConstraints = @[]
      currentSkinPathConstraints = @[]
      currentSkinPhysicsConstraints = @[]

  proc boneNames(): seq[string] =
    for bone in bones:
      result.add bone.name

  proc ikNames(): seq[string] =
    for ik in ikConstraints:
      result.add ik.name

  proc transformNames(): seq[string] =
    for tc in transformConstraints:
      result.add tc.name

  proc pathNames(): seq[string] =
    for path in paths:
      result.add path.name

  proc physicsNames(): seq[string] =
    for pc in physicsConstraints:
      result.add pc.name

  for record in objects:
    case record.typeKey
    of skeletonTypeKey:
      if hasSkeleton:
        raise newBonyLoadError(duplicateKey, ".bnb contains multiple skeleton objects")
      let properties = record.propertyMap([nameKey, versionKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeSkeletonBnbScalars, properties, bonySkeletonScalarSpecs, strings, "skeleton")
      headerValue = skeletonHeader(
        scalars.bnbScalarString(nameKey, "skeleton.name"),
        scalars.bnbScalarString(versionKey, "skeleton.version"),
      )
      hasSkeleton = true
    of boneTypeKey:
      let properties = record.propertyMap([
        nameKey,
        parentKey,
        xKey,
        yKey,
        rotationKey,
        scaleXKey,
        scaleYKey,
        shearXKey,
        shearYKey,
        inheritRotationKey,
        inheritScaleKey,
        inheritReflectionKey,
        transformModeKey,
        skinRequiredKey,
      ])
      let scalars = decodeBnbScalarsFromProperties(
        decodeBoneBnbScalars, properties, bonyBoneScalarSpecs, strings, "bone")
      let inheritRotation = scalars.bnbScalarBool(inheritRotationKey, "bone.inheritRotation")
      let inheritScale = scalars.bnbScalarBool(inheritScaleKey, "bone.inheritScale")
      let inheritReflection = scalars.bnbScalarBool(inheritReflectionKey, "bone.inheritReflection")
      bones.add boneData(
        scalars.bnbScalarString(nameKey, "bone.name"),
        scalars.bnbScalarString(parentKey, "bone.parent"),
        localTransform(
          x = scalars.bnbScalarFloat(xKey, "bone.x"),
          y = scalars.bnbScalarFloat(yKey, "bone.y"),
          rotation = scalars.bnbScalarFloat(rotationKey, "bone.rotation"),
          scaleX = scalars.bnbScalarFloat(scaleXKey, "bone.scaleX"),
          scaleY = scalars.bnbScalarFloat(scaleYKey, "bone.scaleY"),
          shearX = scalars.bnbScalarFloat(shearXKey, "bone.shearX"),
          shearY = scalars.bnbScalarFloat(shearYKey, "bone.shearY"),
          inheritRotation = inheritRotation,
          inheritScale = inheritScale,
          inheritReflection = inheritReflection,
          transformMode = parseTransformMode(scalars.bnbScalarString(transformModeKey, "bone.transformMode")),
        ),
        skinRequired = scalars.bnbScalarBool(skinRequiredKey, "bone.skinRequired"),
      )
    of slotTypeKey:
      let properties = record.propertyMap([nameKey, boneKey, attachmentKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeSlotBnbScalars, properties, bonySlotScalarSpecs, strings, "slot")
      slots.add slotData(
        scalars.bnbScalarString(nameKey, "slot.name"),
        scalars.bnbScalarString(boneKey, "slot.bone"),
        scalars.bnbScalarString(attachmentKey, "slot.attachment"),
      )
    of regionTypeKey:
      let properties = record.propertyMap([nameKey, widthKey, heightKey, texturePageKey, u0Key, v0Key, u1Key, v1Key, alphaModeKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeRegionBnbScalars, properties, bonyRegionScalarSpecs, strings, "region")
      regions.add regionAttachment(
        scalars.bnbScalarString(nameKey, "region.name"),
        scalars.bnbScalarFloat(widthKey, "region.width"),
        scalars.bnbScalarFloat(heightKey, "region.height"),
        texturePage = scalars.bnbScalarString(texturePageKey, "region.texturePage"),
        u0 = scalars.bnbScalarFloat(u0Key, "region.u0"),
        v0 = scalars.bnbScalarFloat(v0Key, "region.v0"),
        u1 = scalars.bnbScalarFloat(u1Key, "region.u1"),
        v1 = scalars.bnbScalarFloat(v1Key, "region.v1"),
        alphaMode = scalars.bnbScalarString(alphaModeKey, "region.alphaMode"),
      )
    of pointAttachmentTypeKey:
      let properties = record.propertyMap([nameKey, xKey, yKey, rotationKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodePointAttachmentBnbScalars, properties, bonyPointAttachmentScalarSpecs, strings, "pointAttachment")
      pointAttachments.add pointAttachmentData(
        scalars.bnbScalarString(nameKey, "pointAttachment.name"),
        scalars.bnbScalarFloat(xKey, "pointAttachment.x"),
        scalars.bnbScalarFloat(yKey, "pointAttachment.y"),
        scalars.bnbScalarFloat(rotationKey, "pointAttachment.rotation"),
      )
    of boundingBoxAttachmentTypeKey:
      let properties = record.propertyMap([nameKey, verticesKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeBoundingBoxAttachmentBnbScalars, properties, bonyBoundingBoxAttachmentScalarSpecs, strings, "boundingBoxAttachment")
      if verticesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb boundingBoxAttachment.vertices is required")
      boundingBoxAttachments.add boundingBoxAttachmentData(
        scalars.bnbScalarString(nameKey, "boundingBoxAttachment.name"),
        readPolygonVerticesPayload(properties[verticesKey], "boundingBoxAttachment"),
      )
    of pathAttachmentTypeKey:
      let properties = record.propertyMap([nameKey, p0xKey, p0yKey, p1xKey, p1yKey, p2xKey, p2yKey, p3xKey, p3yKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodePathAttachmentBnbScalars, properties, bonyPathAttachmentScalarSpecs, strings, "pathAttachment")
      pathAttachments.add pathAttachmentData(
        scalars.bnbScalarString(nameKey, "pathAttachment.name"),
        scalars.bnbScalarFloat(p0xKey, "pathAttachment.p0x"),
        scalars.bnbScalarFloat(p0yKey, "pathAttachment.p0y"),
        scalars.bnbScalarFloat(p1xKey, "pathAttachment.p1x"),
        scalars.bnbScalarFloat(p1yKey, "pathAttachment.p1y"),
        scalars.bnbScalarFloat(p2xKey, "pathAttachment.p2x"),
        scalars.bnbScalarFloat(p2yKey, "pathAttachment.p2y"),
        scalars.bnbScalarFloat(p3xKey, "pathAttachment.p3x"),
        scalars.bnbScalarFloat(p3yKey, "pathAttachment.p3y"),
      )
    of clippingAttachmentTypeKey:
      let properties = record.propertyMap([nameKey, verticesKey, untilSlotKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeClippingAttachmentBnbScalars, properties, bonyClippingAttachmentScalarSpecs, strings, "clippingAttachment")
      if verticesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb clippingAttachment.vertices is required")
      clips.add clipAttachmentData(
        scalars.bnbScalarString(nameKey, "clippingAttachment.name"),
        readPolygonVerticesPayload(properties[verticesKey], "clippingAttachment"),
        scalars.bnbScalarString(untilSlotKey, "clippingAttachment.untilSlot"),
      )
    of meshAttachmentTypeKey:
      let properties = record.propertyMap([nameKey, meshWeightedKey, meshVerticesKey, meshUvsKey, meshTrianglesKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeMeshAttachmentBnbScalars, properties, bonyMeshAttachmentScalarSpecs, strings, "meshAttachment")
      if meshVerticesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb meshAttachment.meshVertices is required")
      if meshUvsKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb meshAttachment.meshUvs is required")
      if meshTrianglesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb meshAttachment.meshTriangles is required")
      # meshWeighted selects the vertices payload branch; it defaults to false and
      # is only present when non-default. The (a)-(g) whole-skeleton checks run
      # later in validateSkeletonData via skeletonData().
      let weighted = scalars.bnbScalarBool(meshWeightedKey, "meshAttachment.meshWeighted")
      meshes.add meshAttachmentData(
        scalars.bnbScalarString(nameKey, "meshAttachment.name"),
        readMeshUvsPayload(properties[meshUvsKey]),
        readMeshTrianglesPayload(properties[meshTrianglesKey]),
        readMeshVerticesPayload(properties[meshVerticesKey], weighted, strings),
        weighted,
      )
    of nestedRigAttachmentTypeKey:
      let properties = record.propertyMap([nameKey, nestedSkeletonKey, nestedSkinKey, nestedAnimationKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeNestedRigAttachmentBnbScalars, properties, bonyNestedRigAttachmentScalarSpecs, strings, "nestedRigAttachment")
      nestedRigAttachments.add nestedRigAttachmentData(
        scalars.bnbScalarString(nameKey, "nestedRigAttachment.name"),
        scalars.bnbScalarString(nestedSkeletonKey, "nestedRigAttachment.nestedSkeleton"),
        scalars.bnbScalarString(nestedSkinKey, "nestedRigAttachment.nestedSkin"),
        scalars.bnbScalarString(nestedAnimationKey, "nestedRigAttachment.nestedAnimation"),
      )
    of pathTypeKey:
      flushPendingIfAny()
      let properties = record.propertyMap([nameKey, boneKey, targetKey, pathKey, orderKey, skinRequiredKey, positionKey, translateMixKey, rotateMixKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodePathBnbScalars, properties, bonyPathScalarSpecs, strings, "path")
      paths.add pathConstraintData(
        scalars.bnbScalarString(nameKey, "path.name"),
        scalars.bnbScalarString(boneKey, "path.bone"),
        scalars.bnbScalarString(targetKey, "path.target"),
        scalars.bnbScalarString(pathKey, "path.path"),
        scalars.bnbScalarInt(orderKey, "path.order"),
        skinRequired = scalars.bnbScalarBool(skinRequiredKey, "path.skinRequired"),
        hasPosition = positionKey in properties,
        position =
          if positionKey in properties: scalars.bnbScalarFloat(positionKey, "path.position")
          else: defaultFloat("path", "position"),
        hasTranslateMix = translateMixKey in properties,
        translateMix =
          if translateMixKey in properties: scalars.bnbScalarFloat(translateMixKey, "path.translateMix")
          else: defaultFloat("path", "translateMix"),
        hasRotateMix = rotateMixKey in properties,
        rotateMix =
          if rotateMixKey in properties: scalars.bnbScalarFloat(rotateMixKey, "path.rotateMix")
          else: defaultFloat("path", "rotateMix"),
      )
    of ikConstraintTypeKey:
      flushPendingIfAny()
      let properties = record.propertyMap([nameKey, bonesKey, targetKey, orderKey, skinRequiredKey, mixKey, bendPositiveKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeIkConstraintBnbScalars, properties, bonyIkConstraintScalarSpecs, strings, "ikConstraint")
      if bonesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb ikConstraint.bones is required")
      ikConstraints.add ikConstraintData(
        scalars.bnbScalarString(nameKey, "ikConstraint.name"),
        scalars.bnbScalarString(targetKey, "ikConstraint.target"),
        readBonesPayload(properties[bonesKey], strings),
        order = scalars.bnbScalarInt(orderKey, "ikConstraint.order"),
        skinRequired = scalars.bnbScalarBool(skinRequiredKey, "ikConstraint.skinRequired"),
        hasMix = mixKey in properties,
        mix =
          if mixKey in properties: scalars.bnbScalarFloat(mixKey, "ikConstraint.mix")
          else: defaultFloat("ikConstraint", "mix"),
        hasBendPositive = bendPositiveKey in properties,
        bendPositive =
          if bendPositiveKey in properties: scalars.bnbScalarBool(bendPositiveKey, "ikConstraint.bendPositive")
          else: defaultBool("ikConstraint", "bendPositive"),
      )
    of transformConstraintTypeKey:
      flushPendingIfAny()
      let properties = record.propertyMap([nameKey, boneKey, targetKey, orderKey, skinRequiredKey, translateMixKey, rotateMixKey, scaleMixKey, shearMixKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeTransformConstraintBnbScalars, properties, bonyTransformConstraintScalarSpecs, strings, "transformConstraint")
      transformConstraints.add transformConstraintData(
        scalars.bnbScalarString(nameKey, "transformConstraint.name"),
        scalars.bnbScalarString(boneKey, "transformConstraint.bone"),
        scalars.bnbScalarString(targetKey, "transformConstraint.target"),
        order = scalars.bnbScalarInt(orderKey, "transformConstraint.order"),
        skinRequired = scalars.bnbScalarBool(skinRequiredKey, "transformConstraint.skinRequired"),
        hasTranslateMix = translateMixKey in properties,
        translateMix =
          if translateMixKey in properties: scalars.bnbScalarFloat(translateMixKey, "transformConstraint.translateMix")
          else: defaultFloat("transformConstraint", "translateMix"),
        hasRotateMix = rotateMixKey in properties,
        rotateMix =
          if rotateMixKey in properties: scalars.bnbScalarFloat(rotateMixKey, "transformConstraint.rotateMix")
          else: defaultFloat("transformConstraint", "rotateMix"),
        hasScaleMix = scaleMixKey in properties,
        scaleMix =
          if scaleMixKey in properties: scalars.bnbScalarFloat(scaleMixKey, "transformConstraint.scaleMix")
          else: defaultFloat("transformConstraint", "scaleMix"),
        hasShearMix = shearMixKey in properties,
        shearMix =
          if shearMixKey in properties: scalars.bnbScalarFloat(shearMixKey, "transformConstraint.shearMix")
          else: defaultFloat("transformConstraint", "shearMix"),
      )
    of physicsConstraintTypeKey:
      flushPendingIfAny()
      let properties = record.propertyMap([nameKey, boneKey, orderKey, skinRequiredKey, channelsKey, inertiaKey, strengthKey, dampingKey, massKey, gravityKey, windKey, physicsMixKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodePhysicsConstraintBnbScalars, properties, bonyPhysicsConstraintScalarSpecs, strings, "physicsConstraint")
      let channelMask = scalars.bnbScalarUint(channelsKey, "physicsConstraint.channels")
      physicsConstraints.add physicsConstraintData(
        scalars.bnbScalarString(nameKey, "physicsConstraint.name"),
        scalars.bnbScalarString(boneKey, "physicsConstraint.bone"),
        physicsChannelsFromMask(channelMask, "physicsConstraint.channels"),
        order = scalars.bnbScalarInt(orderKey, "physicsConstraint.order"),
        skinRequired = scalars.bnbScalarBool(skinRequiredKey, "physicsConstraint.skinRequired"),
        hasInertia = inertiaKey in properties,
        inertia =
          if inertiaKey in properties: scalars.bnbScalarFloat(inertiaKey, "physicsConstraint.inertia")
          else: defaultFloat("physicsConstraint", "inertia"),
        hasStrength = strengthKey in properties,
        strength =
          if strengthKey in properties: scalars.bnbScalarFloat(strengthKey, "physicsConstraint.strength")
          else: defaultFloat("physicsConstraint", "strength"),
        hasDamping = dampingKey in properties,
        damping =
          if dampingKey in properties: scalars.bnbScalarFloat(dampingKey, "physicsConstraint.damping")
          else: defaultFloat("physicsConstraint", "damping"),
        hasMass = massKey in properties,
        mass =
          if massKey in properties: scalars.bnbScalarFloat(massKey, "physicsConstraint.mass")
          else: defaultFloat("physicsConstraint", "mass"),
        hasGravity = gravityKey in properties,
        gravity =
          if gravityKey in properties: scalars.bnbScalarFloat(gravityKey, "physicsConstraint.gravity")
          else: defaultFloat("physicsConstraint", "gravity"),
        hasWind = windKey in properties,
        wind =
          if windKey in properties: scalars.bnbScalarFloat(windKey, "physicsConstraint.wind")
          else: defaultFloat("physicsConstraint", "wind"),
        hasMix = physicsMixKey in properties,
        mix =
          if physicsMixKey in properties: scalars.bnbScalarFloat(physicsMixKey, "physicsConstraint.physicsMix")
          else: defaultFloat("physicsConstraint", "physicsMix"),
      )
    of parameterTypeKey:
      flushSkinIfAny()
      flushPendingIfAny()
      let properties = record.propertyMap([nameKey, parameterMinKey, parameterMaxKey, parameterDefaultKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeParameterBnbScalars, properties, bonyParameterScalarSpecs, strings, "parameter")
      loadedParameters.add ParameterAxis(
        name: scalars.bnbScalarString(nameKey, "parameter.name"),
        minValue: scalars.bnbScalarFloat(parameterMinKey, "parameter.min"),
        maxValue: scalars.bnbScalarFloat(parameterMaxKey, "parameter.max"),
        defaultValue: scalars.bnbScalarFloat(parameterDefaultKey, "parameter.default"),
      )
    of skinTypeKey:
      flushPendingIfAny()
      flushSkinIfAny()
      let properties = record.propertyMap([
        nameKey,
        skinBonesKey,
        skinIkConstraintsKey,
        skinTransformConstraintsKey,
        skinPathConstraintsKey,
        skinPhysicsConstraintsKey,
      ])
      let scalars = decodeBnbScalarsFromProperties(
        decodeSkinBnbScalars, properties, bonySkinScalarSpecs, strings, "skin")
      currentSkinName = scalars.bnbScalarString(nameKey, "skin.name")
      currentSkinEntries = @[]
      currentSkinBones =
        if skinBonesKey in properties: readIndexListPayload(properties[skinBonesKey], boneNames(), "skin.bones")
        else: @[]
      currentSkinIkConstraints =
        if skinIkConstraintsKey in properties: readIndexListPayload(properties[skinIkConstraintsKey], ikNames(), "skin.ikConstraints")
        else: @[]
      currentSkinTransformConstraints =
        if skinTransformConstraintsKey in properties: readIndexListPayload(properties[skinTransformConstraintsKey], transformNames(), "skin.transformConstraints")
        else: @[]
      currentSkinPathConstraints =
        if skinPathConstraintsKey in properties: readIndexListPayload(properties[skinPathConstraintsKey], pathNames(), "skin.pathConstraints")
        else: @[]
      currentSkinPhysicsConstraints =
        if skinPhysicsConstraintsKey in properties: readIndexListPayload(properties[skinPhysicsConstraintsKey], physicsNames(), "skin.physicsConstraints")
        else: @[]
    of skinEntryTypeKey:
      flushPendingIfAny()
      if currentSkinName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb skinEntry record without preceding skin")
      let properties = record.propertyMap([slotKey, skinAttachmentKey, skinTargetKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeSkinEntryBnbScalars, properties, bonySkinEntryScalarSpecs, strings, "skinEntry")
      currentSkinEntries.add skinEntryData(
        scalars.bnbScalarString(slotKey, "skinEntry.slot"),
        scalars.bnbScalarString(skinAttachmentKey, "skinEntry.skinAttachment"),
        scalars.bnbScalarString(skinTargetKey, "skinEntry.skinTarget"),
      )
    of deformerTypeKey:
      flushSkinIfAny()
      flushPendingIfAny()
      let properties = record.propertyMap([deformerIdKey, parentKey, deformerOrderKey, deformerKindKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeDeformerBnbScalars, properties, bonyDeformerScalarSpecs, strings, "deformer")
      let kindStr = scalars.bnbScalarString(deformerKindKey, "deformer.kind")
      let pendingKind =
        case kindStr
        of "warp": warpDeformerKind
        of "rotation": rotationDeformerKind
        else: raise newBonyLoadError(schemaViolation, ".bnb deformer.kind must be 'warp' or 'rotation'")
      pendingDeformer.start(
        scalars.bnbScalarString(deformerIdKey, "deformer.id"),
        scalars.bnbScalarString(parentKey, "deformer.parent"),
        scalars.bnbScalarUint32(deformerOrderKey, "deformer.order"),
        pendingKind,
      )
    of warpLatticeTypeKey:
      let properties = record.propertyMap([warpRowsKey, warpColsKey, warpMinXKey, warpMinYKey, warpMaxXKey, warpMaxYKey, warpControlPointsKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeWarpLatticeBnbScalars, properties, bonyWarpLatticeScalarSpecs, strings, "warpLattice")
      let rows = scalars.bnbScalarUint32(warpRowsKey, "warpLattice.rows")
      let cols = scalars.bnbScalarUint32(warpColsKey, "warpLattice.cols")
      let minX = scalars.bnbScalarFloat(warpMinXKey, "warpLattice.minX")
      let minY = scalars.bnbScalarFloat(warpMinYKey, "warpLattice.minY")
      let maxX = scalars.bnbScalarFloat(warpMaxXKey, "warpLattice.maxX")
      let maxY = scalars.bnbScalarFloat(warpMaxYKey, "warpLattice.maxY")
      if warpControlPointsKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb warpLattice.controlPoints is required")
      let controlPoints = readControlPointsPayload(properties[warpControlPointsKey])
      pendingDeformer.setWarp(WarpLattice(rows: rows, cols: cols, minX: minX, minY: minY, maxX: maxX, maxY: maxY, controlPoints: controlPoints))
    of rotationDeformerTypeKey:
      let properties = record.propertyMap([rotationPivotXKey, rotationPivotYKey, rotationAngleDegreesKey, rotationScaleXKey, rotationScaleYKey, rotationOpacityKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeRotationDeformerBnbScalars, properties, bonyRotationDeformerScalarSpecs, strings, "rotationDeformer")
      let pivotX = scalars.bnbScalarFloat(rotationPivotXKey, "rotationDeformer.pivotX")
      let pivotY = scalars.bnbScalarFloat(rotationPivotYKey, "rotationDeformer.pivotY")
      let angleDeg = scalars.bnbScalarFloat(rotationAngleDegreesKey, "rotationDeformer.angleDegrees")
      let scaleX = scalars.bnbScalarFloat(rotationScaleXKey, "rotationDeformer.scaleX")
      let scaleY = scalars.bnbScalarFloat(rotationScaleYKey, "rotationDeformer.scaleY")
      let opacity = scalars.bnbScalarFloat(rotationOpacityKey, "rotationDeformer.opacity")
      pendingDeformer.setRotation(RotationDeformer(pivotX: pivotX, pivotY: pivotY, angleDegrees: angleDeg, scaleX: scaleX, scaleY: scaleY, opacity: opacity))
    of keyformBlendTypeKey:
      let properties = record.propertyMap([blendValueCountKey, blendAxesKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeKeyformBlendBnbScalars, properties, bonyKeyformBlendScalarSpecs, strings, "keyformBlend")
      let valueCount = scalars.bnbScalarUint32(blendValueCountKey, "keyformBlend.valueCount")
      if blendAxesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb keyformBlend.axes is required")
      var paramMap = initTable[string, ParameterAxis]()
      for p in loadedParameters:
        paramMap[p.name] = p
      pendingDeformer.startBlend(readBlendAxesPayload(properties[blendAxesKey], strings, paramMap), int(valueCount))
    of keyformTypeKey:
      let properties = record.propertyMap([blendCoordinatesKey, blendValuesKey])
      if blendCoordinatesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb keyform.coordinates is required")
      if blendValuesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb keyform.values is required")
      let coordFs = readBlendF32sPayload(properties[blendCoordinatesKey], pendingDeformer.blendAxes.len, "keyform.coordinates")
      let valueFs = readBlendF32sPayload(properties[blendValuesKey], pendingDeformer.blendValueCount, "keyform.values")
      var coordinates: seq[ParameterSample]
      for axisIndex, axis in pendingDeformer.blendAxes:
        coordinates.add ParameterSample(name: axis.name, value: coordFs[axisIndex])
      pendingDeformer.addKeyform(Keyform(coordinates: coordinates, values: valueFs))
    else:
      flushSkinIfAny()
      flushPendingIfAny()
      discard

  flushSkinIfAny()
  flushPendingIfAny()

  if not hasSkeleton:
    raise newBonyLoadError(schemaViolation, ".bnb skeleton object is required")
  skeletonData(
    headerValue, bones, slots, regions, pathAttachments, paths, loadedParameters, loadedDeformers,
    ikConstraints, transformConstraints, physicsConstraints, clips, meshes, skins,
    pointAttachments, boundingBoxAttachments, nestedRigAttachments,
  )
