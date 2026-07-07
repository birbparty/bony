proc parseCurveFromNode(kfObj: JsonNode; curveKey, kfCtx: string): TimelineCurve =
  if not kfObj.hasKey(curveKey):
    return linearTimelineCurve
  if kfObj[curveKey].kind != JString:
    raise newBonyLoadError(schemaViolation, kfCtx & "." & curveKey & " must be a string")
  let cs = kfObj[curveKey].getStr()
  case cs
  of "linear": linearTimelineCurve
  of "stepped": steppedTimelineCurve
  of "bezier":
    let c1x = requiredF64(kfObj, "c1x", kfCtx)
    let c1y = requiredF64(kfObj, "c1y", kfCtx)
    let c2x = requiredF64(kfObj, "c2x", kfCtx)
    let c2y = requiredF64(kfObj, "c2y", kfCtx)
    bezierTimelineCurve(c1x, c1y, c2x, c2y)
  else:
    raise newBonyLoadError(schemaViolation, kfCtx & "." & curveKey & " unknown: " & cs)


proc parseBonyAnimations(root: JsonNode; data: SkeletonData): Table[string, AnimationClip] =
  if not root.hasKey("animations"):
    return initTable[string, AnimationClip]()
  var meshesByName = initTable[string, MeshAttachment]()
  for mesh in data.meshAttachments:
    meshesByName[mesh.name] = mesh
  let animsNode = requireArray(root["animations"], "animations")
  for animIndex, animNode in animsNode.elems:
    let ctx = "animations[" & $animIndex & "]"
    let aObj = requireObject(animNode, ctx)
    validateKnownKeys(aObj, ["name", "boneTimelines", "slotTimelines", "eventTimelines", "deformTimelines"], ctx)
    let animName = requiredString(aObj, "name", ctx)
    if animName.len == 0:
      raise newBonyLoadError(schemaViolation, ctx & ".name must not be empty")
    if result.hasKey(animName):
      raise newBonyLoadError(duplicateKey, "duplicate animation name: " & animName)
    var boneTimelines: seq[BoneTimeline] = @[]
    if aObj.hasKey("boneTimelines"):
      let btListNode = requireArray(aObj["boneTimelines"], ctx & ".boneTimelines")
      for btIndex, btNode in btListNode.elems:
        let btCtx = ctx & ".boneTimelines[" & $btIndex & "]"
        let btObj = requireObject(btNode, btCtx)
        let bone = requiredString(btObj, "bone", btCtx)
        let propStr = requiredString(btObj, "property", btCtx)
        validateKnownKeys(btObj, ["bone", "property", "keyframes"], btCtx)
        if not btObj.hasKey("keyframes"):
          raise newBonyLoadError(schemaViolation, btCtx & ".keyframes is required")
        let kfListNode = requireArray(btObj["keyframes"], btCtx & ".keyframes")
        case propStr
        of "rotate", "translateX", "translateY", "scaleX", "scaleY", "shearX", "shearY":
          let tlKind =
            case propStr
            of "rotate": rotateTimeline
            of "translateX": translateXTimeline
            of "translateY": translateYTimeline
            of "scaleX": scaleXTimeline
            of "scaleY": scaleYTimeline
            of "shearX": shearXTimeline
            else: shearYTimeline
          var scalarKeys: seq[ScalarKeyframe] = @[]
          for kfIndex, kfNode in kfListNode.elems:
            let kfCtx = btCtx & ".keyframes[" & $kfIndex & "]"
            let kfObj = requireObject(kfNode, kfCtx)
            validateKnownKeys(kfObj, ["t", "value", "curve", "c1x", "c1y", "c2x", "c2y"], kfCtx)
            let kfTime = requiredF64(kfObj, "t", kfCtx)
            let kfValue = requiredFloat(kfObj, "value", kfCtx)
            scalarKeys.add scalarKeyframe(kfTime, kfValue, parseCurveFromNode(kfObj, "curve", kfCtx))
          boneTimelines.add boneTimeline(bone, tlKind, scalarKeys)
        of "translate", "scale", "shear":
          let tlKind =
            case propStr
            of "translate": translateTimeline
            of "scale": scaleTimeline
            else: shearTimeline
          var vectorKeys: seq[Vector2Keyframe] = @[]
          for kfIndex, kfNode in kfListNode.elems:
            let kfCtx = btCtx & ".keyframes[" & $kfIndex & "]"
            let kfObj = requireObject(kfNode, kfCtx)
            validateKnownKeys(kfObj, ["t", "x", "y", "curve", "curveX", "curveY", "c1x", "c1y", "c2x", "c2y"], kfCtx)
            let kfTime = requiredF64(kfObj, "t", kfCtx)
            let kfX = optionalFloat(kfObj, "x", 0.0, kfCtx)
            let kfY = optionalFloat(kfObj, "y", 0.0, kfCtx)
            let curveXKey = if kfObj.hasKey("curveX"): "curveX" else: "curve"
            let curveYKey = if kfObj.hasKey("curveY"): "curveY" else: "curve"
            vectorKeys.add vector2Keyframe(kfTime, kfX, kfY,
              parseCurveFromNode(kfObj, curveXKey, kfCtx),
              parseCurveFromNode(kfObj, curveYKey, kfCtx))
          boneTimelines.add boneTimeline(bone, tlKind, vectorKeys)
        of "inherit":
          var inheritKeys: seq[InheritKeyframe] = @[]
          for kfIndex, kfNode in kfListNode.elems:
            let kfCtx = btCtx & ".keyframes[" & $kfIndex & "]"
            let kfObj = requireObject(kfNode, kfCtx)
            validateKnownKeys(kfObj, ["t", "inheritRotation", "inheritScale", "inheritReflection", "transformMode"], kfCtx)
            let kfTime = requiredF64(kfObj, "t", kfCtx)
            let ir = optionalBool(kfObj, "inheritRotation", true, kfCtx)
            let isc = optionalBool(kfObj, "inheritScale", true, kfCtx)
            let irf = optionalBool(kfObj, "inheritReflection", true, kfCtx)
            let tmStr = optionalString(kfObj, "transformMode", "normal", kfCtx)
            let tm = parseTransformMode(tmStr, kfCtx)
            inheritKeys.add inheritKeyframe(kfTime, ir, isc, irf, tm)
          boneTimelines.add boneTimeline(bone, inheritTimeline, inheritKeys)
        else:
          raise newBonyLoadError(schemaViolation, btCtx & ".property unknown: " & propStr)
    var slotTimelines: seq[SlotTimeline] = @[]
    if aObj.hasKey("slotTimelines"):
      let stListNode = requireArray(aObj["slotTimelines"], ctx & ".slotTimelines")
      for stIndex, stNode in stListNode.elems:
        let stCtx = ctx & ".slotTimelines[" & $stIndex & "]"
        let stObj = requireObject(stNode, stCtx)
        let slot = requiredString(stObj, "slot", stCtx)
        let propStr = requiredString(stObj, "property", stCtx)
        validateKnownKeys(stObj, ["slot", "property", "keyframes"], stCtx)
        if not stObj.hasKey("keyframes"):
          raise newBonyLoadError(schemaViolation, stCtx & ".keyframes is required")
        let kfListNode = requireArray(stObj["keyframes"], stCtx & ".keyframes")
        case propStr
        of "attachment":
          var attachmentKeys: seq[AttachmentKeyframe] = @[]
          for kfIndex, kfNode in kfListNode.elems:
            let kfCtx = stCtx & ".keyframes[" & $kfIndex & "]"
            let kfObj = requireObject(kfNode, kfCtx)
            validateKnownKeys(kfObj, ["t", "attachment"], kfCtx)
            let kfTime = requiredF64(kfObj, "t", kfCtx)
            let att = optionalString(kfObj, "attachment", "", kfCtx)
            attachmentKeys.add attachmentKeyframe(kfTime, att)
          slotTimelines.add slotTimeline(slot, attachmentTimeline, attachmentKeys)
        of "rgba", "rgb", "alpha":
          let tlKind =
            case propStr
            of "rgba": rgbaTimeline
            of "rgb": rgbTimeline
            else: alphaTimeline
          var colorKeys: seq[ColorKeyframe] = @[]
          for kfIndex, kfNode in kfListNode.elems:
            let kfCtx = stCtx & ".keyframes[" & $kfIndex & "]"
            let kfObj = requireObject(kfNode, kfCtx)
            validateKnownKeys(kfObj, ["t", "r", "g", "b", "a", "curve", "c1x", "c1y", "c2x", "c2y"], kfCtx)
            let kfTime = requiredF64(kfObj, "t", kfCtx)
            let r = optionalFloat(kfObj, "r", 1.0, kfCtx)
            let g = optionalFloat(kfObj, "g", 1.0, kfCtx)
            let b = optionalFloat(kfObj, "b", 1.0, kfCtx)
            let a = optionalFloat(kfObj, "a", 1.0, kfCtx)
            colorKeys.add colorKeyframe(kfTime, ColorRgba(r: r, g: g, b: b, a: a), parseCurveFromNode(kfObj, "curve", kfCtx))
          slotTimelines.add slotTimeline(slot, tlKind, colorKeys)
        of "rgba2":
          var color2Keys: seq[Color2Keyframe] = @[]
          for kfIndex, kfNode in kfListNode.elems:
            let kfCtx = stCtx & ".keyframes[" & $kfIndex & "]"
            let kfObj = requireObject(kfNode, kfCtx)
            validateKnownKeys(kfObj, ["t", "r", "g", "b", "a", "dr", "dg", "db", "curve", "c1x", "c1y", "c2x", "c2y"], kfCtx)
            let kfTime = requiredF64(kfObj, "t", kfCtx)
            let r = optionalFloat(kfObj, "r", 1.0, kfCtx)
            let g = optionalFloat(kfObj, "g", 1.0, kfCtx)
            let b = optionalFloat(kfObj, "b", 1.0, kfCtx)
            let a = optionalFloat(kfObj, "a", 1.0, kfCtx)
            let dr = optionalFloat(kfObj, "dr", 0.0, kfCtx)
            let dg = optionalFloat(kfObj, "dg", 0.0, kfCtx)
            let db = optionalFloat(kfObj, "db", 0.0, kfCtx)
            let light = ColorRgba(r: r, g: g, b: b, a: a)
            color2Keys.add color2Keyframe(kfTime, ColorRgba2(light: light, darkR: dr, darkG: dg, darkB: db), parseCurveFromNode(kfObj, "curve", kfCtx))
          slotTimelines.add slotTimeline(slot, rgba2Timeline, color2Keys)
        of "sequence":
          var sequenceKeys: seq[SequenceKeyframe] = @[]
          for kfIndex, kfNode in kfListNode.elems:
            let kfCtx = stCtx & ".keyframes[" & $kfIndex & "]"
            let kfObj = requireObject(kfNode, kfCtx)
            validateKnownKeys(kfObj, ["t", "index", "delay", "mode"], kfCtx)
            let kfTime = requiredF64(kfObj, "t", kfCtx)
            let index = optionalInt(kfObj, "index", 0, kfCtx)
            let delay = optionalFloat(kfObj, "delay", 0.0, kfCtx)
            let modeStr = optionalString(kfObj, "mode", "once", kfCtx)
            let mode =
              case modeStr
              of "once": sequenceOnce
              of "loop": sequenceLoop
              of "pingpong": sequencePingpong
              of "reverse": sequenceReverse
              of "hold": sequenceHold
              else:
                raise newBonyLoadError(schemaViolation, kfCtx & ".mode unknown: " & modeStr)
            sequenceKeys.add sequenceKeyframe(kfTime, uint32(index), delay, mode)
          slotTimelines.add slotTimeline(slot, sequenceTimeline, sequenceKeys)
        else:
          raise newBonyLoadError(schemaViolation, stCtx & ".property unknown: " & propStr)
    var deformTimelines: seq[DeformTimeline] = @[]
    if aObj.hasKey("deformTimelines"):
      let dtListNode = requireArray(aObj["deformTimelines"], ctx & ".deformTimelines")
      for dtIndex, dtNode in dtListNode.elems:
        let dtCtx = ctx & ".deformTimelines[" & $dtIndex & "]"
        let dtObj = requireObject(dtNode, dtCtx)
        validateKnownKeys(dtObj, ["skin", "slot", "attachment", "vertexCount", "keyframes"], dtCtx)
        let skin = requiredString(dtObj, "skin", dtCtx)
        let slot = requiredString(dtObj, "slot", dtCtx)
        let attachment = requiredString(dtObj, "attachment", dtCtx)
        let vertexCount = requiredInt(dtObj, "vertexCount", dtCtx)
        if not data.hasSkin(skin):
          raise newBonyLoadError(unknownRequiredReference, dtCtx & ".skin names unknown skin: " & skin)
        let resolvedAttachment = data.resolveSkinAttachmentTarget(skin, slot, attachment)
        if resolvedAttachment.len == 0:
          raise newBonyLoadError(unknownRequiredReference,
            dtCtx & " does not resolve through skin lookup: " & skin & "/" & slot & "/" & attachment)
        if resolvedAttachment notin meshesByName:
          raise newBonyLoadError(unknownRequiredReference,
            dtCtx & ".attachment resolves to non-mesh or unknown target: " & resolvedAttachment)
        let mesh = meshesByName[resolvedAttachment]
        if vertexCount != mesh.vertices.len:
          raise newBonyLoadError(schemaViolation, dtCtx & ".vertexCount does not match mesh: " & resolvedAttachment)
        if not dtObj.hasKey("keyframes"):
          raise newBonyLoadError(schemaViolation, dtCtx & ".keyframes is required")
        let kfListNode = requireArray(dtObj["keyframes"], dtCtx & ".keyframes")
        var deformKeys: seq[DeformKeyframe] = @[]
        for kfIndex, kfNode in kfListNode.elems:
          let kfCtx = dtCtx & ".keyframes[" & $kfIndex & "]"
          let kfObj = requireObject(kfNode, kfCtx)
          validateKnownKeys(kfObj, ["t", "offset", "deltas", "curve", "c1x", "c1y", "c2x", "c2y"], kfCtx)
          let kfTime = requiredF64(kfObj, "t", kfCtx)
          let offset = optionalInt(kfObj, "offset", 0, kfCtx)
          if offset < 0:
            raise newBonyLoadError(schemaViolation, kfCtx & ".offset must be non-negative")
          if not kfObj.hasKey("deltas"):
            raise newBonyLoadError(schemaViolation, kfCtx & ".deltas is required")
          let deltasNode = requireArray(kfObj["deltas"], kfCtx & ".deltas")
          var deltas: seq[MeshDelta] = @[]
          for dIndex, dNode in deltasNode.elems:
            let dCtx = kfCtx & ".deltas[" & $dIndex & "]"
            let dObj = requireObject(dNode, dCtx)
            validateKnownKeys(dObj, ["x", "y"], dCtx)
            deltas.add meshDelta(
              optionalFloat(dObj, "x", 0.0, dCtx),
              optionalFloat(dObj, "y", 0.0, dCtx),
            )
          deformKeys.add deformKeyframe(kfTime, uint32(offset), deltas, parseCurveFromNode(kfObj, "curve", kfCtx))
        deformTimelines.add deformTimeline(skin, slot, attachment, mesh, deformKeys)
    var eventTimelines: seq[EventTimeline] = @[]
    if aObj.hasKey("eventTimelines"):
      let etListNode = requireArray(aObj["eventTimelines"], ctx & ".eventTimelines")
      for etIndex, etNode in etListNode.elems:
        let etCtx = ctx & ".eventTimelines[" & $etIndex & "]"
        let etObj = requireObject(etNode, etCtx)
        validateKnownKeys(etObj, ["keyframes"], etCtx)
        if not etObj.hasKey("keyframes"):
          raise newBonyLoadError(schemaViolation, etCtx & ".keyframes is required")
        let kfListNode = requireArray(etObj["keyframes"], etCtx & ".keyframes")
        var eventKeys: seq[EventKeyframe] = @[]
        for kfIndex, kfNode in kfListNode.elems:
          let kfCtx = etCtx & ".keyframes[" & $kfIndex & "]"
          let kfObj = requireObject(kfNode, kfCtx)
          validateKnownKeys(kfObj,
            ["t", "name", "intValue", "floatValue", "stringValue", "audioPath", "volume", "balance"], kfCtx)
          let kfTime = requiredF64(kfObj, "t", kfCtx)
          let evName = requiredString(kfObj, "name", kfCtx)
          let intValue = optionalInt(kfObj, "intValue", 0, kfCtx)
          if intValue < int(low(int32)) or intValue > int(high(int32)):
            raise newBonyLoadError(numericOutOfRange, kfCtx & ".intValue is out of int32 range")
          let floatValue = optionalFloat(kfObj, "floatValue", 0.0, kfCtx)
          let stringValue = optionalString(kfObj, "stringValue", "", kfCtx)
          let audioPath = optionalString(kfObj, "audioPath", "", kfCtx)
          let volume = optionalFloat(kfObj, "volume", 1.0, kfCtx)
          let balance = optionalFloat(kfObj, "balance", 0.0, kfCtx)
          let event = eventData(evName, int32(intValue), floatValue, stringValue, audioPath, volume, balance)
          eventKeys.add eventKeyframe(kfTime, event)
        eventTimelines.add eventTimeline(eventKeys)
    result[animName] = animationClip(data, animName, boneTimelines, slotTimelines,
      eventTimelines = eventTimelines, deformTimelines = deformTimelines)


