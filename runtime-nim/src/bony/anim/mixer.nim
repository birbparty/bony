## M3 multi-track animation mixer.

import std/[math, tables]

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

  MixedPose* = object
    scalars*: seq[MixedScalar]
    vectors*: seq[MixedVector]
    attachments*: seq[MixedAttachment]

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


proc update*(state: var AnimationState; dt: float64) =
  let step = quantizeF32(dt, "animation.dt")
  if step < 0:
    raise newBonyLoadError(schemaViolation, "animation.dt must be non-negative")
  for track in state.tracks.mitems:
    if not track.hasCurrent:
      continue
    let scaled = step * track.timeScale
    track.current.time = quantizeF32(track.current.time + scaled, "track.time")
    if track.hasPrevious:
      track.previous.time = quantizeF32(track.previous.time + scaled, "track.previous.time")
      track.current.mixTime = quantizeF32(track.current.mixTime + abs(scaled), "track.mixTime")
      if track.current.mixDuration <= 0 or track.current.mixTime >= track.current.mixDuration:
        track.hasPrevious = false
    if track.queue.len > 0 and track.current.time >= track.queue[0].delay:
      var next = track.queue[0]
      track.queue.delete(0)
      if next.mixDuration > 0:
        track.previous = track.current
        track.hasPrevious = true
      else:
        track.hasPrevious = false
      track.current = next
      track.hasCurrent = true


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


proc applyEntry(
  scalars: var Table[string, MixedScalar];
  vectors: var Table[string, MixedVector];
  attachments: var Table[string, MixedAttachment];
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
      vectors.putVector(MixedVector(target: timeline.target, kind: timeline.kind, x: sample.x, y: sample.y), entry.blend, finalWeight)
    of inheritTimeline:
      discard
    else:
      let sample = timeline.sample(sampleTime)
      scalars.putScalar(MixedScalar(target: timeline.target, kind: timeline.kind, value: sample.value), entry.blend, finalWeight)
  if finalWeight >= track.mixAttachmentThreshold:
    for timeline in entry.clip.slotTimelines:
      if timeline.kind == attachmentTimeline:
        let sample = timeline.sampleAttachment(sampleTime)
        attachments[timeline.target] = MixedAttachment(target: timeline.target, attachment: sample.attachment)


proc sample*(state: AnimationState): MixedPose =
  var scalars = initTable[string, MixedScalar]()
  var vectors = initTable[string, MixedVector]()
  var attachments = initTable[string, MixedAttachment]()
  for track in state.tracks:
    if not track.hasCurrent:
      continue
    let mixWeight =
      if track.hasPrevious and track.current.mixDuration > 0:
        clamp01(track.current.mixTime / track.current.mixDuration)
      else:
        1.0
    if track.hasPrevious:
      applyEntry(scalars, vectors, attachments, track.previous, track, 1.0 - mixWeight)
    applyEntry(scalars, vectors, attachments, track.current, track, mixWeight)
  for value in scalars.values:
    result.scalars.add value
  for value in vectors.values:
    result.vectors.add value
  for value in attachments.values:
    result.attachments.add value
