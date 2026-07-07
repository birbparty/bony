## Shared input-script, numeric-golden, and render/play implementation.

import std/[json, os, parseutils, sets, strutils, tables]

import bony
import pixie

import ../argparse
import ../cli_common
import ../json_schema

type
  ScriptInputKind = enum
    scriptBoolInput,
    scriptNumberInput,
    scriptTriggerInput

  ScriptInput = object
    name: string
    kind: ScriptInputKind
    boolValue: bool
    numberValue: float64

  ScriptPointer = object
    kind: StateMachineListenerKind
    x: float64
    y: float64

  InputScriptSample = object
    name: string
    time: float64
    inputs: seq[ScriptInput]
    pointer: ScriptPointer
    hasPointer: bool

  InputScriptChild = object
    skeleton: string
    asset: string
    binaryAsset: string

  InputScript = object
    asset: string
    stateMachine: string
    activeSkin: string
    children: seq[InputScriptChild]
    samples: seq[InputScriptSample]

  StateMachineRunSample = object
    machine: string
    activeSkin: string
    sample: InputScriptSample
    runtime: StateMachineRuntime
    evaluated: EvaluatedStateMachine
    posedData: SkeletonData
    worlds: seq[Affine2]
    animationEvents: seq[DispatchedEvent]

  StateMachineGolden = object
    present: bool
    machine: string
    sample: string
    runtime: StateMachineRuntime
    evaluated: EvaluatedStateMachine

  RenderSlotState = object
    r: float64
    g: float64
    b: float64
    a: float64
    hasDark: bool
    darkR: float64
    darkG: float64
    darkB: float64
    hasSequence: bool
    sequenceIndex: uint32
    sequenceDelay: float64
    sequenceMode: SequenceMode


proc affineJson(world: Affine2): JsonNode =
  result = newJObject()
  result["a"] = newJFloat(world.a)
  result["b"] = newJFloat(world.b)
  result["c"] = newJFloat(world.c)
  result["d"] = newJFloat(world.d)
  result["tx"] = newJFloat(world.tx)
  result["ty"] = newJFloat(world.ty)


proc vertexJson(vertex: DrawVertex): JsonNode =
  result = newJObject()
  result["x"] = newJFloat(vertex.x)
  result["y"] = newJFloat(vertex.y)
  result["u"] = newJFloat(vertex.u)
  result["v"] = newJFloat(vertex.v)
  result["r"] = newJFloat(vertex.r)
  result["g"] = newJFloat(vertex.g)
  result["b"] = newJFloat(vertex.b)
  result["a"] = newJFloat(vertex.a)


# `defaultParameterSamples`, `effectiveDeformers`, and
# `applyDeformersToDrawBatches` now live in the exported runtime module
# `bony/deform/drawbatch_deform` (re-exported via `bony`) so library consumers
# share the CLI's deformer-application stage. The CLI delegates to them below.


proc deformerJson(rec: DeformerRecord; samples: seq[ParameterSample]): JsonNode =
  result = newJObject()
  result["id"] = newJString(rec.deformer.id)
  if rec.deformer.parent.len > 0:
    result["parent"] = newJString(rec.deformer.parent)
  result["order"] = newJInt(int(rec.deformer.order))
  case rec.deformer.kind
  of warpDeformerKind:
    result["kind"] = newJString("warp")
    var pts: seq[DeformerPoint]
    if rec.keyformBlend.axes.len > 0 and rec.keyformBlend.keyforms.len > 0:
      pts = sampleKeyformPoints(rec.keyformBlend, samples)
    else:
      pts = rec.deformer.warp.controlPoints
    var cpArr = newJArray()
    for pt in pts:
      var cpNode = newJObject()
      cpNode["x"] = newJFloat(pt.x)
      cpNode["y"] = newJFloat(pt.y)
      cpArr.add cpNode
    result["controlPoints"] = cpArr
  of rotationDeformerKind:
    result["kind"] = newJString("rotation")
    let rot = rec.deformer.rotation
    var rotNode = newJObject()
    rotNode["pivotX"] = newJFloat(rot.pivotX)
    rotNode["pivotY"] = newJFloat(rot.pivotY)
    rotNode["angleDegrees"] = newJFloat(rot.angleDegrees)
    rotNode["scaleX"] = newJFloat(rot.scaleX)
    rotNode["scaleY"] = newJFloat(rot.scaleY)
    rotNode["opacity"] = newJFloat(rot.opacity)
    result["rotation"] = rotNode


proc validateBonyKeys(node: JsonNode; allowed: openArray[string]; context: string) =
  if node.kind != JObject:
    raise newBonyLoadError(schemaViolation, context & " must be an object")
  for key in node.keys:
    var found = false
    for allowedKey in allowed:
      if key == allowedKey:
        found = true
        break
    if not found:
      raise newBonyLoadError(schemaViolation, context & "." & key & " is not a recognized field")


proc requireScriptObject(node: JsonNode; context: string): JsonNode =
  json_schema.requireObject(node, context, raiseBonySchema,
    message = context & " must be an object")


proc requireScriptArray(node: JsonNode; context: string): JsonNode =
  json_schema.requireArray(node, context, raiseBonySchema,
    message = context & " must be an array")


proc scriptString(node: JsonNode; key, context: string; required = false): string =
  if not node.hasKey(key):
    if required:
      raise newBonyLoadError(schemaViolation, context & "." & key & " is required")
    return ""
  result = json_schema.optionalString(node, key, "", context, raiseBonySchema,
    message = context & "." & key & " must be a string")
  if required and result.len == 0:
    raise newBonyLoadError(schemaViolation, context & "." & key & " must not be empty")


proc scriptTime(node: JsonNode; key, context: string): float64 =
  let value = json_schema.requireField(node, key, context, raiseBonySchema,
    message = context & "." & key & " is required")
  result = quantizeF32(
    json_schema.requireNumberType(value, context, key, raiseBonySchema,
      message = context & "." & key & " must be a number"),
    context & "." & key,
  )
  if result < 0:
    raise newBonyLoadError(schemaViolation, context & "." & key & " must be non-negative")


