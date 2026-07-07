## M3 bone, slot, and event timeline data structures.

import std/[math, sets, tables]

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
    case kind: BoneTimelineKind
    of inheritTimeline:
      inheritKeys: seq[InheritKeyframe]
    of translateTimeline, scaleTimeline, shearTimeline:
      vectorKeys: seq[Vector2Keyframe]
    else:
      scalarKeys: seq[ScalarKeyframe]

  SlotTimeline* = object
    target: string
    case kind: SlotTimelineKind
    of attachmentTimeline:
      attachmentKeys: seq[AttachmentKeyframe]
    of rgbaTimeline, rgbTimeline, alphaTimeline:
      colorKeys: seq[ColorKeyframe]
    of rgba2Timeline:
      color2Keys: seq[Color2Keyframe]
    of sequenceTimeline:
      sequenceKeys: seq[SequenceKeyframe]

  DeformKeyframe* = object
    ## One keyframe of a deform timeline: a sparse `offset`-anchored run of
    ## per-vertex `deltas` at `time`, interpolated with `curve`. Relocated here
    ## from mesh/deform.nim (it carries a same-module `TimelineCurve`) so a clip
    ## can own `DeformTimeline`s without a timelines<->deform import cycle.
    time*: float64
    offset*: uint32
    deltas*: seq[MeshDelta]
    curve*: TimelineCurve

  DeformTimeline* = object
    ## A clip-owned per-vertex mesh-offset (FFD) timeline targeting the mesh
    ## attachment named `attachment` on slot `slot` under skin `skin`. See
    ## docs/deform-timeline-contract.md.
    skin*: string
    slot*: string
    attachment*: string
    vertexCount*: int
    keys*: seq[DeformKeyframe]

  AnimationClip* = object
    name: string
    duration: float64
    boneTimelines: seq[BoneTimeline]
    slotTimelines: seq[SlotTimeline]
    eventTimelines: seq[EventTimeline]
    deformTimelines: seq[DeformTimeline]

template isScalarBoneTimeline(kind: BoneTimelineKind): bool =
  kind in {
    rotateTimeline,
    translateXTimeline,
    translateYTimeline,
    scaleXTimeline,
    scaleYTimeline,
    shearXTimeline,
    shearYTimeline,
  }

template isVectorBoneTimeline(kind: BoneTimelineKind): bool =
  kind in {translateTimeline, scaleTimeline, shearTimeline}

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
proc scalarKeys*(timeline: BoneTimeline): seq[ScalarKeyframe] =
  if timeline.kind.isScalarBoneTimeline: timeline.scalarKeys else: @[]

proc vectorKeys*(timeline: BoneTimeline): seq[Vector2Keyframe] =
  if timeline.kind.isVectorBoneTimeline: timeline.vectorKeys else: @[]

proc inheritKeys*(timeline: BoneTimeline): seq[InheritKeyframe] =
  if timeline.kind == inheritTimeline: timeline.inheritKeys else: @[]

proc target*(timeline: SlotTimeline): string = timeline.target
proc kind*(timeline: SlotTimeline): SlotTimelineKind = timeline.kind
proc attachmentKeys*(timeline: SlotTimeline): seq[AttachmentKeyframe] =
  if timeline.kind == attachmentTimeline: timeline.attachmentKeys else: @[]

proc colorKeys*(timeline: SlotTimeline): seq[ColorKeyframe] =
  if timeline.kind in {rgbaTimeline, rgbTimeline, alphaTimeline}: timeline.colorKeys else: @[]

proc color2Keys*(timeline: SlotTimeline): seq[Color2Keyframe] =
  if timeline.kind == rgba2Timeline: timeline.color2Keys else: @[]

proc sequenceKeys*(timeline: SlotTimeline): seq[SequenceKeyframe] =
  if timeline.kind == sequenceTimeline: timeline.sequenceKeys else: @[]

