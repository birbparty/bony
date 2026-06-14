## M7 parameter animation timelines for driving deformer inputs over time.

import bony/anim/timelines
import bony/deform/parameters
import bony/model

type
  ParameterTimeline* = object
    target*: string
    axis*: ParameterAxis
    keys*: seq[ScalarKeyframe]


proc quantizeTimelineTime(value: float64; context: string): float64 =
  result = quantizeF32(value, context)
  if result < 0:
    raise newBonyLoadError(schemaViolation, context & " must be non-negative")


proc requireSortedKeys(keys: openArray[ScalarKeyframe]; context: string) =
  if keys.len == 0:
    raise newBonyLoadError(schemaViolation, context & " must contain at least one keyframe")
  for index in 1 ..< keys.len:
    if keys[index - 1].time >= keys[index].time:
      raise newBonyLoadError(schemaViolation, context & " keyframe times must be strictly increasing")


proc validatedParameterTimeline(timeline: ParameterTimeline): ParameterTimeline =
  let axis = parameterAxis(
    timeline.axis.name,
    minValue = timeline.axis.minValue,
    maxValue = timeline.axis.maxValue,
    defaultValue = timeline.axis.defaultValue,
  )
  if timeline.target.len == 0:
    raise newBonyLoadError(schemaViolation, "parameter timeline target must not be empty")
  if timeline.target != axis.name:
    raise newBonyLoadError(unknownRequiredReference, "parameter timeline target does not match axis")
  requireSortedKeys(timeline.keys, "parameter timeline")
  result = ParameterTimeline(target: timeline.target, axis: axis)
  for key in timeline.keys:
    discard quantizeTimelineTime(key.time, "key.time")
    result.keys.add scalarKeyframe(key.time, parameterSample(axis, key.value).value, key.curve)


proc parameterTimeline*(axis: ParameterAxis; keys: openArray[ScalarKeyframe]): ParameterTimeline =
  let axis = parameterAxis(axis.name, minValue = axis.minValue, maxValue = axis.maxValue, defaultValue = axis.defaultValue)
  validatedParameterTimeline(ParameterTimeline(target: axis.name, axis: axis, keys: @keys))


proc findSpan(keys: openArray[ScalarKeyframe]; time: float64): int =
  if time <= keys[0].time:
    return 0
  for index in 0 ..< keys.len - 1:
    if time < keys[index + 1].time:
      return index
  keys.len - 1


proc sampleParameterValue*(timeline: ParameterTimeline; time: float64): ParameterSample =
  let timeline = validatedParameterTimeline(timeline)
  let storedTime = quantizeTimelineTime(time, "sample.time")
  let index = findSpan(timeline.keys, storedTime)
  let current = timeline.keys[index]
  if index == timeline.keys.high or storedTime <= current.time:
    return parameterSample(timeline.axis, current.value)
  let next = timeline.keys[index + 1]
  let t = (storedTime - current.time) / (next.time - current.time)
  let mixed = current.value + (next.value - current.value) * current.curve.evaluate(t)
  parameterSample(timeline.axis, mixed)


proc applyParameterTimeline*(state: var ParameterState; timeline: ParameterTimeline; time: float64) =
  state.applyParameterSample(timeline.sampleParameterValue(time))