proc scriptFloat(node: JsonNode; key, context: string): float64 =
  let value = json_schema.requireField(node, key, context, raiseBonySchema,
    message = context & "." & key & " is required")
  quantizeF32(
    json_schema.requireNumberType(value, context, key, raiseBonySchema,
      message = context & "." & key & " must be a number"),
    context & "." & key,
  )


proc scriptSafeRelativeAsset(value, context: string) =
  if value.len == 0:
    raise newBonyLoadError(schemaViolation, context & " must not be empty")
  if value.isAbsolute or value.contains(".."):
    raise newBonyLoadError(schemaViolation, context & " must be a safe relative asset path")


proc parsePointerKind(value, context: string): StateMachineListenerKind =
  case value
  of "pointerDown": pointerDownListener
  of "pointerUp": pointerUpListener
  of "pointerEnter": pointerEnterListener
  of "pointerExit": pointerExitListener
  of "pointerMove": pointerMoveListener
  else:
    raise newBonyLoadError(schemaViolation, context & ".kind must be a pointer listener kind")


proc safeSampleName(name: string): bool =
  if name.len == 0:
    return false
  var hasNonDigit = false
  for ch in name:
    if not (ch in {'a'..'z', 'A'..'Z', '0'..'9', '_', '-', '.'}):
      return false
    if ch notin {'0'..'9'}:
      hasNonDigit = true
  if not hasNonDigit:
    return false
  true


proc parseInputScript(path: string): InputScript =
  let text = readFile(path)
  rejectDuplicateObjectKeys(text)
  let parsed =
    try:
      parseJson(text)
    except JsonParsingError as exc:
      raise newBonyLoadError(schemaViolation, "invalid input script JSON: " & exc.msg)

  let root = requireScriptObject(parsed, "inputScript")
  validateBonyKeys(root, ["format", "asset", "stateMachine", "activeSkin", "children", "samples"], "inputScript")
  if scriptString(root, "format", "inputScript", required = true) != "bony.input-script.v1":
    raise newBonyLoadError(schemaViolation, "inputScript.format must be bony.input-script.v1")
  result.asset = scriptString(root, "asset", "inputScript", required = true)
  scriptSafeRelativeAsset(result.asset, "inputScript.asset")
  result.stateMachine = scriptString(root, "stateMachine", "inputScript")
  result.activeSkin = scriptString(root, "activeSkin", "inputScript")
  if result.activeSkin.len == 0:
    result.activeSkin = "default"

  if root.hasKey("children"):
    let childrenObj = requireScriptObject(root["children"], "inputScript.children")
    for skeletonId, childNode in childrenObj.pairs:
      if skeletonId.len == 0:
        raise newBonyLoadError(schemaViolation, "inputScript.children key must not be empty")
      let childContext = "inputScript.children." & skeletonId
      let childObj = requireScriptObject(childNode, childContext)
      validateBonyKeys(childObj, ["asset", "binaryAsset"], childContext)
      let childAsset = scriptString(childObj, "asset", childContext, required = true)
      scriptSafeRelativeAsset(childAsset, childContext & ".asset")
      let childBinaryAsset = scriptString(childObj, "binaryAsset", childContext)
      if childBinaryAsset.len > 0:
        scriptSafeRelativeAsset(childBinaryAsset, childContext & ".binaryAsset")
      result.children.add InputScriptChild(
        skeleton: skeletonId,
        asset: childAsset,
        binaryAsset: childBinaryAsset,
      )

  if not root.hasKey("samples"):
    raise newBonyLoadError(schemaViolation, "inputScript.samples is required")
  let samplesNode = requireScriptArray(root["samples"], "inputScript.samples")
  if samplesNode.elems.len == 0:
    raise newBonyLoadError(schemaViolation, "inputScript.samples must not be empty")

  for sampleIndex, item in samplesNode.elems:
    let context = "inputScript.samples[" & $sampleIndex & "]"
    let sampleObj = requireScriptObject(item, context)
    validateBonyKeys(sampleObj, ["name", "t", "inputs", "pointer"], context)
    var sample = InputScriptSample(
      name: scriptString(sampleObj, "name", context),
      time: scriptTime(sampleObj, "t", context),
    )
    if sample.name.len > 0 and not sample.name.safeSampleName:
      raise newBonyLoadError(schemaViolation, context & ".name must contain only letters, digits, _, -, or . and must not be numeric-only")
    if sampleObj.hasKey("inputs"):
      let inputsObj = requireScriptObject(sampleObj["inputs"], context & ".inputs")
      for inputName, inputValue in inputsObj.pairs:
        if inputName.len == 0:
          raise newBonyLoadError(schemaViolation, context & ".inputs key must not be empty")
        case inputValue.kind
        of JBool:
          sample.inputs.add ScriptInput(name: inputName, kind: scriptBoolInput, boolValue: inputValue.getBool())
        of JInt, JFloat:
          sample.inputs.add ScriptInput(
            name: inputName,
            kind: scriptNumberInput,
            numberValue: quantizeF32(inputValue.getFloat(), context & ".inputs." & inputName),
          )
        of JString:
          if inputValue.getStr() != "fire":
            raise newBonyLoadError(schemaViolation, context & ".inputs." & inputName & " string value must be \"fire\"")
          sample.inputs.add ScriptInput(name: inputName, kind: scriptTriggerInput)
        else:
          raise newBonyLoadError(schemaViolation, context & ".inputs." & inputName & " must be bool, number, or \"fire\"")
    if sampleObj.hasKey("pointer"):
      let pointerObj = requireScriptObject(sampleObj["pointer"], context & ".pointer")
      validateBonyKeys(pointerObj, ["kind", "x", "y"], context & ".pointer")
      sample.pointer = ScriptPointer(
        kind: parsePointerKind(scriptString(pointerObj, "kind", context & ".pointer", required = true), context & ".pointer"),
        x: scriptFloat(pointerObj, "x", context & ".pointer"),
        y: scriptFloat(pointerObj, "y", context & ".pointer"),
      )
      sample.hasPointer = true
    result.samples.add sample


