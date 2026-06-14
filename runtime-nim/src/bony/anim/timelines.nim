## M3 bone, slot, and event timeline data structures.

import std/[math, sets]

import bony/model

type
  TimelineCurveKind* = enum
    linearCurve,
    steppedCurve,
    bezierCurve

  TimelineCurve* = object
    kind: TimelineCurveKind
    c1x: float64
    c1y: float64
    c2x: float64
    c2y: float64

  BoneTimelineKind* = enum
    rotateTimeline,
    translateTimeline,
    translateXTimeline,
    translateYTimeline,
    scaleTimeline,
    scaleXTimeline,
    scaleYTimeline,
    shearTimeline,
    shearXTimeline,
    shearYTimeline,
    inheritTimeline

  SlotTimelineKind* = enum
    attachmentTimeline,
    rgbaTimeline,
    rgbTimeline,
    alphaTimeline,
    rgba2Timeline,
    sequenceTimeline

  SequenceMode* = enum
    sequenceOnce,
    sequenceLoop,
    sequencePingpong,
    sequenceReverse,
    sequenceHold

  ColorRgba* = object
    r*: float64
    g*: float64
    b*: float64
    a*: float64

  ColorRgba2* = object
    light*: ColorRgba
    darkR*: float64
    darkG*: float64
    darkB*: float64

  ScalarKeyframe* = object
    time*: float64
    value*: float64
    curve*: TimelineCurve

  Vector2Keyframe* = object
    time*: float64
    x*: float64
    y*: float64
    curveX*: TimelineCurve
    curveY*: TimelineCurve

  InheritKeyframe* = object
    time*: float64
    inheritRotation*: bool
    inheritScale*: bool
    inheritReflection*: bool
    transformMode*: TransformMode

  AttachmentKeyframe* = object
    time*: float64
    attachment*: string

  ColorKeyframe* = object
    time*: float64
    color*: ColorRgba
    curve*: TimelineCurve

  Color2Keyframe* = object
    time*: float64
    color*: ColorRgba2
    curve*: TimelineCurve

  SequenceKeyframe* = object
    time*: float64
    index*: uint32
    delay*: float64
    mode*: SequenceMode

  EventData* = object
    name*: string
    intValue*: int32
    floatValue*: float64
    stringValue*: string
    audioPath*: string
    volume*: float64
    balance*: float64

  EventKeyframe* = object
    time*: float64
    event*: EventData

  EventTimeline* = object
    keys: seq[EventKeyframe]

  SampledSequence* = object
    time*: float64
    baseIndex*: uint32
    index*: uint32
    delay*: float64
    mode*: SequenceMode

  BoneTimeline* = object
    target: string
    kind: BoneTimelineKind
    scalarKeys: seq[ScalarKeyframe]
    vectorKeys: seq[Vector2Keyframe]
    inheritKeys: seq[InheritKeyframe]

  SlotTimeline* = object
    target: string
    kind: SlotTimelineKind
    attachmentKeys: seq[AttachmentKeyframe]
    colorKeys: seq[ColorKeyframe]
    color2Keys: seq[Color2Keyframe]
    sequenceKeys: seq[SequenceKeyframe]

  AnimationClip* = object
    name: string
    duration: float64
    boneTimelines: seq[BoneTimeline]
    slotTimelines: seq[SlotTimeline]
    eventTimelines: seq[EventTimeline]

const
  linearTimelineCurve* = TimelineCurve(kind: linearCurve)
  steppedTimelineCurve* = TimelineCurve(kind: steppedCurve)

proc kind*(curve: TimelineCurve): TimelineCurveKind = curve.kind
proc c1x*(curve: TimelineCurve): float64 = curve.c1x
proc c1y*(curve: TimelineCurve): float64 = curve.c1y
proc c2x*(curve: TimelineCurve): float64 = curve.c2x
proc c2y*(curve: TimelineCurve): float64 = curve.c2y

proc timelineCurve*(kind: TimelineCurveKind): TimelineCurve =
  case kind
  of linearCurve:
    linearTimelineCurve
  of steppedCurve:
    steppedTimelineCurve
  of bezierCurve:
    raise newBonyLoadError(schemaViolation, "bezierCurve requires control points")

