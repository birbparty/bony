proc animationByIndex(animations: openArray[AnimationClip]; index: uint32; context: string): AnimationClip =
  if int(index) >= animations.len:
    raise newBonyLoadError(unknownRequiredReference, ".bnb " & context & " animation index is out of range")
  animations[int(index)]


proc inputByIndex(inputs: openArray[StateMachineInput]; index: uint32; context: string): StateMachineInput =
  if int(index) >= inputs.len:
    raise newBonyLoadError(unknownRequiredReference, ".bnb " & context & " input index is out of range")
  inputs[int(index)]


proc stateNameByIndex(states: openArray[StateMachineState]; index: uint32; context: string): string =
  if int(index) >= states.len:
    raise newBonyLoadError(unknownRequiredReference, ".bnb " & context & " state index is out of range")
  states[int(index)].name


proc decodeStateMachineObjects(
  objects: openArray[BnbObjectRecord];
  strings: BnbStringTable;
  animations: openArray[AnimationClip];
  skeleton: SkeletonData;
): seq[StateMachine] =
  var machineName = ""
  var inputs: seq[StateMachineInput]
  var layers: seq[StateMachineLayer]
  var listeners: seq[StateMachineListener]
  var layerName = ""
  var layerInitialIndex = 0'u32
  var layerStates: seq[StateMachineState]
  var layerTransitions: seq[StateMachineTransition]
  var pendingTransitionFrom = ""
  var pendingTransitionTo = ""
  var pendingConditions: seq[StateMachineCondition]
  var seenMachines = initHashSet[string]()

  template flushTransition() =
    if pendingTransitionFrom.len > 0:
      layerTransitions.add stateMachineTransition(pendingTransitionFrom, pendingTransitionTo, pendingConditions)
      pendingTransitionFrom = ""
      pendingTransitionTo = ""
      pendingConditions = @[]

  template flushLayer() =
    if layerName.len > 0:
      flushTransition()
      layers.add stateMachineLayer(layerName, layerStates, stateNameByIndex(layerStates, layerInitialIndex, "stateMachineLayer.initialStateIndex"), layerTransitions)
      layerName = ""
      layerInitialIndex = 0'u32
      layerStates = @[]
      layerTransitions = @[]

  template flushMachine() =
    if machineName.len > 0:
      flushLayer()
      if machineName in seenMachines:
        raise newBonyLoadError(duplicateKey, "duplicate state machine name: " & machineName)
      seenMachines.incl(machineName)
      result.add stateMachine(machineName, layers, inputs, listeners)
      machineName = ""
      inputs = @[]
      layers = @[]
      listeners = @[]

  for record in objects:
    case record.typeKey
    of stateMachineTypeKey:
      flushMachine()
      let properties = record.propertyMap([nameKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeStateMachineBnbScalars, properties, bonyStateMachineScalarSpecs, strings, "stateMachine")
      machineName = scalars.bnbScalarString(nameKey, "stateMachine.name")
    of stateMachineInputTypeKey:
      if machineName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineInput record without stateMachine")
      flushLayer()
      let properties = record.propertyMap([nameKey, stateMachineInputKindKey, inputDefaultBoolKey, inputDefaultNumberKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeStateMachineInputBnbScalars, properties, bonyStateMachineInputScalarSpecs, strings, "stateMachineInput")
      let name = scalars.bnbScalarString(nameKey, "stateMachineInput.name")
      let kind = inputKindFromTag(scalars.bnbScalarUint32(stateMachineInputKindKey, "stateMachineInput.kind"))
      case kind
      of boolInput:
        if inputDefaultNumberKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb bool input must not contain number default")
        inputs.add stateMachineBoolInput(
          name,
          if inputDefaultBoolKey in properties: scalars.bnbScalarBool(inputDefaultBoolKey, "stateMachineInput.defaultBool")
          else: defaultBool("stateMachineInput", "inputDefaultBool"),
        )
      of numberInput:
        if inputDefaultBoolKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb number input must not contain bool default")
        inputs.add stateMachineNumberInput(
          name,
          if inputDefaultNumberKey in properties: scalars.bnbScalarFloat(inputDefaultNumberKey, "stateMachineInput.defaultNumber")
          else: defaultFloat("stateMachineInput", "inputDefaultNumber"),
        )
      of triggerInput:
        if inputDefaultBoolKey in properties or inputDefaultNumberKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb trigger input must not contain defaults")
        inputs.add stateMachineTriggerInput(name)
    of stateMachineLayerTypeKey:
      if machineName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineLayer record without stateMachine")
      flushLayer()
      let properties = record.propertyMap([nameKey, initialStateIndexKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeStateMachineLayerBnbScalars, properties, bonyStateMachineLayerScalarSpecs, strings, "stateMachineLayer")
      layerName = scalars.bnbScalarString(nameKey, "stateMachineLayer.name")
      layerInitialIndex = scalars.bnbScalarUint32(initialStateIndexKey, "stateMachineLayer.initialStateIndex")
    of stateMachineStateTypeKey:
      if layerName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineState record without stateMachineLayer")
      flushTransition()
      let properties = record.propertyMap([nameKey, stateMachineStateKindKey, stateClipIndexKey, stateLoopKey, stateBlendInputIndexKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeStateMachineStateBnbScalars, properties, bonyStateMachineStateScalarSpecs, strings, "stateMachineState")
      let name = scalars.bnbScalarString(nameKey, "stateMachineState.name")
      let kind = stateKindFromTag(scalars.bnbScalarUint32(stateMachineStateKindKey, "stateMachineState.kind"))
      case kind
      of clipState:
        if stateBlendInputIndexKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb clip state must not contain blend input")
        let clip = animationByIndex(
          animations,
          scalars.bnbScalarUint32(stateClipIndexKey, "stateMachineState.clip"),
          "stateMachineState.clip",
        )
        layerStates.add stateMachineState(
          name,
          clip,
          if stateLoopKey in properties: scalars.bnbScalarBool(stateLoopKey, "stateMachineState.loop")
          else: defaultBool("stateMachineState", "stateLoop"),
        )
      of blend1DState:
        if stateClipIndexKey in properties or stateLoopKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb blend1d state must not contain direct clip fields")
        let input = inputByIndex(
          inputs,
          scalars.bnbScalarUint32(stateBlendInputIndexKey, "stateMachineState.blendInput"),
          "stateMachineState.blendInput",
        )
        layerStates.add StateMachineState(name: name, kind: blend1DState, blendInput: input.name)
    of stateMachineBlendClipTypeKey:
      if layerStates.len == 0 or layerStates[^1].kind != blend1DState:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineBlendClip record without blend1d state")
      let properties = record.propertyMap([blendClipAnimationIndexKey, blendClipValueKey, blendClipLoopKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeStateMachineBlendClipBnbScalars, properties, bonyStateMachineBlendClipScalarSpecs, strings, "stateMachineBlendClip")
      let clip = animationByIndex(
        animations,
        scalars.bnbScalarUint32(blendClipAnimationIndexKey, "stateMachineBlendClip.animation"),
        "stateMachineBlendClip.animation",
      )
      let value = scalars.bnbScalarFloat(blendClipValueKey, "stateMachineBlendClip.value")
      let loop = scalars.bnbScalarBool(blendClipLoopKey, "stateMachineBlendClip.loop")
      layerStates[^1].blendClips.add stateMachineBlendClip(clip, value, loop)
    of stateMachineTransitionTypeKey:
      if layerName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineTransition record without stateMachineLayer")
      flushTransition()
      let properties = record.propertyMap([transitionFromStateIndexKey, transitionToStateIndexKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeStateMachineTransitionBnbScalars, properties, bonyStateMachineTransitionScalarSpecs, strings, "stateMachineTransition")
      pendingTransitionFrom = stateNameByIndex(
        layerStates,
        scalars.bnbScalarUint32(transitionFromStateIndexKey, "stateMachineTransition.from"),
        "stateMachineTransition.from",
      )
      pendingTransitionTo = stateNameByIndex(
        layerStates,
        scalars.bnbScalarUint32(transitionToStateIndexKey, "stateMachineTransition.to"),
        "stateMachineTransition.to",
      )
    of stateMachineConditionTypeKey:
      if pendingTransitionFrom.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineCondition record without stateMachineTransition")
      let properties = record.propertyMap([conditionInputIndexKey, stateMachineConditionKindKey, conditionBoolValueKey, conditionNumberValueKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeStateMachineConditionBnbScalars, properties, bonyStateMachineConditionScalarSpecs, strings, "stateMachineCondition")
      let input = inputByIndex(
        inputs,
        scalars.bnbScalarUint32(conditionInputIndexKey, "stateMachineCondition.input"),
        "stateMachineCondition.input",
      )
      let kind = conditionKindFromTag(scalars.bnbScalarUint32(stateMachineConditionKindKey, "stateMachineCondition.kind"))
      case kind
      of boolEqualsCondition:
        if conditionNumberValueKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb bool condition must not contain number value")
        pendingConditions.add stateMachineBoolCondition(
          input.name,
          if conditionBoolValueKey in properties: scalars.bnbScalarBool(conditionBoolValueKey, "stateMachineCondition.bool")
          else: defaultBool("stateMachineCondition", "conditionBoolValue"),
        )
      of numberEqualsCondition, numberGreaterCondition, numberGreaterOrEqualCondition, numberLessCondition, numberLessOrEqualCondition:
        if conditionBoolValueKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb number condition must not contain bool value")
        pendingConditions.add stateMachineNumberCondition(
          input.name,
          kind,
          scalars.bnbScalarFloat(conditionNumberValueKey, "stateMachineCondition.number"),
        )
      of triggerSetCondition:
        if conditionBoolValueKey in properties or conditionNumberValueKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb trigger condition must not contain values")
        pendingConditions.add stateMachineTriggerCondition(input.name)
    of stateMachineListenerTypeKey:
      if machineName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineListener record without stateMachine")
      flushLayer()
      let properties = record.propertyMap([
        nameKey, stateMachineListenerKindKey, listenerLayerIndexKey, listenerFromStateIndexKey, listenerToStateIndexKey,
        listenerSlotIndexKey, listenerHelperKindKey, listenerHelperTargetKey, listenerInputIndexKey,
        listenerBoolValueKey, listenerNumberValueKey, listenerHitRadiusKey,
      ])
      let scalars = decodeBnbScalarsFromProperties(
        decodeStateMachineListenerBnbScalars, properties, bonyStateMachineListenerScalarSpecs, strings, "stateMachineListener")
      let name = scalars.bnbScalarString(nameKey, "stateMachineListener.name")
      let kind = listenerKindFromTag(scalars.bnbScalarUint32(stateMachineListenerKindKey, "stateMachineListener.kind"))
      case kind
      of stateEnterListener:
        let layerIndex = int(scalars.bnbScalarUint32(listenerLayerIndexKey, "stateMachineListener.layer"))
        if layerIndex >= layers.len:
          raise newBonyLoadError(unknownRequiredReference, ".bnb stateMachineListener.layer is out of range")
        let layer = layers[layerIndex]
        if listenerFromStateIndexKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb enter listener must not contain from state")
        listeners.add stateMachineStateEnterListener(
          name,
          layer.name,
          stateNameByIndex(layer.states, scalars.bnbScalarUint32(listenerToStateIndexKey, "stateMachineListener.to"), "stateMachineListener.to"),
        )
      of stateExitListener:
        let layerIndex = int(scalars.bnbScalarUint32(listenerLayerIndexKey, "stateMachineListener.layer"))
        if layerIndex >= layers.len:
          raise newBonyLoadError(unknownRequiredReference, ".bnb stateMachineListener.layer is out of range")
        let layer = layers[layerIndex]
        if listenerToStateIndexKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb exit listener must not contain to state")
        listeners.add stateMachineStateExitListener(
          name,
          layer.name,
          stateNameByIndex(layer.states, scalars.bnbScalarUint32(listenerFromStateIndexKey, "stateMachineListener.from"), "stateMachineListener.from"),
        )
      of transitionListener:
        let layerIndex = int(scalars.bnbScalarUint32(listenerLayerIndexKey, "stateMachineListener.layer"))
        if layerIndex >= layers.len:
          raise newBonyLoadError(unknownRequiredReference, ".bnb stateMachineListener.layer is out of range")
        let layer = layers[layerIndex]
        listeners.add stateMachineTransitionListener(
          name,
          layer.name,
          stateNameByIndex(layer.states, scalars.bnbScalarUint32(listenerFromStateIndexKey, "stateMachineListener.from"), "stateMachineListener.from"),
          stateNameByIndex(layer.states, scalars.bnbScalarUint32(listenerToStateIndexKey, "stateMachineListener.to"), "stateMachineListener.to"),
        )
      of pointerDownListener, pointerUpListener, pointerEnterListener, pointerExitListener, pointerMoveListener:
        if listenerLayerIndexKey in properties or listenerFromStateIndexKey in properties or listenerToStateIndexKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb pointer listener must not contain lifecycle fields")
        let slotIndex = int(scalars.bnbScalarUint32(listenerSlotIndexKey, "stateMachineListener.slot"))
        if slotIndex >= skeleton.slots.len:
          raise newBonyLoadError(unknownRequiredReference, ".bnb stateMachineListener.slot is out of range")
        let inputIndex = int(scalars.bnbScalarUint32(listenerInputIndexKey, "stateMachineListener.input"))
        if inputIndex >= inputs.len:
          raise newBonyLoadError(unknownRequiredReference, ".bnb stateMachineListener.input is out of range")
        let targetKind = helperKindFromTag(uint64(scalars.bnbScalarUint32(listenerHelperKindKey, "stateMachineListener.helperKind")))
        let target = scalars.bnbScalarString(listenerHelperTargetKey, "stateMachineListener.target")
        let input = inputs[inputIndex]
        var boolValue = false
        var hasBoolValue = false
        var numberValue = 0.0
        var hasNumberValue = false
        case input.kind
        of boolInput:
          if listenerBoolValueKey notin properties:
            raise newBonyLoadError(schemaViolation, ".bnb pointer bool listener value is required")
          if listenerNumberValueKey in properties:
            raise newBonyLoadError(schemaViolation, ".bnb pointer bool listener must not contain number value")
          boolValue = scalars.bnbScalarBool(listenerBoolValueKey, "stateMachineListener.boolValue")
          hasBoolValue = true
        of numberInput:
          if listenerBoolValueKey in properties:
            raise newBonyLoadError(schemaViolation, ".bnb pointer number listener must not contain bool value")
          numberValue = scalars.bnbScalarFloat(listenerNumberValueKey, "stateMachineListener.numberValue")
          hasNumberValue = true
        of triggerInput:
          if listenerBoolValueKey in properties or listenerNumberValueKey in properties:
            raise newBonyLoadError(schemaViolation, ".bnb pointer trigger listener must not contain values")
        var hitRadius = 0.0
        var hasHitRadius = false
        case targetKind
        of pointHelperTarget:
          hitRadius = scalars.bnbScalarFloat(listenerHitRadiusKey, "stateMachineListener.hitRadius")
          hasHitRadius = true
        of boundingBoxHelperTarget:
          if listenerHitRadiusKey in properties:
            raise newBonyLoadError(schemaViolation, ".bnb pointer bounding-box listener must not contain hitRadius")
        listeners.add stateMachinePointerListener(
          name, kind, skeleton.slots[slotIndex].name, targetKind, target, input.name,
          hitRadius = hitRadius,
          hasHitRadius = hasHitRadius,
          boolValue = boolValue,
          hasBoolValue = hasBoolValue,
          numberValue = numberValue,
          hasNumberValue = hasNumberValue,
        )
    else:
      discard
  flushMachine()