proc validateStateMachineScript(script: InputScript; machineName: string) =
  if machineName.len == 0:
    raise newBonyLoadError(schemaViolation, "state-machine execution requires --state-machine or inputScript.stateMachine")
  if script.children.len > 0:
    raise newBonyLoadError(schemaViolation, "inputScript.children is only valid for setup-pose scripts")
  var names = initHashSet[string]()
  var previousTime = 0.0
  for index, sample in script.samples:
    if sample.name.len == 0:
      raise newBonyLoadError(schemaViolation, "state-machine input-script samples require name")
    if sample.name in names:
      raise newBonyLoadError(duplicateKey, "duplicate input-script sample name: " & sample.name)
    names.incl(sample.name)
    if index > 0 and sample.time < previousTime:
      raise newBonyLoadError(schemaViolation, "state-machine input-script sample times must be non-decreasing")
    previousTime = sample.time


proc resolveStateMachineName(cliName: string; script: InputScript): string =
  result = cliName
  if result.len == 0:
    result = script.stateMachine
  elif script.stateMachine.len > 0 and script.stateMachine != result:
    raise newBonyLoadError(schemaViolation, "--state-machine does not match inputScript.stateMachine")


proc selectStateMachine(machines: openArray[StateMachine]; name: string): StateMachine =
  for machine in machines:
    if machine.name == name:
      return machine
  raise newBonyLoadError(unknownRequiredReference, "unknown state machine: " & name)


proc selectAnimation(animations: openArray[AnimationClip]; name: string): AnimationClip =
  for clip in animations:
    if clip.name == name:
      return clip
  raise newBonyLoadError(unknownRequiredReference, "unknown animation: " & name)


proc applyScriptInputs(runtime: var StateMachineRuntime; inputs: openArray[ScriptInput]) =
  for input in inputs:
    case input.kind
    of scriptBoolInput:
      runtime.setBoolInput(input.name, input.boolValue)
    of scriptNumberInput:
      runtime.setNumberInput(input.name, input.numberValue)
    of scriptTriggerInput:
      runtime.fireTrigger(input.name)


proc sampleMatches(sample: InputScriptSample; index: int; selector: string): bool =
  if selector.len == 0:
    return true
  var parsedIndex: int
  let consumed = parseInt(selector, parsedIndex)
  if consumed == selector.len:
    return index == parsedIndex
  sample.name == selector


proc regionNames(data: SkeletonData): HashSet[string] =
  result = initHashSet[string]()
  for region in data.regions:
    result.incl(region.name)


proc sequenceAttachmentName(attachment: string; index: uint32): string =
  if attachment.len == 0:
    return attachment
  var suffixStart = attachment.len
  while suffixStart > 0 and attachment[suffixStart - 1].isDigit:
    dec suffixStart
  let suffix =
    if suffixStart == attachment.len:
      $index
    else:
      align($index, attachment.len - suffixStart, '0')
  attachment[0 ..< suffixStart] & suffix


proc applySequencePose*(data: SkeletonData; pose: MixedPose): SkeletonData =
  if pose.sequences.len == 0:
    return data

  var sequenceLookup = initTable[string, MixedSequence]()
  for value in pose.sequences:
    sequenceLookup[value.target] = value

  let knownRegions = data.regionNames()
  var slots: seq[SlotData]
  for slot in data.slots:
    var attachment = slot.attachment
    if slot.name in sequenceLookup:
      let sequence = sequenceLookup[slot.name]
      attachment = sequenceAttachmentName(attachment, sequence.value.index)
      if attachment.len > 0 and attachment notin knownRegions:
        raise newBonyLoadError(
          unknownRequiredReference,
          "unknown sequence frame attachment for slot " & slot.name & ": " & attachment,
        )
    slots.add slotData(slot.name, slot.bone, attachment)

  # Preserve meshAttachments/clippingAttachments AND the transient deform
  # override so a sequence-rebuilt pose still carries an animated mesh's deltas
  # through to buildDrawBatches (applySequencePose rebuilds SkeletonData a second
  # time after applyPose; without this the override would be silently dropped).
  skeletonData(
    data.header,
    data.bones,
    slots,
    data.regions,
    data.pathAttachments,
    data.paths,
    data.parameters,
    data.deformers,
    data.ikConstraints,
    data.transformConstraints,
    data.physicsConstraints,
    data.clippingAttachments,
    data.meshAttachments,
    data.skins,
  ).withDeformOverrides(data.deformOverrides)


proc applyRenderablePose*(data: SkeletonData; pose: MixedPose): SkeletonData =
  data.applyPose(pose).applySequencePose(pose)


