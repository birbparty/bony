## M7 named scalar parameters for deformer and state-machine inputs.

import std/[sets, tables]

import bony/model

type
  ParameterAxis* = object
    name*: string
    minValue*: float64
    maxValue*: float64
    defaultValue*: float64

  ParameterSample* = object
    name*: string
    value*: float64

  ParameterState* = object
    axes: seq[ParameterAxis]
    values: Table[string, float64]


proc normalizedParameterAxis(axis: ParameterAxis): ParameterAxis =
  result = ParameterAxis(
    name: axis.name,
    minValue: quantizeF32(axis.minValue, "parameter.min"),
    maxValue: quantizeF32(axis.maxValue, "parameter.max"),
    defaultValue: quantizeF32(axis.defaultValue, "parameter.default"),
  )
  if result.name.len == 0:
    raise newBonyLoadError(schemaViolation, "parameter name must not be empty")
  if result.minValue >= result.maxValue:
    raise newBonyLoadError(schemaViolation, "parameter min must be less than max")
  if result.defaultValue < result.minValue or result.defaultValue > result.maxValue:
    raise newBonyLoadError(schemaViolation, "parameter default must be within min..max")


proc validateParameterAxis*(axis: ParameterAxis) =
  discard normalizedParameterAxis(axis)


proc parameterAxis*(name: string; minValue = 0.0; maxValue = 1.0; defaultValue = 0.0): ParameterAxis =
  normalizedParameterAxis(ParameterAxis(name: name, minValue: minValue, maxValue: maxValue, defaultValue: defaultValue))


proc validateParameterAxes*(axes: openArray[ParameterAxis]) =
  var names = initHashSet[string]()
  for axis in axes:
    let normalized = normalizedParameterAxis(axis)
    if normalized.name in names:
      raise newBonyLoadError(duplicateKey, "duplicate parameter name: " & normalized.name)
    names.incl(normalized.name)


proc name*(axis: ParameterAxis): string = axis.name
proc minValue*(axis: ParameterAxis): float64 = axis.minValue
proc maxValue*(axis: ParameterAxis): float64 = axis.maxValue
proc defaultValue*(axis: ParameterAxis): float64 = axis.defaultValue


proc quantizeParameterValue(axis: ParameterAxis; value: float64): float64 =
  result = quantizeF32(value, "parameter.value")
  if result < axis.minValue or result > axis.maxValue:
    raise newBonyLoadError(schemaViolation, "parameter value must be within min..max")


proc parameterSample*(axis: ParameterAxis; value: float64): ParameterSample =
  let axis = normalizedParameterAxis(axis)
  ParameterSample(name: axis.name, value: quantizeParameterValue(axis, value))


proc defaultParameterSample*(axis: ParameterAxis): ParameterSample =
  parameterSample(axis, axis.defaultValue)


proc initParameterState*(axes: openArray[ParameterAxis]): ParameterState =
  var names = initHashSet[string]()
  for axis in axes:
    let normalized = normalizedParameterAxis(axis)
    if normalized.name in names:
      raise newBonyLoadError(duplicateKey, "duplicate parameter name: " & normalized.name)
    names.incl(normalized.name)
    result.axes.add normalized
    result.values[normalized.name] = normalized.defaultValue


proc axes*(state: ParameterState): seq[ParameterAxis] =
  state.axes


proc samples*(state: ParameterState): seq[ParameterSample] =
  for axis in state.axes:
    result.add ParameterSample(name: axis.name, value: state.values[axis.name])


proc axisByName(state: ParameterState; name: string): ParameterAxis =
  for axis in state.axes:
    if axis.name == name:
      return axis
  raise newBonyLoadError(unknownRequiredReference, "unknown parameter: " & name)


proc getParameterValue*(state: ParameterState; name: string): float64 =
  discard state.axisByName(name)
  state.values[name]


proc setParameterValue*(state: var ParameterState; name: string; value: float64) =
  let axis = state.axisByName(name)
  state.values[name] = quantizeParameterValue(axis, value)


proc applyParameterSample*(state: var ParameterState; sample: ParameterSample) =
  state.setParameterValue(sample.name, sample.value)


proc resetParameters*(state: var ParameterState) =
  for axis in state.axes:
    state.values[axis.name] = axis.defaultValue