proc name*(clip: AnimationClip): string = clip.name
proc duration*(clip: AnimationClip): float64 = clip.duration
proc boneTimelines*(clip: AnimationClip): seq[BoneTimeline] = clip.boneTimelines
proc slotTimelines*(clip: AnimationClip): seq[SlotTimeline] = clip.slotTimelines
proc eventTimelines*(clip: AnimationClip): seq[EventTimeline] = clip.eventTimelines
proc deformTimelines*(clip: AnimationClip): seq[DeformTimeline] = clip.deformTimelines
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
  of translateTimeline, scaleTimeline, shearTimeline:
    requireKeys(timeline.vectorKeys.len, context)
    ensureSorted(timeline.vectorKeys, context)
  else:
    requireKeys(timeline.scalarKeys.len, context)
    ensureSorted(timeline.scalarKeys, context)


proc validateSlotTimeline(timeline: SlotTimeline; context: string) =
  validateTimelineTarget(timeline.target, context)
  case timeline.kind
  of attachmentTimeline:
    requireKeys(timeline.attachmentKeys.len, context)
    ensureSorted(timeline.attachmentKeys, context)
  of rgbaTimeline, rgbTimeline, alphaTimeline:
    requireKeys(timeline.colorKeys.len, context)
    ensureSorted(timeline.colorKeys, context)
  of rgba2Timeline:
    requireKeys(timeline.color2Keys.len, context)
    ensureSorted(timeline.color2Keys, context)
  of sequenceTimeline:
    requireKeys(timeline.sequenceKeys.len, context)
    ensureSorted(timeline.sequenceKeys, context)


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


proc boneTimeline*(
  target: string;
  kind: BoneTimelineKind;
  keys: openArray[ScalarKeyframe];
): BoneTimeline =
  if not kind.isScalarBoneTimeline:
    raise newBonyLoadError(schemaViolation, "bone scalar timeline kind is not scalar")
  validateTimelineTarget(target, "bone timeline")
  requireKeys(keys.len, "bone timeline")
  ensureSorted(keys, "bone timeline")
  case kind
  of rotateTimeline:
    result = BoneTimeline(target: target, kind: rotateTimeline, scalarKeys: @keys)
  of translateXTimeline:
    result = BoneTimeline(target: target, kind: translateXTimeline, scalarKeys: @keys)
  of translateYTimeline:
    result = BoneTimeline(target: target, kind: translateYTimeline, scalarKeys: @keys)
  of scaleXTimeline:
    result = BoneTimeline(target: target, kind: scaleXTimeline, scalarKeys: @keys)
  of scaleYTimeline:
    result = BoneTimeline(target: target, kind: scaleYTimeline, scalarKeys: @keys)
  of shearXTimeline:
    result = BoneTimeline(target: target, kind: shearXTimeline, scalarKeys: @keys)
  of shearYTimeline:
    result = BoneTimeline(target: target, kind: shearYTimeline, scalarKeys: @keys)
  else:
    raise newBonyLoadError(schemaViolation, "bone scalar timeline kind is not scalar")
  validateBoneTimeline(result, "bone timeline")


proc boneTimeline*(
  target: string;
  kind: BoneTimelineKind;
  keys: openArray[Vector2Keyframe];
): BoneTimeline =
  if not kind.isVectorBoneTimeline:
    raise newBonyLoadError(schemaViolation, "bone vector timeline kind is not vector")
  validateTimelineTarget(target, "bone timeline")
  requireKeys(keys.len, "bone timeline")
  ensureSorted(keys, "bone timeline")
  case kind
  of translateTimeline:
    result = BoneTimeline(target: target, kind: translateTimeline, vectorKeys: @keys)
  of scaleTimeline:
    result = BoneTimeline(target: target, kind: scaleTimeline, vectorKeys: @keys)
  of shearTimeline:
    result = BoneTimeline(target: target, kind: shearTimeline, vectorKeys: @keys)
  else:
    raise newBonyLoadError(schemaViolation, "bone vector timeline kind is not vector")
  validateBoneTimeline(result, "bone timeline")