proc executeStateMachineScript(
  assetPath, stateMachineName, scriptPath, selector: string;
): seq[StateMachineRunSample] =
  let script = parseInputScript(scriptPath)
  let assetName = extractFilename(assetPath)
  let scriptComparableAsset =
    if assetName.toLowerAscii.endsWith(".bnb"):
      assetName.changeFileExt(".bony")
    else:
      assetName
  if scriptComparableAsset != script.asset:
    raise newBonyLoadError(schemaViolation, "inputScript.asset does not match input asset")
  let machineName = resolveStateMachineName(stateMachineName, script)
  validateStateMachineScript(script, machineName)

  let asset =
    if assetPath.toLowerAscii.endsWith(".bnb"):
      loadBonyBnbAsset(readBytes(assetPath))
    else:
      loadBonyJsonAsset(readFile(assetPath))
  let data = asset.skeleton
  var dataRef = new(SkeletonData)
  dataRef[] = data
  var runtime = initStateMachineRuntime(selectStateMachine(asset.stateMachines, machineName))
  # Physics is bony's only stateful, time-dependent constraint: the story runner
  # is the single time driver, so its per-sample inter-sample delta is the dt the
  # physics stage advances by. `physicsStates` carries PhysicsConstraintState
  # across every sample (advanced even for unmatched samples) so a re-run that
  # selects a late sample reproduces the same continuous trajectory. With no
  # physics constraints advancePhysics is exactly computeWorldTransforms, so
  # existing (physics-free) story goldens are unchanged.
  var physicsStates = newPhysicsStates(data)
  # Event-timeline dispatch bridge (docs/event-timeline-contract.md "Dispatch
  # output channel"). The clip mixer's event dispatch is never reached along the
  # state-machine story path — the SM runner steps layer time and samples poses
  # directly, it never drives an AnimationState. So we mirror each layer's active
  # clip onto its own single-track AnimationState and advance that track by the
  # same per-sample delta the state machine is advanced by. `AnimationState.update`
  # resets its event list every call, so the events collected per sample are
  # exactly the events fired in that inter-sample window (the incremental,
  # reset-per-sample parity contract prompts 29/30 depend on) — never the
  # cumulative [0, t] window. A state transition reloads that layer's track (time
  # reset to 0), mirroring the SM layer-time reset.
  var layerAnimStates = newSeq[AnimationState](runtime.layers.len)
  for animState in layerAnimStates.mitems:
    animState = animationState()
  var layerLoadedStates = newSeq[string](runtime.layers.len)
  # Previous post-update layer time, per layer. Layer time is monotonic
  # non-decreasing (dt is non-negative and looping never resets it), so a
  # decrease can only mean a state transition reset layer time to 0 — including
  # a self-transition (A->A), which is legal and keeps the state name unchanged.
  # We detect that reset by time, not by name, so a self-transition still reloads
  # the mirrored track instead of silently desyncing it forever.
  var layerPrevTimes = newSeq[float64](runtime.layers.len)
  var previousTime = 0.0
  var matched = false
  for index, sample in script.samples:
    runtime.clearEvents()
    runtime.applyScriptInputs(sample.inputs)
    if sample.hasPointer:
      let pointerEvaluated = runtime.evaluate(dataRef)
      let pointerPosed = data.applyRenderablePose(pointerEvaluated.pose)
      if not pointerPosed.hasSkin(script.activeSkin):
        raise newBonyLoadError(unknownRequiredReference, "unknown active skin: " & script.activeSkin)
      let pointerWorlds = computeWorldTransforms(pointerPosed, script.activeSkin)
      runtime.dispatchPointerListeners(
        pointerPosed,
        pointerWorlds,
        script.activeSkin,
        sample.pointer.kind,
        sample.pointer.x,
        sample.pointer.y,
      )
    runtime.update(sample.time - previousTime, preserveEvents = true)
    let evaluated = runtime.evaluate(dataRef)
    let posed = data.applyRenderablePose(evaluated.pose)
    if not posed.hasSkin(script.activeSkin):
      raise newBonyLoadError(unknownRequiredReference, "unknown active skin: " & script.activeSkin)
    let worlds = advancePhysics(posed, physicsStates, sample.time - previousTime, script.activeSkin)
    var sampleEvents: seq[DispatchedEvent]
    for layerIndex in 0 ..< runtime.layers.len:
      let layerRt = runtime.layers[layerIndex]
      let active = layerRt.currentState()
      let layerTimeReset = layerRt.time < layerPrevTimes[layerIndex]
      layerPrevTimes[layerIndex] = layerRt.time
      if active.kind != clipState:
        # A 1D blend has no single owning clip; event dispatch across a blend is
        # out of scope for this slice. Disarm so a later clip re-entry reloads.
        layerLoadedStates[layerIndex] = ""
        continue
      # Reload the mirrored track on a state change OR a same-name layer-time
      # reset (self-transition). Note: a transition observed here is a hard cut —
      # the outgoing clip's events in this sample's partial pre-transition window
      # are intentionally NOT dispatched, matching the SM's instantaneous pose
      # evaluation and layer-time reset (the incremental parity contract prompts
      # 29/30 reproduce). Only the post-update active clip dispatches.
      if layerLoadedStates[layerIndex] != active.name or layerTimeReset:
        layerAnimStates[layerIndex].setAnimation(0, active.clip, active.loop)
        layerLoadedStates[layerIndex] = active.name
      # Advance this layer's track to the SM layer's post-update (raw) time. In
      # steady state this is the inter-sample step; right after a (re)load the
      # track sits at 0 and advances to the post-reset layer time.
      let amount = max(0.0, layerRt.time - layerAnimStates[layerIndex].tracks[0].current.time)
      layerAnimStates[layerIndex].update(amount)
      for dispatched in layerAnimStates[layerIndex].events:
        sampleEvents.add dispatched
    if sample.sampleMatches(index, selector):
      matched = true
      result.add StateMachineRunSample(
        machine: machineName,
        activeSkin: script.activeSkin,
        sample: sample,
        runtime: runtime,
        evaluated: evaluated,
        posedData: posed,
        worlds: worlds,
        animationEvents: sampleEvents,
      )
    previousTime = sample.time
  if not matched:
    raise newBonyLoadError(unknownRequiredReference, "unknown input-script sample: " & selector)


proc resolveInputScriptAssetPath(scriptPath, assetName: string): string =
  let scriptDir = parentDir(scriptPath)
  normalizedPath(scriptDir / ".." / "assets" / assetName)


