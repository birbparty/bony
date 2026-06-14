## M3 multi-track animation mixer.

import std/[algorithm, math, tables]

import bony/anim/timelines
import bony/model

type
  MixBlend* = enum
    firstMix,
    replaceMix,
    addMix

  MixedScalar* = object
    target*: string
    kind*: BoneTimelineKind
    value*: float64

  MixedVector* = object
    target*: string
    kind*: BoneTimelineKind
    x*: float64
    y*: float64

  MixedAttachment* = object
    target*: string
    attachment*: string

  MixedInherit* = object
    target*: string
    value*: InheritKeyframe

  MixedColor* = object
    target*: string
    kind*: SlotTimelineKind
    color*: ColorRgba

  MixedColor2* = object
    target*: string
    color*: ColorRgba2

  MixedSequence* = object
    target*: string
    value*: SequenceKeyframe

  DispatchedEvent* = object
    trackIndex*: int
    event*: EventData
    time*: float64

  MixedPose* = object
    scalars*: seq[MixedScalar]
    vectors*: seq[MixedVector]
    attachments*: seq[MixedAttachment]
    inherits*: seq[MixedInherit]
    colors*: seq[MixedColor]
    colors2*: seq[MixedColor2]
    sequences*: seq[MixedSequence]

  TrackEntry* = object
    clip*: AnimationClip
    loop*: bool
    delay*: float64
    mixDuration*: float64
    time*: float64
    mixTime*: float64
    blend*: MixBlend

  AnimationTrack* = object
    current*: TrackEntry
    previous*: TrackEntry
    queue*: seq[TrackEntry]
    hasCurrent*: bool
    hasPrevious*: bool
    alpha*: float64
    timeScale*: float64
    mixAttachmentThreshold*: float64
    mixDrawOrderThreshold*: float64
    eventThreshold*: float64

  AnimationState* = object
    tracks*: seq[AnimationTrack]
    data*: ref SkeletonData
    events*: seq[DispatchedEvent]

proc clamp01(value: float64): float64 =
  min(1.0, max(0.0, value))


proc wrappedTime(entry: TrackEntry): float64 =
  if entry.loop and entry.clip.duration > 0:
    entry.time mod entry.clip.duration
  else:
    min(entry.time, entry.clip.duration)


proc trackEntry*(
  clip: AnimationClip;
  loop = false;
  delay = 0.0;
  mixDuration = 0.0;
  blend = replaceMix;
): TrackEntry =
  let storedDelay = quantizeF32(delay, "track.delay")
  let storedMixDuration = quantizeF32(mixDuration, "track.mixDuration")
  if storedDelay < 0:
    raise newBonyLoadError(schemaViolation, "track.delay must be non-negative")
  if storedMixDuration < 0:
    raise newBonyLoadError(schemaViolation, "track.mixDuration must be non-negative")
  TrackEntry(clip: clip, loop: loop, delay: storedDelay, mixDuration: storedMixDuration, blend: blend)


proc animationTrack*(
  alpha = 1.0;
  timeScale = 1.0;
  mixAttachmentThreshold = 0.5;
  mixDrawOrderThreshold = 0.5;
  eventThreshold = 0.5;
): AnimationTrack =
  AnimationTrack(
    alpha: clamp01(quantizeF32(alpha, "track.alpha")),
    timeScale: quantizeF32(timeScale, "track.timeScale"),
    mixAttachmentThreshold: clamp01(quantizeF32(mixAttachmentThreshold, "track.mixAttachmentThreshold")),
    mixDrawOrderThreshold: clamp01(quantizeF32(mixDrawOrderThreshold, "track.mixDrawOrderThreshold")),
    eventThreshold: clamp01(quantizeF32(eventThreshold, "track.eventThreshold")),
  )


proc animationState*(trackCount = 0): AnimationState =
  result.tracks = newSeq[AnimationTrack](trackCount)
  for track in result.tracks.mitems:
    track = animationTrack()


proc animationState*(data: ref SkeletonData; trackCount = 0): AnimationState =
  result = animationState(trackCount)
  result.data = data


proc ensureTrack(state: var AnimationState; index: int) =
  if index < 0:
    raise newBonyLoadError(schemaViolation, "track index must be non-negative")
  while state.tracks.len <= index:
    state.tracks.add animationTrack()


proc setAnimation*(
  state: var AnimationState;
  trackIndex: int;
  clip: AnimationClip;
  loop = false;
  mixDuration = 0.0;
  blend = replaceMix;
) =
  state.ensureTrack(trackIndex)
  var entry = trackEntry(clip, loop, mixDuration = mixDuration, blend = blend)
  if state.tracks[trackIndex].hasCurrent and entry.mixDuration > 0:
    state.tracks[trackIndex].previous = state.tracks[trackIndex].current
    state.tracks[trackIndex].hasPrevious = true
  else:
    state.tracks[trackIndex].hasPrevious = false
  state.tracks[trackIndex].current = entry
  state.tracks[trackIndex].hasCurrent = true
  state.tracks[trackIndex].queue.setLen(0)