proc target*(timeline: BoneTimeline): string = timeline.target
proc kind*(timeline: BoneTimeline): BoneTimelineKind = timeline.kind
proc scalarKeys*(timeline: BoneTimeline): seq[ScalarKeyframe] = timeline.scalarKeys
proc vectorKeys*(timeline: BoneTimeline): seq[Vector2Keyframe] = timeline.vectorKeys
proc inheritKeys*(timeline: BoneTimeline): seq[InheritKeyframe] = timeline.inheritKeys

proc target*(timeline: SlotTimeline): string = timeline.target
proc kind*(timeline: SlotTimeline): SlotTimelineKind = timeline.kind
proc attachmentKeys*(timeline: SlotTimeline): seq[AttachmentKeyframe] = timeline.attachmentKeys
proc colorKeys*(timeline: SlotTimeline): seq[ColorKeyframe] = timeline.colorKeys
proc color2Keys*(timeline: SlotTimeline): seq[Color2Keyframe] = timeline.color2Keys
proc sequenceKeys*(timeline: SlotTimeline): seq[SequenceKeyframe] = timeline.sequenceKeys

proc name*(clip: AnimationClip): string = clip.name
proc duration*(clip: AnimationClip): float64 = clip.duration
proc boneTimelines*(clip: AnimationClip): seq[BoneTimeline] = clip.boneTimelines
proc slotTimelines*(clip: AnimationClip): seq[SlotTimeline] = clip.slotTimelines
proc eventTimelines*(clip: AnimationClip): seq[EventTimeline] = clip.eventTimelines
proc keys*(timeline: EventTimeline): seq[EventKeyframe] = timeline.keys

proc validateTimelineTarget(target, context: string) =
  if target.len == 0:
    raise newBonyLoadError(schemaViolation, context & " target must not be empty")


proc validateEventName(name, context: string) =
  if name.len == 0:
    raise newBonyLoadError(schemaViolation, context & " event name must not be empty")


proc quantizeTime(value: float64; context: string): float64 =
  result = quantizeF32(value, context)
  if result < 0:
    raise newBonyLoadError(schemaViolation, context & " must be non-negative")


proc quantizeChannel(value: float64; context: string): float64 =
  result = quantizeF32(value, context)
  if result < 0 or result > 1:
    raise newBonyLoadError(schemaViolation, context & " must be in 0..1")


proc bezierTimelineCurve*(c1x, c1y, c2x, c2y: float64): TimelineCurve =
  let storedC1x = quantizeF32(c1x, "curve.c1x")
  let storedC1y = quantizeF32(c1y, "curve.c1y")
  let storedC2x = quantizeF32(c2x, "curve.c2x")
  let storedC2y = quantizeF32(c2y, "curve.c2y")
  if storedC1x < 0 or storedC1x > 1:
    raise newBonyLoadError(schemaViolation, "curve.c1x must be in 0..1")
  if storedC2x < 0 or storedC2x > 1:
    raise newBonyLoadError(schemaViolation, "curve.c2x must be in 0..1")
  TimelineCurve(kind: bezierCurve, c1x: storedC1x, c1y: storedC1y, c2x: storedC2x, c2y: storedC2y)


proc ensureSorted[T](keys: openArray[T]; context: string) =
  for index in 1 ..< keys.len:
    if keys[index - 1].time >= keys[index].time:
      raise newBonyLoadError(schemaViolation, context & " keyframe times must be strictly increasing")


proc ensureEventSorted(keys: openArray[EventKeyframe]; context: string) =
  for index in 1 ..< keys.len:
    if keys[index - 1].time > keys[index].time:
      raise newBonyLoadError(schemaViolation, context & " event times must be non-decreasing")


proc requireKeys(count: int; context: string) =
  if count == 0:
    raise newBonyLoadError(schemaViolation, context & " must contain at least one keyframe")


proc validateEventData(event: EventData; context: string) =
  validateEventName(event.name, context)
  discard quantizeF32(event.floatValue, context & ".float")
  discard quantizeF32(event.volume, context & ".volume")
  discard quantizeF32(event.balance, context & ".balance")