proc validateSetupPoseScript(script: InputScript) =
  if script.stateMachine.len > 0:
    raise newBonyLoadError(schemaViolation, "setup-pose input scripts must not declare stateMachine")
  var names = initHashSet[string]()
  for index, sample in script.samples:
    if sample.time != 0.0:
      raise newBonyLoadError(schemaViolation, "setup-pose input-script samples require t=0")
    if sample.inputs.len > 0:
      raise newBonyLoadError(schemaViolation, "setup-pose input-script samples must not declare inputs")
    if sample.hasPointer:
      raise newBonyLoadError(schemaViolation, "setup-pose input-script samples must not declare pointer")
    if sample.name.len > 0:
      if sample.name in names:
        raise newBonyLoadError(duplicateKey, "duplicate input-script sample name: " & sample.name)
      names.incl(sample.name)


proc loadInputScriptChildren(
  scriptPath: string;
  script: InputScript;
  preferBinary: bool;
): NestedSkeletonMap =
  result = initTable[string, SkeletonData]()
  for child in script.children:
    let childAsset =
      if preferBinary:
        if child.binaryAsset.len == 0:
          raise newBonyLoadError(
            unknownRequiredReference,
            "missing binary child asset for nested skeleton: " & child.skeleton,
          )
        child.binaryAsset
      else:
        child.asset
    let path = resolveInputScriptAssetPath(scriptPath, childAsset)
    if not fileExists(path):
      raise newBonyLoadError(
        unknownRequiredReference,
        "nested child asset not found for " & child.skeleton & ": " & childAsset,
      )
    if path.toLowerAscii.endsWith(".bnb"):
      result[child.skeleton] = loadBonyBnb(readBytes(path))
    else:
      result[child.skeleton] = loadBonyJson(readFile(path))


proc executeSetupPoseScript(
  assetPath, scriptPath, selector: string;
): tuple[data: SkeletonData; time: float64; activeSkin: string; children: NestedSkeletonMap] =
  let script = parseInputScript(scriptPath)
  let assetName = extractFilename(assetPath)
  let scriptComparableAsset =
    if assetName.toLowerAscii.endsWith(".bnb"):
      assetName.changeFileExt(".bony")
    else:
      assetName
  if scriptComparableAsset != script.asset:
    raise newBonyLoadError(schemaViolation, "inputScript.asset does not match input asset")
  validateSetupPoseScript(script)

  var matched = false
  var selected = InputScriptSample()
  for index, sample in script.samples:
    if sample.sampleMatches(index, selector):
      if matched:
        raise newBonyLoadError(schemaViolation, "--sample must select exactly one input-script sample")
      matched = true
      selected = sample
  if not matched:
    raise newBonyLoadError(unknownRequiredReference, "unknown input-script sample: " & selector)

  let data = loadInputSkeleton(assetPath)
  let children = loadInputScriptChildren(scriptPath, script, assetPath.toLowerAscii.endsWith(".bnb"))
  (data: data, time: selected.time, activeSkin: script.activeSkin, children: children)


proc boneTimelineKindJson(kind: BoneTimelineKind): string =
  case kind
  of rotateTimeline: "rotate"
  of translateTimeline: "translate"
  of translateXTimeline: "translateX"
  of translateYTimeline: "translateY"
  of scaleTimeline: "scale"
  of scaleXTimeline: "scaleX"
  of scaleYTimeline: "scaleY"
  of shearTimeline: "shear"
  of shearXTimeline: "shearX"
  of shearYTimeline: "shearY"
  of inheritTimeline: "inherit"


proc slotTimelineKindJson(kind: SlotTimelineKind): string =
  case kind
  of attachmentTimeline: "attachment"
  of rgbaTimeline: "rgba"
  of rgbTimeline: "rgb"
  of alphaTimeline: "alpha"
  of rgba2Timeline: "rgba2"
  of sequenceTimeline: "sequence"


proc transformModeJson(mode: TransformMode): string =
  case mode
  of normal: "normal"
  of onlyTranslation: "onlyTranslation"
  of noRotationOrReflection: "noRotationOrReflection"
  of noScale: "noScale"
  of noScaleOrReflection: "noScaleOrReflection"


proc inputKindJson(kind: StateMachineInputKind): string =
  case kind
  of boolInput: "bool"
  of numberInput: "number"
  of triggerInput: "trigger"


proc listenerKindJson(kind: StateMachineListenerKind): string =
  case kind
  of stateEnterListener: "stateEnter"
  of stateExitListener: "stateExit"
  of transitionListener: "transition"
  of pointerDownListener: "pointerDown"
  of pointerUpListener: "pointerUp"
  of pointerEnterListener: "pointerEnter"
  of pointerExitListener: "pointerExit"
  of pointerMoveListener: "pointerMove"


proc pointerHelperTargetKindJson(kind: PointerHelperTargetKind): string =
  case kind
  of pointHelperTarget: "point"
  of boundingBoxHelperTarget: "boundingBox"


proc colorJson(color: timelines.ColorRgba): JsonNode =
  result = newJObject()
  result["r"] = newJFloat(color.r)
  result["g"] = newJFloat(color.g)
  result["b"] = newJFloat(color.b)
  result["a"] = newJFloat(color.a)


proc defaultRenderSlotStates(data: SkeletonData): Table[string, RenderSlotState] =
  result = initTable[string, RenderSlotState]()
  for slot in data.slots:
    result[slot.name] = RenderSlotState(r: 1.0, g: 1.0, b: 1.0, a: 1.0)