proc boneTimeline*(
  target: string;
  kind: BoneTimelineKind;
  keys: openArray[InheritKeyframe];
): BoneTimeline =
  if kind != inheritTimeline:
    raise newBonyLoadError(schemaViolation, "bone inherit timeline kind is not inherit")
  validateTimelineTarget(target, "bone timeline")
  requireKeys(keys.len, "bone timeline")
  ensureSorted(keys, "bone timeline")
  result = BoneTimeline(target: target, kind: inheritTimeline, inheritKeys: @keys)
  validateBoneTimeline(result, "bone timeline")


proc boneScalarTimeline*(
  target: string;
  kind: BoneTimelineKind;
  keys: openArray[ScalarKeyframe];
): BoneTimeline =
  boneTimeline(target, kind, keys)


proc boneVectorTimeline*(
  target: string;
  kind: BoneTimelineKind;
  keys: openArray[Vector2Keyframe];
): BoneTimeline =
  boneTimeline(target, kind, keys)


proc boneInheritTimeline*(target: string; keys: openArray[InheritKeyframe]): BoneTimeline =
  boneTimeline(target, inheritTimeline, keys)


proc slotTimeline*(
  target: string;
  kind: SlotTimelineKind;
  keys: openArray[AttachmentKeyframe];
): SlotTimeline =
  if kind != attachmentTimeline:
    raise newBonyLoadError(schemaViolation, "slot attachment timeline kind is not attachment")
  validateTimelineTarget(target, "slot timeline")
  requireKeys(keys.len, "slot timeline")
  ensureSorted(keys, "slot timeline")
  result = SlotTimeline(target: target, kind: attachmentTimeline, attachmentKeys: @keys)
  validateSlotTimeline(result, "slot timeline")


proc slotTimeline*(target: string; kind: SlotTimelineKind; keys: openArray[ColorKeyframe]): SlotTimeline =
  if kind notin {rgbaTimeline, rgbTimeline, alphaTimeline}:
    raise newBonyLoadError(schemaViolation, "slot color timeline kind is not rgba/rgb/alpha")
  validateTimelineTarget(target, "slot timeline")
  requireKeys(keys.len, "slot timeline")
  ensureSorted(keys, "slot timeline")
  case kind
  of rgbaTimeline:
    result = SlotTimeline(target: target, kind: rgbaTimeline, colorKeys: @keys)
  of rgbTimeline:
    result = SlotTimeline(target: target, kind: rgbTimeline, colorKeys: @keys)
  of alphaTimeline:
    result = SlotTimeline(target: target, kind: alphaTimeline, colorKeys: @keys)
  else:
    raise newBonyLoadError(schemaViolation, "slot color timeline kind is not rgba/rgb/alpha")
  validateSlotTimeline(result, "slot timeline")


proc slotTimeline*(
  target: string;
  kind: SlotTimelineKind;
  keys: openArray[Color2Keyframe];
): SlotTimeline =
  if kind != rgba2Timeline:
    raise newBonyLoadError(schemaViolation, "slot rgba2 timeline kind is not rgba2")
  validateTimelineTarget(target, "slot timeline")
  requireKeys(keys.len, "slot timeline")
  ensureSorted(keys, "slot timeline")
  result = SlotTimeline(target: target, kind: rgba2Timeline, color2Keys: @keys)
  validateSlotTimeline(result, "slot timeline")


proc slotTimeline*(
  target: string;
  kind: SlotTimelineKind;
  keys: openArray[SequenceKeyframe];
): SlotTimeline =
  if kind != sequenceTimeline:
    raise newBonyLoadError(schemaViolation, "slot sequence timeline kind is not sequence")
  validateTimelineTarget(target, "slot timeline")
  requireKeys(keys.len, "slot timeline")
  ensureSorted(keys, "slot timeline")
  result = SlotTimeline(target: target, kind: sequenceTimeline, sequenceKeys: @keys)
  validateSlotTimeline(result, "slot timeline")


proc slotAttachmentTimeline*(target: string; keys: openArray[AttachmentKeyframe]): SlotTimeline =
  slotTimeline(target, attachmentTimeline, keys)


proc slotColorTimeline*(target: string; kind: SlotTimelineKind; keys: openArray[ColorKeyframe]): SlotTimeline =
  slotTimeline(target, kind, keys)