proc addAnimation*(
  state: var AnimationState;
  trackIndex: int;
  clip: AnimationClip;
  loop = false;
  delay = 0.0;
  mixDuration = 0.0;
  blend = replaceMix;
) =
  state.ensureTrack(trackIndex)
  state.tracks[trackIndex].queue.add trackEntry(clip, loop, delay, mixDuration, blend)


proc currentMixWeight(track: AnimationTrack): float64 =
  if track.hasPrevious and track.current.mixDuration > 0:
    clamp01(track.current.mixTime / track.current.mixDuration)
  else:
    1.0


proc dispatchEvents(
  output: var seq[DispatchedEvent];
  trackIndex: int;
  entry: TrackEntry;
  fromTime, toTime: float64;
  includeFrom = false;
) =
  if toTime < fromTime or (toTime == fromTime and not includeFrom):
    return
  var fired: seq[tuple[event: DispatchedEvent, order: int]]
  var order = 0
  if entry.loop and entry.clip.duration > 0:
    let duration = entry.clip.duration
    let firstCycle = int(floor(fromTime / duration))
    let lastCycle = int(floor(toTime / duration))
    for cycle in firstCycle .. lastCycle:
      let baseTime = float64(cycle) * duration
      for timeline in entry.clip.eventTimelines:
        for key in timeline.keys:
          let absoluteTime = baseTime + key.time
          if (absoluteTime > fromTime or (includeFrom and absoluteTime == fromTime)) and absoluteTime <= toTime:
            fired.add (DispatchedEvent(trackIndex: trackIndex, event: key.event, time: absoluteTime), order)
          inc order
  else:
    let endTime = min(toTime, entry.clip.duration)
    for timeline in entry.clip.eventTimelines:
      for key in timeline.keys:
        if (key.time > fromTime or (includeFrom and key.time == fromTime)) and key.time <= endTime:
          fired.add (DispatchedEvent(trackIndex: trackIndex, event: key.event, time: key.time), order)
        inc order
  fired.sort(proc(a, b: tuple[event: DispatchedEvent, order: int]): int =
    result = cmp(a.event.time, b.event.time)
    if result == 0:
      result = cmp(a.order, b.order)
  )
  for item in fired:
    output.add item.event


proc advancePlaying(track: var AnimationTrack; amount: float64; events: var seq[DispatchedEvent]; trackIndex: int) =
  if amount <= 0:
    return
  let startTime = track.current.time
  let startMixTime = track.current.mixTime
  let hadPrevious = track.hasPrevious
  let mixDuration = track.current.mixDuration
  track.current.time = quantizeF32(track.current.time + amount, "track.time")
  if track.hasPrevious:
    track.previous.time = quantizeF32(track.previous.time + amount, "track.previous.time")
    track.current.mixTime = quantizeF32(track.current.mixTime + amount, "track.mixTime")
    if track.current.mixDuration <= 0 or track.current.mixTime >= track.current.mixDuration:
      track.hasPrevious = false
  if hadPrevious and mixDuration > 0:
    let thresholdTime = mixDuration * track.eventThreshold
    if track.current.mixTime >= thresholdTime:
      if startMixTime >= thresholdTime:
        events.dispatchEvents(trackIndex, track.current, startTime, track.current.time)
      else:
        let dispatchFrom = quantizeF32(startTime + thresholdTime - startMixTime, "track.eventThresholdTime")
        events.dispatchEvents(trackIndex, track.current, dispatchFrom, track.current.time, includeFrom = true)
  else:
    events.dispatchEvents(trackIndex, track.current, startTime, track.current.time)