proc renderSlotStates(data: SkeletonData; pose: MixedPose): Table[string, RenderSlotState] =
  result = data.defaultRenderSlotStates()
  for value in pose.colors:
    var state = result.getOrDefault(value.target, RenderSlotState(r: 1.0, g: 1.0, b: 1.0, a: 1.0))
    case value.kind
    of rgbTimeline:
      state.r = value.color.r
      state.g = value.color.g
      state.b = value.color.b
    of alphaTimeline:
      state.a = value.color.a
    of rgbaTimeline:
      state.r = value.color.r
      state.g = value.color.g
      state.b = value.color.b
      state.a = value.color.a
    else:
      discard
    result[value.target] = state

  for value in pose.colors2:
    var state = result.getOrDefault(value.target, RenderSlotState(r: 1.0, g: 1.0, b: 1.0, a: 1.0))
    state.r = value.color.light.r
    state.g = value.color.light.g
    state.b = value.color.light.b
    state.a = value.color.light.a
    state.hasDark = true
    state.darkR = value.color.darkR
    state.darkG = value.color.darkG
    state.darkB = value.color.darkB
    result[value.target] = state

  for value in pose.sequences:
    var state = result.getOrDefault(value.target, RenderSlotState(r: 1.0, g: 1.0, b: 1.0, a: 1.0))
    state.hasSequence = true
    state.sequenceIndex = value.value.index
    state.sequenceDelay = value.value.delay
    state.sequenceMode = value.value.mode
    result[value.target] = state


proc applyRenderSlotStates(batches: seq[DrawBatch]; states: Table[string, RenderSlotState]): seq[DrawBatch] =
  result = batches
  for batchIndex in 0 ..< result.len:
    if result[batchIndex].slot notin states:
      continue
    let state = states[result[batchIndex].slot]
    for vertexIndex in 0 ..< result[batchIndex].vertices.len:
      result[batchIndex].vertices[vertexIndex].r = state.r
      result[batchIndex].vertices[vertexIndex].g = state.g
      result[batchIndex].vertices[vertexIndex].b = state.b
      result[batchIndex].vertices[vertexIndex].a = state.a


proc poseJson(pose: MixedPose): JsonNode =
  result = newJObject()
  var scalars = newJArray()
  for value in pose.scalars:
    var node = newJObject()
    node["target"] = newJString(value.target)
    node["kind"] = newJString(boneTimelineKindJson(value.kind))
    node["value"] = newJFloat(value.value)
    scalars.add node
  result["scalars"] = scalars

  var vectors = newJArray()
  for value in pose.vectors:
    var node = newJObject()
    node["target"] = newJString(value.target)
    node["kind"] = newJString(boneTimelineKindJson(value.kind))
    node["x"] = newJFloat(value.x)
    node["y"] = newJFloat(value.y)
    vectors.add node
  result["vectors"] = vectors

  var attachments = newJArray()
  for value in pose.attachments:
    var node = newJObject()
    node["target"] = newJString(value.target)
    node["attachment"] = newJString(value.attachment)
    attachments.add node
  result["attachments"] = attachments

  var inherits = newJArray()
  for value in pose.inherits:
    var node = newJObject()
    node["target"] = newJString(value.target)
    node["inheritRotation"] = newJBool(value.value.inheritRotation)
    node["inheritScale"] = newJBool(value.value.inheritScale)
    node["inheritReflection"] = newJBool(value.value.inheritReflection)
    node["transformMode"] = newJString(transformModeJson(value.value.transformMode))
    inherits.add node
  result["inherits"] = inherits

  var colors = newJArray()
  for value in pose.colors:
    var node = newJObject()
    node["target"] = newJString(value.target)
    node["kind"] = newJString(slotTimelineKindJson(value.kind))
    node["color"] = colorJson(value.color)
    colors.add node
  result["colors"] = colors

  var colors2 = newJArray()
  for value in pose.colors2:
    var node = newJObject()
    node["target"] = newJString(value.target)
    node["light"] = colorJson(value.color.light)
    node["darkR"] = newJFloat(value.color.darkR)
    node["darkG"] = newJFloat(value.color.darkG)
    node["darkB"] = newJFloat(value.color.darkB)
    colors2.add node
  result["colors2"] = colors2

  var sequences = newJArray()
  for value in pose.sequences:
    var node = newJObject()
    node["target"] = newJString(value.target)
    node["index"] = newJInt(int(value.value.index))
    node["delay"] = newJFloat(value.value.delay)
    node["mode"] = newJString($value.value.mode)
    sequences.add node
  result["sequences"] = sequences


proc stateMachineInputsJson(runtime: StateMachineRuntime): JsonNode =
  result = newJArray()
  for value in runtime.inputs:
    var node = newJObject()
    node["name"] = newJString(value.name)
    node["kind"] = newJString(inputKindJson(value.kind))
    case value.kind
    of boolInput:
      node["value"] = newJBool(value.boolValue)
    of numberInput:
      node["value"] = newJFloat(value.numberValue)
    of triggerInput:
      node["value"] = newJBool(value.boolValue)
    result.add node


proc stateMachineLayersJson(evaluated: EvaluatedStateMachine): JsonNode =
  result = newJArray()
  for layer in evaluated.layers:
    var node = newJObject()
    node["name"] = newJString(layer.layer)
    node["state"] = newJString(layer.state)
    node["time"] = newJFloat(layer.time)
    node["pose"] = poseJson(layer.pose)
    result.add node


proc stateMachineEventsJson(runtime: StateMachineRuntime): JsonNode =
  result = newJArray()
  for event in runtime.events:
    var node = newJObject()
    node["listener"] = newJString(event.listener)
    node["kind"] = newJString(listenerKindJson(event.kind))
    if event.hasPointer:
      node["slot"] = newJString(event.slot)
      node["targetKind"] = newJString(pointerHelperTargetKindJson(event.targetKind))
      node["target"] = newJString(event.target)
      node["input"] = newJString(event.input)
      node["inputKind"] = newJString(inputKindJson(event.inputKind))
      case event.inputKind
      of boolInput:
        node["boolValue"] = newJBool(event.boolValue)
      of numberInput:
        node["numberValue"] = newJFloat(event.numberValue)
      of triggerInput:
        node["triggerValue"] = newJBool(event.triggerValue)
      node["pointerX"] = newJFloat(event.pointerX)
      node["pointerY"] = newJFloat(event.pointerY)
    else:
      node["layer"] = newJString(event.layer)
      node["fromState"] = newJString(event.fromState)
      node["toState"] = newJString(event.toState)
    result.add node