proc validateEventTimeline(timeline: EventTimeline; context: string) =
  requireKeys(timeline.keys.len, context)
  ensureEventSorted(timeline.keys, context)
  for key in timeline.keys:
    validateEventData(key.event, context)


proc validateBoneTimeline(timeline: BoneTimeline; context: string) =
  validateTimelineTarget(timeline.target, context)
  case timeline.kind
  of inheritTimeline:
    requireKeys(timeline.inheritKeys.len, context)
    ensureSorted(timeline.inheritKeys, context)
    if timeline.scalarKeys.len != 0 or timeline.vectorKeys.len != 0:
      raise newBonyLoadError(schemaViolation, context & " has keys for the wrong timeline kind")
  of translateTimeline, scaleTimeline, shearTimeline:
    requireKeys(timeline.vectorKeys.len, context)
    ensureSorted(timeline.vectorKeys, context)
    if timeline.scalarKeys.len != 0 or timeline.inheritKeys.len != 0:
      raise newBonyLoadError(schemaViolation, context & " has keys for the wrong timeline kind")
  else:
    requireKeys(timeline.scalarKeys.len, context)
    ensureSorted(timeline.scalarKeys, context)
    if timeline.vectorKeys.len != 0 or timeline.inheritKeys.len != 0:
      raise newBonyLoadError(schemaViolation, context & " has keys for the wrong timeline kind")


proc validateSlotTimeline(timeline: SlotTimeline; context: string) =
  validateTimelineTarget(timeline.target, context)
  case timeline.kind
  of attachmentTimeline:
    requireKeys(timeline.attachmentKeys.len, context)
    ensureSorted(timeline.attachmentKeys, context)
    if timeline.colorKeys.len != 0 or timeline.color2Keys.len != 0 or timeline.sequenceKeys.len != 0:
      raise newBonyLoadError(schemaViolation, context & " has keys for the wrong timeline kind")
  of rgbaTimeline, rgbTimeline, alphaTimeline:
    requireKeys(timeline.colorKeys.len, context)
    ensureSorted(timeline.colorKeys, context)
    if timeline.attachmentKeys.len != 0 or timeline.color2Keys.len != 0 or timeline.sequenceKeys.len != 0:
      raise newBonyLoadError(schemaViolation, context & " has keys for the wrong timeline kind")
  of rgba2Timeline:
    requireKeys(timeline.color2Keys.len, context)
    ensureSorted(timeline.color2Keys, context)
    if timeline.attachmentKeys.len != 0 or timeline.colorKeys.len != 0 or timeline.sequenceKeys.len != 0:
      raise newBonyLoadError(schemaViolation, context & " has keys for the wrong timeline kind")
  of sequenceTimeline:
    requireKeys(timeline.sequenceKeys.len, context)
    ensureSorted(timeline.sequenceKeys, context)
    if timeline.attachmentKeys.len != 0 or timeline.colorKeys.len != 0 or timeline.color2Keys.len != 0:
      raise newBonyLoadError(schemaViolation, context & " has keys for the wrong timeline kind")


proc lastTime(timeline: BoneTimeline): float64 =
  validateBoneTimeline(timeline, "bone timeline")
  case timeline.kind
  of inheritTimeline:
    timeline.inheritKeys[^1].time
  of translateTimeline, scaleTimeline, shearTimeline:
    timeline.vectorKeys[^1].time
  else:
    timeline.scalarKeys[^1].time


proc lastTime(timeline: SlotTimeline): float64 =
  validateSlotTimeline(timeline, "slot timeline")
  case timeline.kind
  of attachmentTimeline:
    timeline.attachmentKeys[^1].time
  of rgbaTimeline, rgbTimeline, alphaTimeline:
    timeline.colorKeys[^1].time
  of rgba2Timeline:
    timeline.color2Keys[^1].time
  of sequenceTimeline:
    timeline.sequenceKeys[^1].time


proc lastTime(timeline: EventTimeline): float64 =
  validateEventTimeline(timeline, "event timeline")
  timeline.keys[^1].time