proc update*(state: var AnimationState; dt: float64) =
  let step = quantizeF32(dt, "animation.dt")
  if step < 0:
    raise newBonyLoadError(schemaViolation, "animation.dt must be non-negative")
  state.events.setLen(0)
  for trackIndex in 0 ..< state.tracks.len:
    var track = state.tracks[trackIndex]
    if not track.hasCurrent:
      continue
    let scaled = step * track.timeScale
    if scaled < 0:
      raise newBonyLoadError(schemaViolation, "track.timeScale must be non-negative")
    var remaining = scaled
    while remaining > 0 and track.hasCurrent:
      if track.queue.len > 0 and track.current.time + remaining >= track.queue[0].delay:
        let beforeSwitch = max(0.0, track.queue[0].delay - track.current.time)
        track.advancePlaying(beforeSwitch, state.events, trackIndex)
        remaining = quantizeF32(remaining - beforeSwitch, "track.remaining")
        var next = track.queue[0]
        track.queue.delete(0)
        if next.mixDuration > 0:
          track.previous = track.current
          track.hasPrevious = true
        else:
          track.hasPrevious = false
        track.current = next
        track.hasCurrent = true
        track.advancePlaying(remaining, state.events, trackIndex)
        remaining = 0
      else:
        track.advancePlaying(remaining, state.events, trackIndex)
        remaining = 0
    if remaining == 0 and track.queue.len > 0 and track.current.time >= track.queue[0].delay:
      var next = track.queue[0]
      track.queue.delete(0)
      if next.mixDuration > 0:
        track.previous = track.current
        track.hasPrevious = true
      else:
        track.hasPrevious = false
      track.current = next
      track.hasCurrent = true
    state.tracks[trackIndex] = track


proc scalarKey(target: string; kind: BoneTimelineKind): string = target & "\0" & $kind
proc vectorKey(target: string; kind: BoneTimelineKind): string = target & "\0" & $kind


proc putScalar(values: var Table[string, MixedScalar]; sample: MixedScalar; blend: MixBlend; weight: float64) =
  let key = scalarKey(sample.target, sample.kind)
  case blend
  of firstMix:
    if key notin values:
      values[key] = MixedScalar(target: sample.target, kind: sample.kind, value: sample.value * weight)
  of replaceMix:
    let base = if key in values: values[key].value else: 0.0
    values[key] = MixedScalar(target: sample.target, kind: sample.kind, value: base + (sample.value - base) * weight)
  of addMix:
    let base = if key in values: values[key].value else: 0.0
    values[key] = MixedScalar(target: sample.target, kind: sample.kind, value: base + sample.value * weight)


proc putVector(values: var Table[string, MixedVector]; sample: MixedVector; blend: MixBlend; weight: float64) =
  let key = vectorKey(sample.target, sample.kind)
  case blend
  of firstMix:
    if key notin values:
      values[key] = MixedVector(target: sample.target, kind: sample.kind, x: sample.x * weight, y: sample.y * weight)
  of replaceMix:
    let base = if key in values: values[key] else: MixedVector(target: sample.target, kind: sample.kind)
    values[key] = MixedVector(
      target: sample.target,
      kind: sample.kind,
      x: base.x + (sample.x - base.x) * weight,
      y: base.y + (sample.y - base.y) * weight,
    )
  of addMix:
    let base = if key in values: values[key] else: MixedVector(target: sample.target, kind: sample.kind)
    values[key] = MixedVector(target: sample.target, kind: sample.kind, x: base.x + sample.x * weight, y: base.y + sample.y * weight)


proc setupScalar(data: ref SkeletonData; target: string; kind: BoneTimelineKind): float64 =
  if data.isNil:
    return 0.0
  for bone in data[].bones:
    if bone.name == target:
      let local = bone.local
      case kind
      of rotateTimeline: return local.rotation
      of translateXTimeline: return local.x
      of translateYTimeline: return local.y
      of scaleXTimeline: return local.scaleX
      of scaleYTimeline: return local.scaleY
      of shearXTimeline: return local.shearX
      of shearYTimeline: return local.shearY
      else: return 0.0
  0.0


proc setupVector(data: ref SkeletonData; target: string; kind: BoneTimelineKind): MixedVector =
  result = MixedVector(target: target, kind: kind)
  if data.isNil:
    return
  for bone in data[].bones:
    if bone.name == target:
      let local = bone.local
      case kind
      of translateTimeline:
        result.x = local.x
        result.y = local.y
      of scaleTimeline:
        result.x = local.scaleX
        result.y = local.scaleY
      of shearTimeline:
        result.x = local.shearX
        result.y = local.shearY
      else:
        discard
      return


proc putScalarWithSetup(
  values: var Table[string, MixedScalar];
  data: ref SkeletonData;
  sample: MixedScalar;
  blend: MixBlend;
  weight: float64;
) =
  let key = scalarKey(sample.target, sample.kind)
  if key notin values:
    values[key] = MixedScalar(target: sample.target, kind: sample.kind, value: setupScalar(data, sample.target, sample.kind))
  values.putScalar(sample, blend, weight)


proc putVectorWithSetup(
  values: var Table[string, MixedVector];
  data: ref SkeletonData;
  sample: MixedVector;
  blend: MixBlend;
  weight: float64;
) =
  let key = vectorKey(sample.target, sample.kind)
  if key notin values:
    values[key] = setupVector(data, sample.target, sample.kind)
  values.putVector(sample, blend, weight)