proc animationEventsJson(events: seq[DispatchedEvent]): JsonNode =
  ## Clip-dispatched events surfaced under the numeric golden's distinct
  ## `animationEvents` channel (docs/event-timeline-contract.md "Dispatch output
  ## channel"); flattens each DispatchedEvent + its EventData. Kept separate from
  ## the M8 state-machine listener `events` array.
  result = newJArray()
  for dispatched in events:
    var node = newJObject()
    node["name"] = newJString(dispatched.event.name)
    node["trackIndex"] = newJInt(dispatched.trackIndex)
    node["time"] = newJFloat(dispatched.time)
    node["intValue"] = newJInt(int(dispatched.event.intValue))
    node["floatValue"] = newJFloat(dispatched.event.floatValue)
    node["stringValue"] = newJString(dispatched.event.stringValue)
    node["audioPath"] = newJString(dispatched.event.audioPath)
    node["volume"] = newJFloat(dispatched.event.volume)
    node["balance"] = newJFloat(dispatched.event.balance)
    result.add node


proc numericGoldenJson(
    data: SkeletonData;
    time: float64;
    activeSkin = "default";
    state: StateMachineGolden = StateMachineGolden();
    physicsWorlds: seq[Affine2] = @[];
    animationEvents: seq[DispatchedEvent] = @[];
    children: NestedSkeletonMap = initTable[string, SkeletonData]();
): string =
  validateSkeletonData(data)
  if not data.hasSkin(activeSkin):
    raise newBonyLoadError(unknownRequiredReference, "unknown active skin: " & activeSkin)
  # The story runner advances the stateful physics stage and threads the
  # physics-adjusted bone worlds in via `physicsWorlds`; setup-pose callers pass
  # none and fall back to the pure world-transform pass. For a physics-free rig
  # the two are identical (advancePhysics == computeWorldTransforms).
  let worlds =
    if physicsWorlds.len == data.bones.len: physicsWorlds
    else: computeWorldTransforms(data)
  # Thread the (possibly physics-adjusted) worlds into the draw-batch build so
  # draw-batch vertices reflect the physics stage. For a physics-free rig these
  # worlds equal the pure pass, so setup-pose callers are unaffected.
  let baseBatches =
    if children.len > 0:
      buildNestedDrawBatches(data, worlds, children, activeSkin)
    else:
      buildDrawBatches(data, worlds, activeSkin)
  let samples = defaultParameterSamples(data)
  let efDefs = effectiveDeformers(data, samples)
  var batches = applyDeformersToDrawBatches(baseBatches, efDefs)
  let slotStates =
    if state.present:
      renderSlotStates(data, state.evaluated.pose)
    else:
      defaultRenderSlotStates(data)
  batches = applyRenderSlotStates(batches, slotStates)
  var root = newJObject()
  root["format"] = newJString("bony.numeric-golden.v1")
  root["skeleton"] = newJString(data.header.name)
  root["version"] = newJString(data.header.version)
  root["time"] = newJFloat(time)
  if state.present:
    root["stateMachine"] = newJString(state.machine)
    root["sample"] = newJString(state.sample)
    root["inputs"] = stateMachineInputsJson(state.runtime)
    root["layers"] = stateMachineLayersJson(state.evaluated)
    root["events"] = stateMachineEventsJson(state.runtime)
  # Distinct clip-dispatched-event channel; omitted when empty (setup-pose
  # callers, and story samples whose inter-sample window fired nothing).
  if animationEvents.len > 0:
    root["animationEvents"] = animationEventsJson(animationEvents)

  var bones = newJArray()
  let boneData = data.bones
  for index, bone in boneData:
    var node = newJObject()
    node["name"] = newJString(bone.name)
    node["parent"] = newJString(bone.parent)
    node["world"] = affineJson(worlds[index])
    bones.add node
  root["bones"] = bones

  var slots = newJArray()
  for slot in data.slots:
    var node = newJObject()
    node["name"] = newJString(slot.name)
    node["bone"] = newJString(slot.bone)
    node["attachment"] = newJString(slot.attachment)
    let slotState = slotStates.getOrDefault(slot.name, RenderSlotState(r: 1.0, g: 1.0, b: 1.0, a: 1.0))
    node["r"] = newJFloat(slotState.r)
    node["g"] = newJFloat(slotState.g)
    node["b"] = newJFloat(slotState.b)
    node["a"] = newJFloat(slotState.a)
    if slotState.hasDark:
      node["darkR"] = newJFloat(slotState.darkR)
      node["darkG"] = newJFloat(slotState.darkG)
      node["darkB"] = newJFloat(slotState.darkB)
    if slotState.hasSequence:
      node["sequenceIndex"] = newJInt(int(slotState.sequenceIndex))
      node["sequenceDelay"] = newJFloat(slotState.sequenceDelay)
      node["sequenceMode"] = newJString($slotState.sequenceMode)
    slots.add node
  root["slots"] = slots

  if data.deformers.len > 0:
    var defArray = newJArray()
    for rec in data.deformers:
      defArray.add deformerJson(rec, samples)
    root["deformers"] = defArray

  var drawBatches = newJArray()
  for batch in batches:
    var node = newJObject()
    node["slot"] = newJString(batch.slot)
    node["bone"] = newJString(batch.bone)
    node["attachment"] = newJString(batch.attachment)
    node["texturePage"] = newJString(batch.texturePage)
    node["blendMode"] = newJString(batch.blendMode)
    node["clipId"] = newJString(batch.clipId)
    node["world"] = affineJson(batch.world)
    var vertices = newJArray()
    for vertex in batch.vertices:
      vertices.add vertexJson(vertex)
    node["vertices"] = vertices
    var indices = newJArray()
    for index in batch.indices:
      indices.add newJInt(int(index))
    node["indices"] = indices
    drawBatches.add node
  root["drawBatches"] = drawBatches
  pretty(root) & "\n"