proc colorRgba*(r, g, b, a: float64): ColorRgba =
  ColorRgba(
    r: quantizeChannel(r, "color.r"),
    g: quantizeChannel(g, "color.g"),
    b: quantizeChannel(b, "color.b"),
    a: quantizeChannel(a, "color.a"),
  )


proc colorRgba2*(light: ColorRgba; darkR, darkG, darkB: float64): ColorRgba2 =
  ColorRgba2(
    light: light,
    darkR: quantizeChannel(darkR, "color.darkR"),
    darkG: quantizeChannel(darkG, "color.darkG"),
    darkB: quantizeChannel(darkB, "color.darkB"),
  )


proc scalarKeyframe*(time, value: float64; curve = linearTimelineCurve): ScalarKeyframe =
  ScalarKeyframe(
    time: quantizeTime(time, "key.time"),
    value: quantizeF32(value, "key.value"),
    curve: curve,
  )


proc scalarKeyframe*(time, value: float64; curve: TimelineCurveKind): ScalarKeyframe =
  scalarKeyframe(time, value, timelineCurve(curve))


proc vector2Keyframe*(
  time, x, y: float64;
  curveX = linearTimelineCurve;
  curveY = linearTimelineCurve;
): Vector2Keyframe =
  Vector2Keyframe(
    time: quantizeTime(time, "key.time"),
    x: quantizeF32(x, "key.x"),
    y: quantizeF32(y, "key.y"),
    curveX: curveX,
    curveY: curveY,
  )


proc vector2Keyframe*(
  time, x, y: float64;
  curveX: TimelineCurveKind;
  curveY = linearTimelineCurve;
): Vector2Keyframe =
  vector2Keyframe(time, x, y, timelineCurve(curveX), curveY)


proc vector2Keyframe*(
  time, x, y: float64;
  curveX = linearTimelineCurve;
  curveY: TimelineCurveKind;
): Vector2Keyframe =
  vector2Keyframe(time, x, y, curveX, timelineCurve(curveY))


proc vector2Keyframe*(
  time, x, y: float64;
  curveX: TimelineCurveKind;
  curveY: TimelineCurveKind;
): Vector2Keyframe =
  vector2Keyframe(time, x, y, timelineCurve(curveX), timelineCurve(curveY))


proc inheritKeyframe*(
  time: float64;
  inheritRotation = true;
  inheritScale = true;
  inheritReflection = true;
  transformMode = normal;
): InheritKeyframe =
  if modeForFlags(inheritRotation, inheritScale, inheritReflection) != transformMode:
    raise newBonyLoadError(schemaViolation, "inherit key transformMode does not match inherit flags")
  InheritKeyframe(
    time: quantizeTime(time, "key.time"),
    inheritRotation: inheritRotation,
    inheritScale: inheritScale,
    inheritReflection: inheritReflection,
    transformMode: transformMode,
  )


proc attachmentKeyframe*(time: float64; attachment: string): AttachmentKeyframe =
  AttachmentKeyframe(time: quantizeTime(time, "key.time"), attachment: attachment)


proc colorKeyframe*(time: float64; color: ColorRgba; curve = linearTimelineCurve): ColorKeyframe =
  ColorKeyframe(time: quantizeTime(time, "key.time"), color: color, curve: curve)


proc colorKeyframe*(time: float64; color: ColorRgba; curve: TimelineCurveKind): ColorKeyframe =
  colorKeyframe(time, color, timelineCurve(curve))


proc color2Keyframe*(time: float64; color: ColorRgba2; curve = linearTimelineCurve): Color2Keyframe =
  Color2Keyframe(time: quantizeTime(time, "key.time"), color: color, curve: curve)


proc color2Keyframe*(time: float64; color: ColorRgba2; curve: TimelineCurveKind): Color2Keyframe =
  color2Keyframe(time, color, timelineCurve(curve))


