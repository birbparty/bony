## M3 bone and slot timeline data structures.

import std/sets

import bony/model

type
  TimelineCurveKind* = enum
    linearCurve,
    steppedCurve

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
    curve*: TimelineCurveKind

  Vector2Keyframe* = object
    time*: float64
    x*: float64
    y*: float64
    curveX*: TimelineCurveKind
    curveY*: TimelineCurveKind

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
    curve*: TimelineCurveKind

  Color2Keyframe* = object
    time*: float64
    color*: ColorRgba2
    curve*: TimelineCurveKind

  SequenceKeyframe* = object
    time*: float64
    index*: uint32
    delay*: float64
    mode*: SequenceMode

  BoneTimeline* = object
    target*: string
    kind*: BoneTimelineKind
    scalarKeys*: seq[ScalarKeyframe]
    vectorKeys*: seq[Vector2Keyframe]
    inheritKeys*: seq[InheritKeyframe]

  SlotTimeline* = object
    target*: string
    kind*: SlotTimelineKind
    attachmentKeys*: seq[AttachmentKeyframe]
    colorKeys*: seq[ColorKeyframe]
    color2Keys*: seq[Color2Keyframe]
    sequenceKeys*: seq[SequenceKeyframe]

  AnimationClip* = object
    name*: string
    duration*: float64
    boneTimelines*: seq[BoneTimeline]
    slotTimelines*: seq[SlotTimeline]

proc validateTimelineTarget(target, context: string) =
  if target.len == 0:
    raise newBonyLoadError(schemaViolation, context & " target must not be empty")


proc quantizeTime(value: float64; context: string): float64 =
  result = quantizeF32(value, context)
  if result < 0:
    raise newBonyLoadError(schemaViolation, context & " must be non-negative")


proc quantizeChannel(value: float64; context: string): float64 =
  result = quantizeF32(value, context)
  if result < 0 or result > 1:
    raise newBonyLoadError(schemaViolation, context & " must be in 0..1")


proc ensureSorted[T](keys: openArray[T]; context: string) =
  for index in 1 ..< keys.len:
    if keys[index - 1].time >= keys[index].time:
      raise newBonyLoadError(schemaViolation, context & " keyframe times must be strictly increasing")


proc requireKeys(count: int; context: string) =
  if count == 0:
    raise newBonyLoadError(schemaViolation, context & " must contain at least one keyframe")


proc lastTime(timeline: BoneTimeline): float64 =
  case timeline.kind
  of inheritTimeline:
    timeline.inheritKeys[^1].time
  of translateTimeline, scaleTimeline, shearTimeline:
    timeline.vectorKeys[^1].time
  else:
    timeline.scalarKeys[^1].time


proc lastTime(timeline: SlotTimeline): float64 =
  case timeline.kind
  of attachmentTimeline:
    timeline.attachmentKeys[^1].time
  of rgbaTimeline, rgbTimeline, alphaTimeline:
    timeline.colorKeys[^1].time
  of rgba2Timeline:
    timeline.color2Keys[^1].time
  of sequenceTimeline:
    timeline.sequenceKeys[^1].time


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


proc scalarKeyframe*(time, value: float64; curve = linearCurve): ScalarKeyframe =
  ScalarKeyframe(
    time: quantizeTime(time, "key.time"),
    value: quantizeF32(value, "key.value"),
    curve: curve,
  )


proc vector2Keyframe*(
  time, x, y: float64;
  curveX = linearCurve;
  curveY = linearCurve;
): Vector2Keyframe =
  Vector2Keyframe(
    time: quantizeTime(time, "key.time"),
    x: quantizeF32(x, "key.x"),
    y: quantizeF32(y, "key.y"),
    curveX: curveX,
    curveY: curveY,
  )


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


proc colorKeyframe*(time: float64; color: ColorRgba; curve = linearCurve): ColorKeyframe =
  ColorKeyframe(time: quantizeTime(time, "key.time"), color: color, curve: curve)


proc color2Keyframe*(time: float64; color: ColorRgba2; curve = linearCurve): Color2Keyframe =
  Color2Keyframe(time: quantizeTime(time, "key.time"), color: color, curve: curve)


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
  BoneTimeline(target: target, kind: kind, scalarKeys: @keys)


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
  BoneTimeline(target: target, kind: kind, vectorKeys: @keys)


proc boneInheritTimeline*(target: string; keys: openArray[InheritKeyframe]): BoneTimeline =
  validateTimelineTarget(target, "bone timeline")
  requireKeys(keys.len, "bone timeline")
  ensureSorted(keys, "bone timeline")
  BoneTimeline(target: target, kind: inheritTimeline, inheritKeys: @keys)


