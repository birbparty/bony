proc boneTimelineProperty(kind: BoneTimelineKind): string =
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


proc slotTimelineProperty(kind: SlotTimelineKind): string =
  case kind
  of attachmentTimeline: "attachment"
  of rgbaTimeline: "rgba"
  of rgbTimeline: "rgb"
  of alphaTimeline: "alpha"
  of rgba2Timeline: "rgba2"
  of sequenceTimeline: "sequence"


proc curveName(kind: TimelineCurveKind): string =
  case kind
  of linearCurve: "linear"
  of steppedCurve: "stepped"
  of bezierCurve: "bezier"


proc sequenceModeName(mode: SequenceMode): string =
  case mode
  of sequenceOnce: "once"
  of sequenceLoop: "loop"
  of sequencePingpong: "pingpong"
  of sequenceReverse: "reverse"
  of sequenceHold: "hold"


proc stateMachineInputKindName(kind: StateMachineInputKind): string =
  case kind
  of boolInput: "bool"
  of numberInput: "number"
  of triggerInput: "trigger"


proc stateMachineConditionKindName(kind: StateMachineConditionKind): string =
  case kind
  of boolEqualsCondition: "boolEquals"
  of numberEqualsCondition: "numberEquals"
  of numberGreaterCondition: "numberGreater"
  of numberGreaterOrEqualCondition: "numberGreaterOrEqual"
  of numberLessCondition: "numberLess"
  of numberLessOrEqualCondition: "numberLessOrEqual"
  of triggerSetCondition: "triggerSet"


proc stateMachineListenerKindName(kind: StateMachineListenerKind): string =
  case kind
  of stateEnterListener: "stateEnter"
  of stateExitListener: "stateExit"
  of transitionListener: "transition"
  of pointerDownListener: "pointerDown"
  of pointerUpListener: "pointerUp"
  of pointerEnterListener: "pointerEnter"
  of pointerExitListener: "pointerExit"
  of pointerMoveListener: "pointerMove"


proc pointerHelperTargetKindName(kind: PointerHelperTargetKind): string =
  case kind
  of pointHelperTarget: "point"
  of boundingBoxHelperTarget: "boundingBox"


proc appendCurveFields(result: var string; curve: TimelineCurve; indent: int; first: var bool; key = "curve") =
  result.addStringField(key, curveName(curve.kind), indent, first)
  if curve.kind == bezierCurve:
    result.addNumberField("c1x", curve.c1x, indent, first)
    result.addNumberField("c1y", curve.c1y, indent, first)
    result.addNumberField("c2x", curve.c2x, indent, first)
    result.addNumberField("c2y", curve.c2y, indent, first)