proc sequenceKeyframe*(
  time: float64;
  index: uint32;
  delay: float64;
  mode = sequenceOnce;
): SequenceKeyframe =
  let storedDelay = quantizeF32(delay, "key.delay")
  if storedDelay < 0:
    raise newBonyLoadError(schemaViolation, "key.delay must be non-negative")
  SequenceKeyframe(time: quantizeTime(time, "key.time"), index: index, delay: storedDelay, mode: mode)


proc eventData*(
  name: string;
  intValue: int32 = 0;
  floatValue = 0.0;
  stringValue = "";
  audioPath = "";
  volume = 1.0;
  balance = 0.0;
): EventData =
  result = EventData(
    name: name,
    intValue: intValue,
    floatValue: quantizeF32(floatValue, "event.float"),
    stringValue: stringValue,
    audioPath: audioPath,
    volume: quantizeF32(volume, "event.volume"),
    balance: quantizeF32(balance, "event.balance"),
  )
  validateEventData(result, "event")


proc eventKeyframe*(
  time: float64;
  event: EventData;
  intValue: int32;
  floatValue: float64;
  stringValue: string;
): EventKeyframe =
  var fired = event
  fired.intValue = intValue
  fired.floatValue = quantizeF32(floatValue, "event.float")
  fired.stringValue = stringValue
  validateEventData(fired, "event")
  EventKeyframe(time: quantizeTime(time, "key.time"), event: fired)


proc eventKeyframe*(
  time: float64;
  event: EventData;
  intValue: int32;
  floatValue: float64;
): EventKeyframe =
  eventKeyframe(time, event, intValue, floatValue, event.stringValue)


proc eventKeyframe*(time: float64; event: EventData; stringValue: string): EventKeyframe =
  eventKeyframe(time, event, event.intValue, event.floatValue, stringValue)


proc eventKeyframe*(time: float64; event: EventData): EventKeyframe =
  eventKeyframe(time, event, event.intValue, event.floatValue, event.stringValue)


proc boneScalarTimeline*(
  target: string;
  kind: BoneTimelineKind;
  keys: openArray[ScalarKeyframe];
): BoneTimeline =
  if kind notin {
    rotateTimeline,
    translateXTimeline,
    translateYTimeline,
    scaleXTimeline,
    scaleYTimeline,
    shearXTimeline,
    shearYTimeline,
  }:
    raise newBonyLoadError(schemaViolation, "bone scalar timeline kind is not scalar")
  validateTimelineTarget(target, "bone timeline")
  requireKeys(keys.len, "bone timeline")
  ensureSorted(keys, "bone timeline")
  result = BoneTimeline(target: target, kind: kind, scalarKeys: @keys)
  validateBoneTimeline(result, "bone timeline")


proc boneVectorTimeline*(
  target: string;
  kind: BoneTimelineKind;
  keys: openArray[Vector2Keyframe];
): BoneTimeline =
  if kind notin {translateTimeline, scaleTimeline, shearTimeline}:
    raise newBonyLoadError(schemaViolation, "bone vector timeline kind is not vector")
  validateTimelineTarget(target, "bone timeline")
  requireKeys(keys.len, "bone timeline")
  ensureSorted(keys, "bone timeline")
  result = BoneTimeline(target: target, kind: kind, vectorKeys: @keys)
  validateBoneTimeline(result, "bone timeline")


proc boneInheritTimeline*(target: string; keys: openArray[InheritKeyframe]): BoneTimeline =
  validateTimelineTarget(target, "bone timeline")
  requireKeys(keys.len, "bone timeline")
  ensureSorted(keys, "bone timeline")
  result = BoneTimeline(target: target, kind: inheritTimeline, inheritKeys: @keys)
  validateBoneTimeline(result, "bone timeline")


proc slotAttachmentTimeline*(target: string; keys: openArray[AttachmentKeyframe]): SlotTimeline =
  validateTimelineTarget(target, "slot timeline")
  requireKeys(keys.len, "slot timeline")
  ensureSorted(keys, "slot timeline")
  result = SlotTimeline(target: target, kind: attachmentTimeline, attachmentKeys: @keys)
  validateSlotTimeline(result, "slot timeline")