proc slotAttachmentTimeline*(target: string; keys: openArray[AttachmentKeyframe]): SlotTimeline =
  validateTimelineTarget(target, "slot timeline")
  requireKeys(keys.len, "slot timeline")
  ensureSorted(keys, "slot timeline")
  SlotTimeline(target: target, kind: attachmentTimeline, attachmentKeys: @keys)


proc slotColorTimeline*(target: string; kind: SlotTimelineKind; keys: openArray[ColorKeyframe]): SlotTimeline =
  if kind notin {rgbaTimeline, rgbTimeline, alphaTimeline}:
    raise newBonyLoadError(schemaViolation, "slot color timeline kind is not rgba/rgb/alpha")
  validateTimelineTarget(target, "slot timeline")
  requireKeys(keys.len, "slot timeline")
  ensureSorted(keys, "slot timeline")
  SlotTimeline(target: target, kind: kind, colorKeys: @keys)


proc slotColor2Timeline*(target: string; keys: openArray[Color2Keyframe]): SlotTimeline =
  validateTimelineTarget(target, "slot timeline")
  requireKeys(keys.len, "slot timeline")
  ensureSorted(keys, "slot timeline")
  SlotTimeline(target: target, kind: rgba2Timeline, color2Keys: @keys)


proc slotSequenceTimeline*(target: string; keys: openArray[SequenceKeyframe]): SlotTimeline =
  validateTimelineTarget(target, "slot timeline")
  requireKeys(keys.len, "slot timeline")
  ensureSorted(keys, "slot timeline")
  SlotTimeline(target: target, kind: sequenceTimeline, sequenceKeys: @keys)


proc animationClip*(
  data: SkeletonData;
  name: string;
  boneTimelines: openArray[BoneTimeline] = [];
  slotTimelines: openArray[SlotTimeline] = [];
): AnimationClip =
  if name.len == 0:
    raise newBonyLoadError(schemaViolation, "animation name must not be empty")

  var boneNames = initHashSet[string]()
  var slotNames = initHashSet[string]()
  for bone in data.bones:
    boneNames.incl(bone.name)
  for slot in data.slots:
    slotNames.incl(slot.name)

  var duration = 0.0
  for timeline in boneTimelines:
    if timeline.target notin boneNames:
      raise newBonyLoadError(unknownRequiredReference, "unknown animated bone: " & timeline.target)
    duration = max(duration, timeline.lastTime)
  for timeline in slotTimelines:
    if timeline.target notin slotNames:
      raise newBonyLoadError(unknownRequiredReference, "unknown animated slot: " & timeline.target)
    duration = max(duration, timeline.lastTime)

  AnimationClip(
    name: name,
    duration: duration,
    boneTimelines: @boneTimelines,
    slotTimelines: @slotTimelines,
  )


proc mix(curve: TimelineCurveKind; a, b, t: float64): float64 =
  if curve == steppedCurve:
    a
  else:
    a + (b - a) * t


proc findSpan[T](keys: openArray[T]; time: float64): int =
  if time <= keys[0].time:
    return 0
  for index in 0 ..< keys.len - 1:
    if time < keys[index + 1].time:
      return index
  keys.len - 1


proc sample*(timeline: BoneTimeline; time: float64): ScalarKeyframe =
  if timeline.scalarKeys.len == 0:
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
  if timeline.vectorKeys.len == 0:
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
  if timeline.inheritKeys.len == 0:
    raise newBonyLoadError(schemaViolation, "bone timeline does not contain inherit keys")
  timeline.inheritKeys[findSpan(timeline.inheritKeys, quantizeTime(time, "sample.time"))]


proc sampleAttachment*(timeline: SlotTimeline; time: float64): AttachmentKeyframe =
  if timeline.attachmentKeys.len == 0:
    raise newBonyLoadError(schemaViolation, "slot timeline does not contain attachment keys")
  timeline.attachmentKeys[findSpan(timeline.attachmentKeys, quantizeTime(time, "sample.time"))]


proc sampleColor*(timeline: SlotTimeline; time: float64): ColorKeyframe =
  if timeline.colorKeys.len == 0:
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
  if timeline.color2Keys.len == 0:
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


proc sampleSequence*(timeline: SlotTimeline; time: float64): SequenceKeyframe =
  if timeline.sequenceKeys.len == 0:
    raise newBonyLoadError(schemaViolation, "slot timeline does not contain sequence keys")
  timeline.sequenceKeys[findSpan(timeline.sequenceKeys, quantizeTime(time, "sample.time"))]