proc applyEntry(
  data: ref SkeletonData;
  scalars: var Table[string, MixedScalar];
  vectors: var Table[string, MixedVector];
  attachments: var Table[string, MixedAttachment];
  inherits: var Table[string, MixedInherit];
  colors: var Table[string, MixedColor];
  colors2: var Table[string, MixedColor2];
  sequences: var Table[string, MixedSequence];
  entry: TrackEntry;
  track: AnimationTrack;
  weight: float64;
) =
  let sampleTime = entry.wrappedTime
  let finalWeight = clamp01(track.alpha * weight)
  for timeline in entry.clip.boneTimelines:
    case timeline.kind
    of translateTimeline, scaleTimeline, shearTimeline:
      let sample = timeline.sampleVector(sampleTime)
      vectors.putVectorWithSetup(data, MixedVector(target: timeline.target, kind: timeline.kind, x: sample.x, y: sample.y), entry.blend, finalWeight)
    of inheritTimeline:
      if finalWeight >= track.mixAttachmentThreshold:
        inherits[timeline.target] = MixedInherit(target: timeline.target, value: timeline.sampleInherit(sampleTime))
    else:
      let sample = timeline.sample(sampleTime)
      scalars.putScalarWithSetup(data, MixedScalar(target: timeline.target, kind: timeline.kind, value: sample.value), entry.blend, finalWeight)
  if finalWeight >= track.mixAttachmentThreshold:
    for timeline in entry.clip.slotTimelines:
      case timeline.kind
      of attachmentTimeline:
        let sample = timeline.sampleAttachment(sampleTime)
        attachments[timeline.target] = MixedAttachment(target: timeline.target, attachment: sample.attachment)
      of rgbaTimeline, rgbTimeline, alphaTimeline:
        colors[timeline.target & "\0" & $timeline.kind] = MixedColor(target: timeline.target, kind: timeline.kind, color: timeline.sampleColor(sampleTime).color)
      of rgba2Timeline:
        colors2[timeline.target] = MixedColor2(target: timeline.target, color: timeline.sampleColor2(sampleTime).color)
      of sequenceTimeline:
        sequences[timeline.target] = MixedSequence(target: timeline.target, value: timeline.sampleSequenceKey(sampleTime))


proc scalarOrder(a, b: MixedScalar): int =
  result = cmp(a.target, b.target)
  if result == 0:
    result = cmp(ord(a.kind), ord(b.kind))


proc vectorOrder(a, b: MixedVector): int =
  result = cmp(a.target, b.target)
  if result == 0:
    result = cmp(ord(a.kind), ord(b.kind))


proc attachmentOrder(a, b: MixedAttachment): int = cmp(a.target, b.target)
proc inheritOrder(a, b: MixedInherit): int = cmp(a.target, b.target)


proc colorOrder(a, b: MixedColor): int =
  result = cmp(a.target, b.target)
  if result == 0:
    result = cmp(ord(a.kind), ord(b.kind))


proc color2Order(a, b: MixedColor2): int = cmp(a.target, b.target)
proc sequenceOrder(a, b: MixedSequence): int = cmp(a.target, b.target)


proc sample*(state: AnimationState): MixedPose =
  var scalars = initTable[string, MixedScalar]()
  var vectors = initTable[string, MixedVector]()
  var attachments = initTable[string, MixedAttachment]()
  var inherits = initTable[string, MixedInherit]()
  var colors = initTable[string, MixedColor]()
  var colors2 = initTable[string, MixedColor2]()
  var sequences = initTable[string, MixedSequence]()
  for track in state.tracks:
    if not track.hasCurrent:
      continue
    let mixWeight = track.currentMixWeight
    if track.hasPrevious:
      applyEntry(state.data, scalars, vectors, attachments, inherits, colors, colors2, sequences, track.previous, track, 1.0 - mixWeight)
    applyEntry(state.data, scalars, vectors, attachments, inherits, colors, colors2, sequences, track.current, track, mixWeight)
  for value in scalars.values:
    result.scalars.add value
  result.scalars.sort(scalarOrder)
  for value in vectors.values:
    result.vectors.add value
  result.vectors.sort(vectorOrder)
  for value in attachments.values:
    result.attachments.add value
  result.attachments.sort(attachmentOrder)
  for value in inherits.values:
    result.inherits.add value
  result.inherits.sort(inheritOrder)
  for value in colors.values:
    result.colors.add value
  result.colors.sort(colorOrder)
  for value in colors2.values:
    result.colors2.add value
  result.colors2.sort(color2Order)
  for value in sequences.values:
    result.sequences.add value
  result.sequences.sort(sequenceOrder)