proc slotColorTimeline*(target: string; kind: SlotTimelineKind; keys: openArray[ColorKeyframe]): SlotTimeline =
  if kind notin {rgbaTimeline, rgbTimeline, alphaTimeline}:
    raise newBonyLoadError(schemaViolation, "slot color timeline kind is not rgba/rgb/alpha")
  validateTimelineTarget(target, "slot timeline")
  requireKeys(keys.len, "slot timeline")
  ensureSorted(keys, "slot timeline")
  result = SlotTimeline(target: target, kind: kind, colorKeys: @keys)
  validateSlotTimeline(result, "slot timeline")


proc slotColor2Timeline*(target: string; keys: openArray[Color2Keyframe]): SlotTimeline =
  validateTimelineTarget(target, "slot timeline")
  requireKeys(keys.len, "slot timeline")
  ensureSorted(keys, "slot timeline")
  result = SlotTimeline(target: target, kind: rgba2Timeline, color2Keys: @keys)
  validateSlotTimeline(result, "slot timeline")


proc slotSequenceTimeline*(target: string; keys: openArray[SequenceKeyframe]): SlotTimeline =
  validateTimelineTarget(target, "slot timeline")
  requireKeys(keys.len, "slot timeline")
  ensureSorted(keys, "slot timeline")
  result = SlotTimeline(target: target, kind: sequenceTimeline, sequenceKeys: @keys)
  validateSlotTimeline(result, "slot timeline")


proc eventTimeline*(keys: openArray[EventKeyframe]): EventTimeline =
  requireKeys(keys.len, "event timeline")
  ensureEventSorted(keys, "event timeline")
  result = EventTimeline(keys: @keys)
  validateEventTimeline(result, "event timeline")


proc animationClip*(
  data: SkeletonData;
  name: string;
  boneTimelines: openArray[BoneTimeline] = [];
  slotTimelines: openArray[SlotTimeline] = [];
  eventTimelines: openArray[EventTimeline] = [];
): AnimationClip =
  if name.len == 0:
    raise newBonyLoadError(schemaViolation, "animation name must not be empty")

  var boneNames = initHashSet[string]()
  var slotNames = initHashSet[string]()
  var regionNames = initHashSet[string]()
  for bone in data.bones:
    boneNames.incl(bone.name)
  for slot in data.slots:
    slotNames.incl(slot.name)
  for region in data.regions:
    regionNames.incl(region.name)

  var duration = 0.0
  for timeline in boneTimelines:
    validateBoneTimeline(timeline, "bone timeline")
    if timeline.target notin boneNames:
      raise newBonyLoadError(unknownRequiredReference, "unknown animated bone: " & timeline.target)
    duration = max(duration, timeline.lastTime)
  for timeline in slotTimelines:
    validateSlotTimeline(timeline, "slot timeline")
    if timeline.target notin slotNames:
      raise newBonyLoadError(unknownRequiredReference, "unknown animated slot: " & timeline.target)
    if timeline.kind == attachmentTimeline:
      for key in timeline.attachmentKeys:
        if key.attachment.len > 0 and key.attachment notin regionNames:
          raise newBonyLoadError(unknownRequiredReference, "unknown timeline attachment: " & key.attachment)
    duration = max(duration, timeline.lastTime)
  for timeline in eventTimelines:
    validateEventTimeline(timeline, "event timeline")
    duration = max(duration, timeline.lastTime)

  AnimationClip(
    name: name,
    duration: duration,
    boneTimelines: @boneTimelines,
    slotTimelines: @slotTimelines,
    eventTimelines: @eventTimelines,
  )


proc clamp01(value: float64): float64 =
  min(1.0, max(0.0, value))


proc cubicBezier(c1, c2, s: float64): float64 =
  let inv = 1.0 - s
  3.0 * inv * inv * s * c1 + 3.0 * inv * s * s * c2 + s * s * s


proc cubicBezierDerivative(c1, c2, s: float64): float64 =
  let inv = 1.0 - s
  3.0 * inv * inv * c1 + 6.0 * inv * s * (c2 - c1) + 3.0 * s * s * (1.0 - c2)