proc appendAnimationsJson(result: var string; animations: openArray[AnimationClip]; setupSlots: openArray[SlotData] = []; indent = 1) =
  result.addIndent(indent)
  result.add "\"animations\": ["
  if animations.len > 0:
    result.add "\n"
    for animIndex, anim in animations:
      if animIndex > 0:
        result.add ",\n"
      result.addIndent(indent + 1)
      result.add "{\n"
      var first = true
      result.addStringField("name", anim.name, indent + 2, first)
      if anim.boneTimelines.len > 0:
        result.addFieldPrefix("boneTimelines", indent + 2, first)
        result.add "[\n"
        for tlIndex, timeline in anim.boneTimelines:
          if tlIndex > 0:
            result.add ",\n"
          result.addIndent(indent + 3)
          result.add "{\n"
          var tlFirst = true
          result.addStringField("bone", timeline.target, indent + 4, tlFirst)
          result.addStringField("property", boneTimelineProperty(timeline.kind), indent + 4, tlFirst)
          result.addFieldPrefix("keyframes", indent + 4, tlFirst)
          result.add "[\n"
          case timeline.kind
          of inheritTimeline:
            for keyIndex, key in timeline.inheritKeys:
              if keyIndex > 0: result.add ",\n"
              result.addIndent(indent + 5)
              result.add "{\n"
              var kFirst = true
              result.addNumberField("t", key.time, indent + 6, kFirst)
              result.addBoolField("inheritRotation", key.inheritRotation, indent + 6, kFirst)
              result.addBoolField("inheritScale", key.inheritScale, indent + 6, kFirst)
              result.addBoolField("inheritReflection", key.inheritReflection, indent + 6, kFirst)
              result.addStringField("transformMode", transformModeName(key.transformMode), indent + 6, kFirst)
              result.add "\n"
              result.addIndent(indent + 5)
              result.add "}"
          of translateTimeline, scaleTimeline, shearTimeline:
            for keyIndex, key in timeline.vectorKeys:
              if keyIndex > 0: result.add ",\n"
              result.addIndent(indent + 5)
              result.add "{\n"
              var kFirst = true
              result.addNumberField("t", key.time, indent + 6, kFirst)
              result.addNumberField("x", key.x, indent + 6, kFirst)
              result.addNumberField("y", key.y, indent + 6, kFirst)
              result.appendCurveFields(key.curveX, indent + 6, kFirst, "curveX")
              result.appendCurveFields(key.curveY, indent + 6, kFirst, "curveY")
              result.add "\n"
              result.addIndent(indent + 5)
              result.add "}"
          else:
            for keyIndex, key in timeline.scalarKeys:
              if keyIndex > 0: result.add ",\n"
              result.addIndent(indent + 5)
              result.add "{\n"
              var kFirst = true
              result.addNumberField("t", key.time, indent + 6, kFirst)
              result.addNumberField("value", key.value, indent + 6, kFirst)
              result.appendCurveFields(key.curve, indent + 6, kFirst)
              result.add "\n"
              result.addIndent(indent + 5)
              result.add "}"
          result.add "\n"
          result.addIndent(indent + 4)
          result.add "]\n"
          result.addIndent(indent + 3)
          result.add "}"
        result.add "\n"
        result.addIndent(indent + 2)
        result.add "]"
      if anim.slotTimelines.len > 0:
        result.addFieldPrefix("slotTimelines", indent + 2, first)
        result.add "[\n"
        for tlIndex, timeline in anim.slotTimelines:
          if tlIndex > 0:
            result.add ",\n"
          result.addIndent(indent + 3)
          result.add "{\n"
          var tlFirst = true
          result.addStringField("slot", timeline.target, indent + 4, tlFirst)
          result.addStringField("property", slotTimelineProperty(timeline.kind), indent + 4, tlFirst)
          result.addFieldPrefix("keyframes", indent + 4, tlFirst)
          result.add "[\n"
          case timeline.kind
          of attachmentTimeline:
            for keyIndex, key in timeline.attachmentKeys:
              if keyIndex > 0: result.add ",\n"
              result.addIndent(indent + 5)
              result.add "{\n"
              var kFirst = true
              result.addNumberField("t", key.time, indent + 6, kFirst)
              if key.attachment.len > 0:
                result.addStringField("attachment", key.attachment, indent + 6, kFirst)
              result.add "\n"
              result.addIndent(indent + 5)
              result.add "}"
          of rgbaTimeline, rgbTimeline, alphaTimeline:
            for keyIndex, key in timeline.colorKeys:
              if keyIndex > 0: result.add ",\n"
              result.addIndent(indent + 5)
              result.add "{\n"
              var kFirst = true
              result.addNumberField("t", key.time, indent + 6, kFirst)
              result.addNumberField("r", key.color.r, indent + 6, kFirst)
              result.addNumberField("g", key.color.g, indent + 6, kFirst)
              result.addNumberField("b", key.color.b, indent + 6, kFirst)
              result.addNumberField("a", key.color.a, indent + 6, kFirst)
              result.appendCurveFields(key.curve, indent + 6, kFirst)
              result.add "\n"
              result.addIndent(indent + 5)
              result.add "}"
          of rgba2Timeline:
            for keyIndex, key in timeline.color2Keys:
              if keyIndex > 0: result.add ",\n"
              result.addIndent(indent + 5)
              result.add "{\n"
              var kFirst = true
              result.addNumberField("t", key.time, indent + 6, kFirst)
              result.addNumberField("r", key.color.light.r, indent + 6, kFirst)
              result.addNumberField("g", key.color.light.g, indent + 6, kFirst)
              result.addNumberField("b", key.color.light.b, indent + 6, kFirst)
              result.addNumberField("a", key.color.light.a, indent + 6, kFirst)
              result.addNumberField("dr", key.color.darkR, indent + 6, kFirst)
              result.addNumberField("dg", key.color.darkG, indent + 6, kFirst)
              result.addNumberField("db", key.color.darkB, indent + 6, kFirst)
              result.appendCurveFields(key.curve, indent + 6, kFirst)
              result.add "\n"
              result.addIndent(indent + 5)
              result.add "}"
          of sequenceTimeline:
            for keyIndex, key in timeline.sequenceKeys:
              if keyIndex > 0: result.add ",\n"
              result.addIndent(indent + 5)
              result.add "{\n"
              var kFirst = true
              result.addNumberField("t", key.time, indent + 6, kFirst)
              result.addIntField("index", int(key.index), indent + 6, kFirst)
              result.addNumberField("delay", key.delay, indent + 6, kFirst)
              result.addStringField("mode", sequenceModeName(key.mode), indent + 6, kFirst)
              result.add "\n"
              result.addIndent(indent + 5)
              result.add "}"
          result.add "\n"
          result.addIndent(indent + 4)
          result.add "]\n"
          result.addIndent(indent + 3)
          result.add "}"
        result.add "\n"
        result.addIndent(indent + 2)
        result.add "]"
      if anim.hasDrawOrderTimeline:
        let timeline = anim.drawOrderTimeline
        result.addFieldPrefix("drawOrderTimeline", indent + 2, first)
        result.add "{\n"
        var tlFirst = true
        result.addFieldPrefix("keyframes", indent + 3, tlFirst)
        result.add "[\n"
        for keyIndex, key in timeline.keys:
          if keyIndex > 0: result.add ",\n"
          result.addIndent(indent + 4)
          result.add "{\n"
          var kFirst = true
          result.addNumberField("t", key.time, indent + 5, kFirst)
          result.addFieldPrefix("offsets", indent + 5, kFirst)
          result.add "["
          let offsets =
            if setupSlots.len > 0: drawOrderOffsetsInSetupOrder(key, setupSlots)
            else: key.offsets
          if offsets.len > 0:
            result.add "\n"
            for offsetIndex, offset in offsets:
              if offsetIndex > 0: result.add ",\n"
              result.addIndent(indent + 6)
              result.add "{\n"
              var oFirst = true
              result.addStringField("slot", offset.slot, indent + 7, oFirst)
              result.addIntField("offset", offset.offset, indent + 7, oFirst)
              result.add "\n"
              result.addIndent(indent + 6)
              result.add "}"
            result.add "\n"
            result.addIndent(indent + 5)
          result.add "]\n"
          result.addIndent(indent + 4)
          result.add "}"
        result.add "\n"
        result.addIndent(indent + 3)
        result.add "]\n"
        result.addIndent(indent + 2)
        result.add "}"
      if anim.deformTimelines.len > 0:
        result.addFieldPrefix("deformTimelines", indent + 2, first)
        result.add "[\n"
        for tlIndex, timeline in anim.deformTimelines:
          if tlIndex > 0:
            result.add ",\n"
          result.addIndent(indent + 3)
          result.add "{\n"
          var tlFirst = true
          result.addStringField("skin", timeline.skin, indent + 4, tlFirst)
          result.addStringField("slot", timeline.slot, indent + 4, tlFirst)
          result.addStringField("attachment", timeline.attachment, indent + 4, tlFirst)
          result.addIntField("vertexCount", timeline.vertexCount, indent + 4, tlFirst)
          result.addFieldPrefix("keyframes", indent + 4, tlFirst)
          result.add "[\n"
          for keyIndex, key in timeline.keys:
            if keyIndex > 0: result.add ",\n"
            result.addIndent(indent + 5)
            result.add "{\n"
            var kFirst = true
            result.addNumberField("t", key.time, indent + 6, kFirst)
            result.addIntField("offset", int(key.offset), indent + 6, kFirst)
            result.addFieldPrefix("deltas", indent + 6, kFirst)
            result.add "[\n"
            for dIndex, delta in key.deltas:
              if dIndex > 0: result.add ",\n"
              result.addIndent(indent + 7)
              result.add "{\n"
              var dFirst = true
              result.addNumberField("x", delta.x, indent + 8, dFirst)
              result.addNumberField("y", delta.y, indent + 8, dFirst)
              result.add "\n"
              result.addIndent(indent + 7)
              result.add "}"
            result.add "\n"
            result.addIndent(indent + 6)
            result.add "]"
            result.appendCurveFields(key.curve, indent + 6, kFirst)
            result.add "\n"
            result.addIndent(indent + 5)
            result.add "}"
          result.add "\n"
          result.addIndent(indent + 4)
          result.add "]\n"
          result.addIndent(indent + 3)
          result.add "}"
        result.add "\n"
        result.addIndent(indent + 2)
        result.add "]"
      if anim.eventTimelines.len > 0:
        result.addFieldPrefix("eventTimelines", indent + 2, first)
        result.add "[\n"
        for tlIndex, timeline in anim.eventTimelines:
          if tlIndex > 0:
            result.add ",\n"
          result.addIndent(indent + 3)
          result.add "{\n"
          var tlFirst = true
          result.addFieldPrefix("keyframes", indent + 4, tlFirst)
          result.add "[\n"
          for keyIndex, key in timeline.keys:
            if keyIndex > 0: result.add ",\n"
            result.addIndent(indent + 5)
            result.add "{\n"
            var kFirst = true
            let event = key.event
            result.addNumberField("t", key.time, indent + 6, kFirst)
            result.addStringField("name", event.name, indent + 6, kFirst)
            if event.intValue != 0:
              result.addIntField("intValue", int(event.intValue), indent + 6, kFirst)
            if event.floatValue != 0.0:
              result.addNumberField("floatValue", event.floatValue, indent + 6, kFirst)
            if event.stringValue.len > 0:
              result.addStringField("stringValue", event.stringValue, indent + 6, kFirst)
            if event.audioPath.len > 0:
              result.addStringField("audioPath", event.audioPath, indent + 6, kFirst)
            if event.volume != 1.0:
              result.addNumberField("volume", event.volume, indent + 6, kFirst)
            if event.balance != 0.0:
              result.addNumberField("balance", event.balance, indent + 6, kFirst)
            result.add "\n"
            result.addIndent(indent + 5)
            result.add "}"
          result.add "\n"
          result.addIndent(indent + 4)
          result.add "]\n"
          result.addIndent(indent + 3)
          result.add "}"
        result.add "\n"
        result.addIndent(indent + 2)
        result.add "]"
      result.add "\n"
      result.addIndent(indent + 1)
      result.add "}"
    result.add "\n"
    result.addIndent(indent)
  result.add "]"