proc slotColor2Timeline*(target: string; keys: openArray[Color2Keyframe]): SlotTimeline =
  slotTimeline(target, rgba2Timeline, keys)


proc slotSequenceTimeline*(target: string; keys: openArray[SequenceKeyframe]): SlotTimeline =
  slotTimeline(target, sequenceTimeline, keys)


proc eventTimeline*(keys: openArray[EventKeyframe]): EventTimeline =
  requireKeys(keys.len, "event timeline")
  ensureEventSorted(keys, "event timeline")
  result = EventTimeline(keys: @keys)
  validateEventTimeline(result, "event timeline")


proc deformKeyframe*(
  time: float64;
  offset: uint32;
  deltas: openArray[MeshDelta];
  curve = linearTimelineCurve;
): DeformKeyframe =
  DeformKeyframe(
    time: quantizeF32(time, "deform.key.time"),
    offset: offset,
    deltas: @deltas,
    curve: curve,
  )


proc deformKeyframe*(
  time: float64;
  offset: uint32;
  deltas: openArray[MeshDelta];
  curve: TimelineCurveKind;
): DeformKeyframe =
  deformKeyframe(time, offset, deltas, timelineCurve(curve))


proc validateDeformKey(key: DeformKeyframe; vertexCount: int) =
  let storedTime = quantizeF32(key.time, "deform.key.time")
  if storedTime < 0:
    raise newBonyLoadError(schemaViolation, "deform key time must be non-negative")
  if key.deltas.len == 0:
    raise newBonyLoadError(schemaViolation, "deform key must contain at least one delta")
  if int(key.offset) + key.deltas.len > vertexCount:
    raise newBonyLoadError(schemaViolation, "deform key range exceeds mesh vertex count")
  for delta in key.deltas:
    discard quantizeF32(delta.x, "deform.delta.x")
    discard quantizeF32(delta.y, "deform.delta.y")


proc validateDeformTimeline*(timeline: DeformTimeline) =
  if timeline.skin.len == 0:
    raise newBonyLoadError(schemaViolation, "deform timeline skin must not be empty")
  if timeline.slot.len == 0:
    raise newBonyLoadError(schemaViolation, "deform timeline slot must not be empty")
  if timeline.attachment.len == 0:
    raise newBonyLoadError(schemaViolation, "deform timeline attachment must not be empty")
  if timeline.vertexCount <= 0:
    raise newBonyLoadError(schemaViolation, "deform timeline vertex count must be positive")
  if timeline.keys.len == 0:
    raise newBonyLoadError(schemaViolation, "deform timeline must contain at least one keyframe")
  for index, key in timeline.keys:
    validateDeformKey(key, timeline.vertexCount)
    if index > 0 and timeline.keys[index - 1].time >= key.time:
      raise newBonyLoadError(schemaViolation, "deform key times must be strictly increasing")


proc deformTimeline*(
  skin, slot, attachment: string;
  mesh: MeshAttachment;
  keys: openArray[DeformKeyframe];
): DeformTimeline =
  result = DeformTimeline(
    skin: skin,
    slot: slot,
    attachment: attachment,
    vertexCount: mesh.vertices.len,
    keys: @keys,
  )
  validateDeformTimeline(result)


proc deformTimeline*(
  skin, slot: string;
  mesh: MeshAttachment;
  keys: openArray[DeformKeyframe];
): DeformTimeline =
  deformTimeline(skin, slot, mesh.deformAttachment, mesh, keys)


proc lastTime(timeline: DeformTimeline): float64 =
  validateDeformTimeline(timeline)
  timeline.keys[^1].time