proc evaluate*(curve: TimelineCurve; t: float64): float64 =
  let input = clamp01(t)
  case curve.kind
  of steppedCurve:
    0.0
  of linearCurve:
    input
  of bezierCurve:
    if input == 0:
      return 0.0
    if input == 1:
      return 1.0

    var table: array[16, float64]
    for index in 0 .. 15:
      let s = float64(index) / 15.0
      table[index] = cubicBezier(curve.c1x, curve.c2x, s)

    var s = input
    for index in 0 .. 14:
      let left = table[index]
      let right = table[index + 1]
      if left <= input and input <= right and right > left:
        let segmentT = (input - left) / (right - left)
        s = (float64(index) + segmentT) / 15.0
        break

    for _ in 0 ..< 2:
      let derivative = cubicBezierDerivative(curve.c1x, curve.c2x, s)
      if derivative == 0 or classify(derivative) in {fcNan, fcInf, fcNegInf}:
        break
      s = clamp01(s - (cubicBezier(curve.c1x, curve.c2x, s) - input) / derivative)

    cubicBezier(curve.c1y, curve.c2y, s)


proc mix(curve: TimelineCurve; a, b, t: float64): float64 =
  if curve.kind == steppedCurve:
    a
  else:
    let eased = curve.evaluate(t)
    a + (b - a) * eased


proc findSpan[T](keys: openArray[T]; time: float64): int =
  if time <= keys[0].time:
    return 0
  for index in 0 ..< keys.len - 1:
    if time < keys[index + 1].time:
      return index
  keys.len - 1


proc sample*(timeline: BoneTimeline; time: float64): ScalarKeyframe =
  validateBoneTimeline(timeline, "bone timeline")
  if timeline.kind notin {
    rotateTimeline,
    translateXTimeline,
    translateYTimeline,
    scaleXTimeline,
    scaleYTimeline,
    shearXTimeline,
    shearYTimeline,
  }:
    raise newBonyLoadError(schemaViolation, "bone timeline does not contain scalar keys")
  let storedTime = quantizeTime(time, "sample.time")
  let index = findSpan(timeline.scalarKeys, storedTime)
  let current = timeline.scalarKeys[index]
  if index == timeline.scalarKeys.high or storedTime <= current.time:
    return current
  let next = timeline.scalarKeys[index + 1]
  let t = (storedTime - current.time) / (next.time - current.time)
  scalarKeyframe(storedTime, mix(current.curve, current.value, next.value, t), current.curve)


proc sampleVector*(timeline: BoneTimeline; time: float64): Vector2Keyframe =
  validateBoneTimeline(timeline, "bone timeline")
  if timeline.kind notin {translateTimeline, scaleTimeline, shearTimeline}:
    raise newBonyLoadError(schemaViolation, "bone timeline does not contain vector keys")
  let storedTime = quantizeTime(time, "sample.time")
  let index = findSpan(timeline.vectorKeys, storedTime)
  let current = timeline.vectorKeys[index]
  if index == timeline.vectorKeys.high or storedTime <= current.time:
    return current
  let next = timeline.vectorKeys[index + 1]
  let t = (storedTime - current.time) / (next.time - current.time)
  vector2Keyframe(
    storedTime,
    mix(current.curveX, current.x, next.x, t),
    mix(current.curveY, current.y, next.y, t),
    current.curveX,
    current.curveY,
  )


proc sampleInherit*(timeline: BoneTimeline; time: float64): InheritKeyframe =
  validateBoneTimeline(timeline, "bone timeline")
  if timeline.kind != inheritTimeline:
    raise newBonyLoadError(schemaViolation, "bone timeline does not contain inherit keys")
  timeline.inheritKeys[findSpan(timeline.inheritKeys, quantizeTime(time, "sample.time"))]


proc sampleAttachment*(timeline: SlotTimeline; time: float64): AttachmentKeyframe =
  validateSlotTimeline(timeline, "slot timeline")
  if timeline.kind != attachmentTimeline:
    raise newBonyLoadError(schemaViolation, "slot timeline does not contain attachment keys")
  timeline.attachmentKeys[findSpan(timeline.attachmentKeys, quantizeTime(time, "sample.time"))]