proc parseBonyStateMachines(
  root: JsonNode;
  data: SkeletonData;
  clips: Table[string, AnimationClip];
): seq[StateMachine] =
  if not root.hasKey("stateMachines"):
    return @[]
  let smListNode = requireArray(root["stateMachines"], "stateMachines")
  var seenMachines = initHashSet[string]()
  for smIndex, smNode in smListNode.elems:
    let smCtx = "stateMachines[" & $smIndex & "]"
    let smObj = requireObject(smNode, smCtx)
    validateKnownKeys(smObj, ["name", "inputs", "layers", "listeners"], smCtx)
    let machineName = requiredString(smObj, "name", smCtx)
    if machineName in seenMachines:
      raise newBonyLoadError(duplicateKey, "duplicate state machine name: " & machineName)
    seenMachines.incl(machineName)
    var inputs: seq[StateMachineInput] = @[]
    if smObj.hasKey("inputs"):
      let inputsListNode = requireArray(smObj["inputs"], smCtx & ".inputs")
      for inIndex, inNode in inputsListNode.elems:
        let inCtx = smCtx & ".inputs[" & $inIndex & "]"
        let inObj = requireObject(inNode, inCtx)
        validateKnownKeys(inObj, ["name", "kind", "default"], inCtx)
        let inputName = requiredString(inObj, "name", inCtx)
        let kindStr = requiredString(inObj, "kind", inCtx)
        case kindStr
        of "bool":
          let dv = optionalBool(inObj, "default", false, inCtx)
          inputs.add stateMachineBoolInput(inputName, dv)
        of "number":
          let dv = optionalFloat(inObj, "default", 0.0, inCtx)
          inputs.add stateMachineNumberInput(inputName, dv)
        of "trigger":
          inputs.add stateMachineTriggerInput(inputName)
        else:
          raise newBonyLoadError(schemaViolation, inCtx & ".kind must be 'bool', 'number', or 'trigger'")
    var inputNames = initHashSet[string]()
    var inputKinds = initTable[string, StateMachineInputKind]()
    for inp in inputs:
      inputNames.incl(inp.name)
      inputKinds[inp.name] = inp.kind
    if not smObj.hasKey("layers"):
      raise newBonyLoadError(schemaViolation, smCtx & ".layers is required")
    let layersListNode = requireArray(smObj["layers"], smCtx & ".layers")
    var layers: seq[StateMachineLayer] = @[]
    var layerStateMap = initTable[string, HashSet[string]]()
    for layerIndex, layerNode in layersListNode.elems:
      let lCtx = smCtx & ".layers[" & $layerIndex & "]"
      let lObj = requireObject(layerNode, lCtx)
      validateKnownKeys(lObj, ["name", "states", "initialState", "transitions"], lCtx)
      let layerName = requiredString(lObj, "name", lCtx)
      let statesListNode = requireArray(lObj["states"], lCtx & ".states")
      var states: seq[StateMachineState] = @[]
      for stateIndex, stateNode in statesListNode.elems:
        let sCtx = lCtx & ".states[" & $stateIndex & "]"
        let sObj = requireObject(stateNode, sCtx)
        validateKnownKeys(sObj, ["name", "kind", "clip", "loop", "blendInput", "blendClips"], sCtx)
        let stateName = requiredString(sObj, "name", sCtx)
        let stateKindStr = requiredString(sObj, "kind", sCtx)
        case stateKindStr
        of "clip":
          let clipName = requiredString(sObj, "clip", sCtx)
          if clipName notin clips:
            raise newBonyLoadError(unknownRequiredReference, sCtx & ".clip references unknown animation: " & clipName)
          let loop = optionalBool(sObj, "loop", false, sCtx)
          states.add stateMachineState(stateName, clips[clipName], loop)
        of "blend1d":
          let blendInput = requiredString(sObj, "blendInput", sCtx)
          if blendInput notin inputNames:
            raise newBonyLoadError(unknownRequiredReference, sCtx & ".blendInput references unknown input: " & blendInput)
          let bcListNode = requireArray(sObj["blendClips"], sCtx & ".blendClips")
          var blendClips: seq[StateMachineBlendClip] = @[]
          for bcIndex, bcNode in bcListNode.elems:
            let bcCtx = sCtx & ".blendClips[" & $bcIndex & "]"
            let bcObj = requireObject(bcNode, bcCtx)
            validateKnownKeys(bcObj, ["clip", "value", "loop"], bcCtx)
            let bcClipName = requiredString(bcObj, "clip", bcCtx)
            if bcClipName notin clips:
              raise newBonyLoadError(unknownRequiredReference, bcCtx & ".clip references unknown animation: " & bcClipName)
            let bcValue = requiredFloat(bcObj, "value", bcCtx)
            let bcLoop = optionalBool(bcObj, "loop", false, bcCtx)
            blendClips.add stateMachineBlendClip(clips[bcClipName], bcValue, bcLoop)
          states.add stateMachineBlendState(stateName, blendInput, blendClips)
        else:
          raise newBonyLoadError(schemaViolation, sCtx & ".kind must be 'clip' or 'blend1d'")
      var stateNames = initHashSet[string]()
      for s in states:
        stateNames.incl(s.name)
      var transitions: seq[StateMachineTransition] = @[]
      if lObj.hasKey("transitions"):
        let transListNode = requireArray(lObj["transitions"], lCtx & ".transitions")
        for trIndex, trNode in transListNode.elems:
          let trCtx = lCtx & ".transitions[" & $trIndex & "]"
          let trObj = requireObject(trNode, trCtx)
          validateKnownKeys(trObj, ["fromState", "toState", "conditions"], trCtx)
          let fromState = requiredString(trObj, "fromState", trCtx)
          if fromState notin stateNames:
            raise newBonyLoadError(unknownRequiredReference, trCtx & ".fromState references unknown state: " & fromState)
          let toState = requiredString(trObj, "toState", trCtx)
          if toState notin stateNames:
            raise newBonyLoadError(unknownRequiredReference, trCtx & ".toState references unknown state: " & toState)
          let condListNode = requireArray(trObj["conditions"], trCtx & ".conditions")
          var conditions: seq[StateMachineCondition] = @[]
          for condIndex, condNode in condListNode.elems:
            let condCtx = trCtx & ".conditions[" & $condIndex & "]"
            let condObj = requireObject(condNode, condCtx)
            validateKnownKeys(condObj, ["input", "kind", "value"], condCtx)
            let condInput = requiredString(condObj, "input", condCtx)
            if condInput notin inputNames:
              raise newBonyLoadError(unknownRequiredReference, condCtx & ".input references unknown input: " & condInput)
            let condKindStr = requiredString(condObj, "kind", condCtx)
            case condKindStr
            of "boolEquals":
              let bv = optionalBool(condObj, "value", true, condCtx)
              conditions.add stateMachineBoolCondition(condInput, bv)
            of "numberEquals":
              let nv = requiredFloat(condObj, "value", condCtx)
              conditions.add stateMachineNumberCondition(condInput, numberEqualsCondition, nv)
            of "numberGreater":
              let nv = requiredFloat(condObj, "value", condCtx)
              conditions.add stateMachineNumberCondition(condInput, numberGreaterCondition, nv)
            of "numberGreaterOrEqual":
              let nv = requiredFloat(condObj, "value", condCtx)
              conditions.add stateMachineNumberCondition(condInput, numberGreaterOrEqualCondition, nv)
            of "numberLess":
              let nv = requiredFloat(condObj, "value", condCtx)
              conditions.add stateMachineNumberCondition(condInput, numberLessCondition, nv)
            of "numberLessOrEqual":
              let nv = requiredFloat(condObj, "value", condCtx)
              conditions.add stateMachineNumberCondition(condInput, numberLessOrEqualCondition, nv)
            of "triggerSet":
              conditions.add stateMachineTriggerCondition(condInput)
            else:
              raise newBonyLoadError(schemaViolation, condCtx & ".kind unknown: " & condKindStr)
          transitions.add stateMachineTransition(fromState, toState, conditions)
      let initialState = optionalString(lObj, "initialState", "", lCtx)
      layerStateMap[layerName] = stateNames
      layers.add stateMachineLayer(layerName, states, initialState, transitions)
    var listeners: seq[StateMachineListener] = @[]
    if smObj.hasKey("listeners"):
      let lstListNode = requireArray(smObj["listeners"], smCtx & ".listeners")
      for lstIndex, lstNode in lstListNode.elems:
        let lstCtx = smCtx & ".listeners[" & $lstIndex & "]"
        let lstObj = requireObject(lstNode, lstCtx)
        validateKnownKeys(lstObj,
          ["name", "kind", "layer", "fromState", "toState", "slot", "targetKind", "target", "hitRadius", "input", "value"],
          lstCtx)
        let lstName = requiredString(lstObj, "name", lstCtx)
        let lstKindStr = requiredString(lstObj, "kind", lstCtx)
        case lstKindStr
        of "stateEnter":
          let lstLayer = requiredString(lstObj, "layer", lstCtx)
          if lstLayer notin layerStateMap:
            raise newBonyLoadError(unknownRequiredReference, lstCtx & ".layer references unknown layer: " & lstLayer)
          if lstObj.hasKey("slot") or lstObj.hasKey("targetKind") or lstObj.hasKey("target") or
              lstObj.hasKey("hitRadius") or lstObj.hasKey("input") or lstObj.hasKey("value"):
            raise newBonyLoadError(schemaViolation, lstCtx & " lifecycle listener must not contain pointer fields")
          let lstStates = layerStateMap[lstLayer]
          let toState = requiredString(lstObj, "toState", lstCtx)
          if toState notin lstStates:
            raise newBonyLoadError(unknownRequiredReference, lstCtx & ".toState references unknown state: " & toState)
          listeners.add stateMachineStateEnterListener(lstName, lstLayer, toState)
        of "stateExit":
          let lstLayer = requiredString(lstObj, "layer", lstCtx)
          if lstLayer notin layerStateMap:
            raise newBonyLoadError(unknownRequiredReference, lstCtx & ".layer references unknown layer: " & lstLayer)
          if lstObj.hasKey("slot") or lstObj.hasKey("targetKind") or lstObj.hasKey("target") or
              lstObj.hasKey("hitRadius") or lstObj.hasKey("input") or lstObj.hasKey("value"):
            raise newBonyLoadError(schemaViolation, lstCtx & " lifecycle listener must not contain pointer fields")
          let lstStates = layerStateMap[lstLayer]
          let fromState = requiredString(lstObj, "fromState", lstCtx)
          if fromState notin lstStates:
            raise newBonyLoadError(unknownRequiredReference, lstCtx & ".fromState references unknown state: " & fromState)
          listeners.add stateMachineStateExitListener(lstName, lstLayer, fromState)
        of "transition":
          let lstLayer = requiredString(lstObj, "layer", lstCtx)
          if lstLayer notin layerStateMap:
            raise newBonyLoadError(unknownRequiredReference, lstCtx & ".layer references unknown layer: " & lstLayer)
          if lstObj.hasKey("slot") or lstObj.hasKey("targetKind") or lstObj.hasKey("target") or
              lstObj.hasKey("hitRadius") or lstObj.hasKey("input") or lstObj.hasKey("value"):
            raise newBonyLoadError(schemaViolation, lstCtx & " lifecycle listener must not contain pointer fields")
          let lstStates = layerStateMap[lstLayer]
          let fromState = requiredString(lstObj, "fromState", lstCtx)
          if fromState notin lstStates:
            raise newBonyLoadError(unknownRequiredReference, lstCtx & ".fromState references unknown state: " & fromState)
          let toState = requiredString(lstObj, "toState", lstCtx)
          if toState notin lstStates:
            raise newBonyLoadError(unknownRequiredReference, lstCtx & ".toState references unknown state: " & toState)
          listeners.add stateMachineTransitionListener(lstName, lstLayer, fromState, toState)
        of "pointerDown", "pointerUp", "pointerEnter", "pointerExit", "pointerMove":
          if lstObj.hasKey("layer") or lstObj.hasKey("fromState") or lstObj.hasKey("toState"):
            raise newBonyLoadError(schemaViolation, lstCtx & " pointer listener must not contain lifecycle fields")
          let slot = requiredString(lstObj, "slot", lstCtx)
          let targetKindStr = requiredString(lstObj, "targetKind", lstCtx)
          let targetKind =
            case targetKindStr
            of "point": pointHelperTarget
            of "boundingBox": boundingBoxHelperTarget
            else:
              raise newBonyLoadError(schemaViolation, lstCtx & ".targetKind must be 'point' or 'boundingBox'")
          let target = requiredString(lstObj, "target", lstCtx)
          var hitRadius = 0.0
          var hasHitRadius = false
          case targetKind
          of pointHelperTarget:
            hitRadius = requiredFloat(lstObj, "hitRadius", lstCtx)
            hasHitRadius = true
          of boundingBoxHelperTarget:
            if lstObj.hasKey("hitRadius"):
              raise newBonyLoadError(schemaViolation, lstCtx & ".hitRadius is invalid for boundingBox pointer listeners")
          let input = requiredString(lstObj, "input", lstCtx)
          if input notin inputNames:
            raise newBonyLoadError(unknownRequiredReference, lstCtx & ".input references unknown input: " & input)
          var boolValue = false
          var hasBoolValue = false
          var numberValue = 0.0
          var hasNumberValue = false
          case inputKinds[input]
          of boolInput:
            if not lstObj.hasKey("value"):
              raise newBonyLoadError(schemaViolation, lstCtx & ".value is required for bool pointer listeners")
            if lstObj["value"].kind != JBool:
              raise newBonyLoadError(schemaViolation, lstCtx & ".value must be bool")
            boolValue = lstObj["value"].getBool()
            hasBoolValue = true
          of numberInput:
            if not lstObj.hasKey("value"):
              raise newBonyLoadError(schemaViolation, lstCtx & ".value is required for number pointer listeners")
            if lstObj["value"].kind notin {JInt, JFloat}:
              raise newBonyLoadError(schemaViolation, lstCtx & ".value must be numeric")
            numberValue = quantizeF32(lstObj["value"].getFloat(), lstCtx & ".value")
            hasNumberValue = true
          of triggerInput:
            if lstObj.hasKey("value"):
              raise newBonyLoadError(schemaViolation, lstCtx & ".value is invalid for trigger pointer listeners")
          let pointerKind =
            case lstKindStr
            of "pointerDown": pointerDownListener
            of "pointerUp": pointerUpListener
            of "pointerEnter": pointerEnterListener
            of "pointerExit": pointerExitListener
            else: pointerMoveListener
          listeners.add stateMachinePointerListener(
            lstName, pointerKind, slot, targetKind, target, input,
            hitRadius = hitRadius,
            hasHitRadius = hasHitRadius,
            boolValue = boolValue,
            hasBoolValue = hasBoolValue,
            numberValue = numberValue,
            hasNumberValue = hasNumberValue,
          )
        else:
          raise newBonyLoadError(schemaViolation, lstCtx & ".kind must be a lifecycle or pointer listener kind")
    let machine = stateMachine(machineName, layers, inputs, listeners)
    validatePointerListenerTargets(data, machine)
    result.add machine