proc writeNumericGolden*(args: seq[string]; usageText = "") =
  if args.len < 2:
    quit(usageText, QuitFailure)
  var time = 0.0
  var timeSet = false
  var animationName = ""
  var stateMachine = ""
  var inputScript = ""
  var sampleSelector = ""
  var cursor = initArgCursor(args, usageText)
  cursor.index = 2
  while not cursor.done:
    case cursor.current
    of "--t":
      time = parseFloatArg(cursor.requireValue("--t"), "--t")
      timeSet = true
    of "--animation":
      animationName = cursor.requireValue("--animation")
    of "--state-machine":
      stateMachine = cursor.requireValue("--state-machine")
    of "--input-script":
      inputScript = cursor.requireValue("--input-script")
    of "--sample":
      sampleSelector = cursor.requireValue("--sample")
    else:
      cursor.failUsage()
  if stateMachine.len != 0 or inputScript.len != 0 or sampleSelector.len != 0:
    if animationName.len != 0:
      raise newBonyLoadError(
        schemaViolation,
        "--animation cannot be combined with --state-machine, --input-script, or --sample",
      )
    if inputScript.len == 0:
      raise newBonyLoadError(schemaViolation, "golden-gen script execution requires --input-script")
    if sampleSelector.len == 0:
      raise newBonyLoadError(schemaViolation, "golden-gen script execution requires --sample")
    if timeSet:
      raise newBonyLoadError(schemaViolation, "--t cannot be combined with --input-script; use sample t values in the script")
    let parsedScript = parseInputScript(inputScript)
    if stateMachine.len != 0 or parsedScript.stateMachine.len != 0:
      let samples = executeStateMachineScript(args[0], stateMachine, inputScript, sampleSelector)
      if samples.len != 1:
        raise newBonyLoadError(schemaViolation, "--sample must select exactly one input-script sample")
      let sample = samples[0]
      writeFile(args[1], numericGoldenJson(
        sample.posedData,
        sample.sample.time,
        sample.activeSkin,
        StateMachineGolden(
          present: true,
          machine: sample.machine,
          sample: sample.sample.name,
          runtime: sample.runtime,
          evaluated: sample.evaluated,
        ),
        sample.worlds,
        sample.animationEvents,
      ))
    else:
      let setup = executeSetupPoseScript(args[0], inputScript, sampleSelector)
      writeFile(args[1], numericGoldenJson(
        setup.data,
        setup.time,
        setup.activeSkin,
        children = setup.children,
      ))
    return

  if animationName.len != 0:
    let asset = loadInputAsset(args[0])
    let clip = selectAnimation(asset.animations, animationName)
    var dataRef = new(SkeletonData)
    dataRef[] = asset.skeleton
    var animation = animationState(dataRef, 1)
    animation.setAnimation(0, clip)
    animation.update(time)
    let posed = asset.skeleton.applyRenderablePose(animation.sample())
    writeFile(args[1], numericGoldenJson(posed, time, animationEvents = animation.events))
    return

  requireSetupPoseTime(time)
  let data = loadInputSkeleton(args[0])
  writeFile(args[1], numericGoldenJson(data, time))


proc renderSetupPose*(args: seq[string]; usageText = "") =
  if args.len < 3:
    quit(usageText, QuitFailure)

  let inputPath = args[0]
  var outputPath = ""
  var time = 0.0
  var timeSet = false
  var width = 256
  var height = 256
  var stateMachine = ""
  var inputScript = ""
  var origin = "center"
  var cursor = initArgCursor(args, usageText)
  cursor.index = 1
  while not cursor.done:
    case cursor.current
    of "--out":
      outputPath = cursor.requireValue("--out")
    of "--t":
      time = parseFloatArg(cursor.requireValue("--t"), "--t")
      timeSet = true
    of "--width":
      width = parsePositiveIntArg(cursor.requireValue("--width"), "--width")
    of "--height":
      height = parsePositiveIntArg(cursor.requireValue("--height"), "--height")
    of "--state-machine":
      stateMachine = cursor.requireValue("--state-machine")
    of "--input-script":
      inputScript = cursor.requireValue("--input-script")
    of "--origin":
      origin = cursor.requireValue("--origin")
      if origin notin validOrigins:
        raise newBonyLoadError(schemaViolation, originErrMsg)
    else:
      cursor.failUsage()

  if outputPath.len == 0:
    raise newBonyLoadError(schemaViolation, "play requires --out")
  if stateMachine.len != 0 or inputScript.len != 0:
    if inputScript.len == 0:
      raise newBonyLoadError(schemaViolation, "play state-machine execution requires --input-script")
    if timeSet:
      raise newBonyLoadError(schemaViolation, "--t cannot be combined with --input-script; use sample t values in the script")
    let samples = executeStateMachineScript(inputPath, stateMachine, inputScript, "")
    let sheetWidth = width * samples.len
    var sheet = newImage(sheetWidth, height)
    sheet.fill(rgba(0, 0, 0, 0))
    for sampleIndex, sample in samples:
      # Thread the physics-advanced worlds (see executeStateMachineScript) so the
      # rendered spritesheet reflects the physics stage, matching numericGoldenJson.
      let rawBatches = buildDrawBatches(sample.posedData, sample.worlds)
      let coloredBatches = applyRenderSlotStates(rawBatches, renderSlotStates(sample.posedData, sample.evaluated.pose))
      let batches = if origin == "center": applyViewportTransform(coloredBatches, width, height) else: coloredBatches
      let image = renderSoftware(batches, width, height)
      sheet.draw(image, translate(vec2((sampleIndex * width).float32, 0.0.float32)))
    sheet.writeFile(outputPath)
    return

  requireSetupPoseTime(time)
  let data = loadInputSkeleton(inputPath)
  let rawBatches = buildDrawBatches(data)
  let batches = if origin == "center": applyViewportTransform(rawBatches, width, height) else: rawBatches
  let image = renderSoftware(batches, width, height)
  image.writeFile(outputPath)