proc appendStateMachinesJson(result: var string; machines: openArray[StateMachine]; indent = 1) =
  result.addIndent(indent)
  result.add "\"stateMachines\": ["
  if machines.len > 0:
    result.add "\n"
    for machineIndex, machine in machines:
      if machineIndex > 0: result.add ",\n"
      result.addIndent(indent + 1)
      result.add "{\n"
      var first = true
      result.addStringField("name", machine.name, indent + 2, first)
      if machine.inputs.len > 0:
        result.addFieldPrefix("inputs", indent + 2, first)
        result.add "[\n"
        for inputIndex, input in machine.inputs:
          if inputIndex > 0: result.add ",\n"
          result.addIndent(indent + 3)
          result.add "{\n"
          var iFirst = true
          result.addStringField("name", input.name, indent + 4, iFirst)
          result.addStringField("kind", stateMachineInputKindName(input.kind), indent + 4, iFirst)
          case input.kind
          of boolInput:
            if input.defaultBool:
              result.addBoolField("default", input.defaultBool, indent + 4, iFirst)
          of numberInput:
            if input.defaultNumber != 0.0:
              result.addNumberField("default", input.defaultNumber, indent + 4, iFirst)
          of triggerInput:
            discard
          result.add "\n"
          result.addIndent(indent + 3)
          result.add "}"
        result.add "\n"
        result.addIndent(indent + 2)
        result.add "]"
      result.addFieldPrefix("layers", indent + 2, first)
      result.add "[\n"
      for layerIndex, layer in machine.layers:
        if layerIndex > 0: result.add ",\n"
        result.addIndent(indent + 3)
        result.add "{\n"
        var lFirst = true
        result.addStringField("name", layer.name, indent + 4, lFirst)
        if layer.initialState != layer.states[0].name:
          result.addStringField("initialState", layer.initialState, indent + 4, lFirst)
        result.addFieldPrefix("states", indent + 4, lFirst)
        result.add "[\n"
        for stateIndex, state in layer.states:
          if stateIndex > 0: result.add ",\n"
          result.addIndent(indent + 5)
          result.add "{\n"
          var sFirst = true
          result.addStringField("name", state.name, indent + 6, sFirst)
          case state.kind
          of clipState:
            result.addStringField("kind", "clip", indent + 6, sFirst)
            result.addStringField("clip", state.clip.name, indent + 6, sFirst)
            if state.loop:
              result.addBoolField("loop", state.loop, indent + 6, sFirst)
          of blend1DState:
            result.addStringField("kind", "blend1d", indent + 6, sFirst)
            result.addStringField("blendInput", state.blendInput, indent + 6, sFirst)
            result.addFieldPrefix("blendClips", indent + 6, sFirst)
            result.add "[\n"
            for clipIndex, clip in state.blendClips:
              if clipIndex > 0: result.add ",\n"
              result.addIndent(indent + 7)
              result.add "{\n"
              var cFirst = true
              result.addStringField("clip", clip.clip.name, indent + 8, cFirst)
              result.addNumberField("value", clip.value, indent + 8, cFirst)
              if clip.loop:
                result.addBoolField("loop", clip.loop, indent + 8, cFirst)
              result.add "\n"
              result.addIndent(indent + 7)
              result.add "}"
            result.add "\n"
            result.addIndent(indent + 6)
            result.add "]"
          result.add "\n"
          result.addIndent(indent + 5)
          result.add "}"
        result.add "\n"
        result.addIndent(indent + 4)
        result.add "]"
        if layer.transitions.len > 0:
          result.addFieldPrefix("transitions", indent + 4, lFirst)
          result.add "[\n"
          for trIndex, tr in layer.transitions:
            if trIndex > 0: result.add ",\n"
            result.addIndent(indent + 5)
            result.add "{\n"
            var tFirst = true
            result.addStringField("fromState", tr.fromState, indent + 6, tFirst)
            result.addStringField("toState", tr.toState, indent + 6, tFirst)
            result.addFieldPrefix("conditions", indent + 6, tFirst)
            result.add "[\n"
            for condIndex, cond in tr.conditions:
              if condIndex > 0: result.add ",\n"
              result.addIndent(indent + 7)
              result.add "{\n"
              var cFirst = true
              result.addStringField("input", cond.input, indent + 8, cFirst)
              result.addStringField("kind", stateMachineConditionKindName(cond.kind), indent + 8, cFirst)
              case cond.kind
              of boolEqualsCondition:
                if not cond.boolValue:
                  result.addBoolField("value", cond.boolValue, indent + 8, cFirst)
              of numberEqualsCondition, numberGreaterCondition, numberGreaterOrEqualCondition, numberLessCondition, numberLessOrEqualCondition:
                result.addNumberField("value", cond.numberValue, indent + 8, cFirst)
              of triggerSetCondition:
                discard
              result.add "\n"
              result.addIndent(indent + 7)
              result.add "}"
            result.add "\n"
            result.addIndent(indent + 6)
            result.add "]\n"
            result.addIndent(indent + 5)
            result.add "}"
          result.add "\n"
          result.addIndent(indent + 4)
          result.add "]"
        result.add "\n"
        result.addIndent(indent + 3)
        result.add "}"
      result.add "\n"
      result.addIndent(indent + 2)
      result.add "]"
      if machine.listeners.len > 0:
        result.addFieldPrefix("listeners", indent + 2, first)
        result.add "[\n"
        for listenerIndex, listener in machine.listeners:
          if listenerIndex > 0: result.add ",\n"
          result.addIndent(indent + 3)
          result.add "{\n"
          var lFirst = true
          result.addStringField("name", listener.name, indent + 4, lFirst)
          result.addStringField("kind", stateMachineListenerKindName(listener.kind), indent + 4, lFirst)
          case listener.kind
          of stateEnterListener, stateExitListener, transitionListener:
            result.addStringField("layer", listener.layer, indent + 4, lFirst)
            if listener.fromState.len > 0:
              result.addStringField("fromState", listener.fromState, indent + 4, lFirst)
            if listener.toState.len > 0:
              result.addStringField("toState", listener.toState, indent + 4, lFirst)
          of pointerDownListener, pointerUpListener, pointerEnterListener, pointerExitListener, pointerMoveListener:
            result.addStringField("slot", listener.slot, indent + 4, lFirst)
            result.addStringField("targetKind", pointerHelperTargetKindName(listener.targetKind), indent + 4, lFirst)
            result.addStringField("target", listener.target, indent + 4, lFirst)
            if listener.targetKind == pointHelperTarget:
              result.addNumberField("hitRadius", listener.hitRadius, indent + 4, lFirst)
            result.addStringField("input", listener.input, indent + 4, lFirst)
            if listener.inputKind == boolInput:
              result.addBoolField("value", listener.boolValue, indent + 4, lFirst)
            elif listener.inputKind == numberInput:
              result.addNumberField("value", listener.numberValue, indent + 4, lFirst)
          result.add "\n"
          result.addIndent(indent + 3)
          result.add "}"
        result.add "\n"
        result.addIndent(indent + 2)
        result.add "]"
      result.add "\n"
      result.addIndent(indent + 1)
      result.add "}"
    result.add "\n"
    result.addIndent(indent)
  result.add "]"