proc animationClip*(
  data: SkeletonData;
  name: string;
  boneTimelines: openArray[BoneTimeline] = [];
  slotTimelines: openArray[SlotTimeline] = [];
  eventTimelines: openArray[EventTimeline] = [];
  deformTimelines: openArray[DeformTimeline] = [];
): AnimationClip =
  if name.len == 0:
    raise newBonyLoadError(schemaViolation, "animation name must not be empty")

  var boneNames = initHashSet[string]()
  var slotNames = initHashSet[string]()
  var regionNames = initHashSet[string]()
  var meshVertexCounts = initTable[string, int]()
  var slotSetupAttachments = initTable[string, string]()
  var visibleAttachmentBySlot = initTable[string, HashSet[string]]()
  for bone in data.bones:
    boneNames.incl(bone.name)
  for slot in data.slots:
    slotNames.incl(slot.name)
    slotSetupAttachments[slot.name] = slot.attachment
    if slot.attachment.len > 0:
      visibleAttachmentBySlot.mgetOrPut(slot.name, initHashSet[string]()).incl(slot.attachment)
  for region in data.regions:
    regionNames.incl(region.name)
  for mesh in data.meshAttachments:
    meshVertexCounts[mesh.name] = mesh.vertices.len
  if data.skins.len > 0:
    for skin in data.skins:
      for entry in skin.entries:
        visibleAttachmentBySlot.mgetOrPut(entry.slot, initHashSet[string]()).incl(entry.attachment)

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
        if key.attachment.len > 0:
          if data.skins.len == 0:
            if key.attachment notin regionNames:
              raise newBonyLoadError(unknownRequiredReference, "unknown timeline attachment: " & key.attachment)
          elif timeline.target notin visibleAttachmentBySlot or key.attachment notin visibleAttachmentBySlot[timeline.target]:
            raise newBonyLoadError(unknownRequiredReference,
              "unknown timeline attachment: " & timeline.target & "/" & key.attachment)
    duration = max(duration, timeline.lastTime)
  for timeline in eventTimelines:
    validateEventTimeline(timeline, "event timeline")
    duration = max(duration, timeline.lastTime)
  for timeline in deformTimelines:
    validateDeformTimeline(timeline)
    if not data.hasSkin(timeline.skin):
      raise newBonyLoadError(unknownRequiredReference, "unknown deform timeline skin: " & timeline.skin)
    if timeline.slot notin slotNames:
      raise newBonyLoadError(unknownRequiredReference, "unknown deform timeline slot: " & timeline.slot)
    let resolvedAttachment = data.resolveSkinAttachmentTarget(timeline.skin, timeline.slot, timeline.attachment)
    if resolvedAttachment.len == 0:
      raise newBonyLoadError(unknownRequiredReference,
        "deform timeline slot/attachment pairing does not resolve to a mesh on that slot: " &
        timeline.slot & "/" & timeline.attachment)
    if data.skins.len == 0 and slotSetupAttachments.getOrDefault(timeline.slot) != timeline.attachment:
      raise newBonyLoadError(unknownRequiredReference,
        "deform timeline slot/attachment pairing does not resolve to a mesh on that slot: " &
        timeline.slot & "/" & timeline.attachment)
    if resolvedAttachment notin meshVertexCounts:
      raise newBonyLoadError(unknownRequiredReference, "deform timeline target is not a mesh attachment: " & resolvedAttachment)
    if timeline.vertexCount != meshVertexCounts[resolvedAttachment]:
      raise newBonyLoadError(schemaViolation, "deform timeline vertex count does not match mesh: " & resolvedAttachment)
    duration = max(duration, timeline.lastTime)

  AnimationClip(
    name: name,
    duration: duration,
    boneTimelines: @boneTimelines,
    slotTimelines: @slotTimelines,
    eventTimelines: @eventTimelines,
    deformTimelines: @deformTimelines,
  )


proc clamp01*(value: float64): float64 =
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


proc findSpan*[T](keys: openArray[T]; time: float64): int =
  if time <= keys[0].time:
    return 0
  for index in 0 ..< keys.len - 1:
    if time < keys[index + 1].time:
      return index
  keys.len - 1


proc sample*(timeline: BoneTimeline; time: float64): ScalarKeyframe =
  validateBoneTimeline(timeline, "bone timeline")
  if not timeline.kind.isScalarBoneTimeline:
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
  if not timeline.kind.isVectorBoneTimeline:
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