proc sampleColor*(timeline: SlotTimeline; time: float64): ColorKeyframe =
  validateSlotTimeline(timeline, "slot timeline")
  if timeline.kind notin {rgbaTimeline, rgbTimeline, alphaTimeline}:
    raise newBonyLoadError(schemaViolation, "slot timeline does not contain color keys")
  let storedTime = quantizeTime(time, "sample.time")
  let index = findSpan(timeline.colorKeys, storedTime)
  let current = timeline.colorKeys[index]
  if index == timeline.colorKeys.high or storedTime <= current.time:
    return current
  let next = timeline.colorKeys[index + 1]
  let t = (storedTime - current.time) / (next.time - current.time)
  colorKeyframe(
    storedTime,
    colorRgba(
      mix(current.curve, current.color.r, next.color.r, t),
      mix(current.curve, current.color.g, next.color.g, t),
      mix(current.curve, current.color.b, next.color.b, t),
      mix(current.curve, current.color.a, next.color.a, t),
    ),
    current.curve,
  )


proc sampleColor2*(timeline: SlotTimeline; time: float64): Color2Keyframe =
  validateSlotTimeline(timeline, "slot timeline")
  if timeline.kind != rgba2Timeline:
    raise newBonyLoadError(schemaViolation, "slot timeline does not contain rgba2 keys")
  let storedTime = quantizeTime(time, "sample.time")
  let index = findSpan(timeline.color2Keys, storedTime)
  let current = timeline.color2Keys[index]
  if index == timeline.color2Keys.high or storedTime <= current.time:
    return current
  let next = timeline.color2Keys[index + 1]
  let t = (storedTime - current.time) / (next.time - current.time)
  color2Keyframe(
    storedTime,
    colorRgba2(
      colorRgba(
        mix(current.curve, current.color.light.r, next.color.light.r, t),
        mix(current.curve, current.color.light.g, next.color.light.g, t),
        mix(current.curve, current.color.light.b, next.color.light.b, t),
        mix(current.curve, current.color.light.a, next.color.light.a, t),
      ),
      mix(current.curve, current.color.darkR, next.color.darkR, t),
      mix(current.curve, current.color.darkG, next.color.darkG, t),
      mix(current.curve, current.color.darkB, next.color.darkB, t),
    ),
    current.curve,
  )


proc sampleSequenceKey*(timeline: SlotTimeline; time: float64): SequenceKeyframe =
  validateSlotTimeline(timeline, "slot timeline")
  if timeline.kind != sequenceTimeline:
    raise newBonyLoadError(schemaViolation, "slot timeline does not contain sequence keys")
  timeline.sequenceKeys[findSpan(timeline.sequenceKeys, quantizeTime(time, "sample.time"))]


proc resolveSequenceIndex(baseIndex, elapsedFrames, frameCount: uint32; mode: SequenceMode): uint32 =
  if frameCount == 0:
    raise newBonyLoadError(schemaViolation, "sequence frameCount must be positive")
  let last = frameCount - 1
  let start = min(baseIndex, last)
  case mode
  of sequenceHold:
    start
  of sequenceOnce:
    min(start + elapsedFrames, last)
  of sequenceLoop:
    (start + elapsedFrames) mod frameCount
  of sequenceReverse:
    if elapsedFrames >= start: 0'u32 else: start - elapsedFrames
  of sequencePingpong:
    if frameCount == 1:
      0'u32
    else:
      let period = 2'u32 * last
      let position = (start + elapsedFrames) mod period
      if position <= last: position else: period - position


proc sampleSequence*(timeline: SlotTimeline; time: float64; frameCount: uint32): SampledSequence =
  let storedTime = quantizeTime(time, "sample.time")
  let key = timeline.sampleSequenceKey(storedTime)
  let elapsedFrames =
    if key.delay <= 0:
      0'u32
    else:
      uint32(floor((storedTime - key.time) / key.delay))
  SampledSequence(
    time: storedTime,
    baseIndex: key.index,
    index: resolveSequenceIndex(key.index, elapsedFrames, frameCount, key.mode),
    delay: key.delay,
    mode: key.mode,
  )
