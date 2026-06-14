## M7 keyform multilinear blending across named parameter axes.

import std/[algorithm, sets, tables]

import bony/deform/deformers
import bony/deform/parameters
import bony/model

const maxVaryingKeyformAxes = 20

type
  Keyform* = object
    coordinates*: seq[ParameterSample]
    values*: seq[float64]

  KeyformBlend* = object
    axes*: seq[ParameterAxis]
    valueCount*: int
    keyforms*: seq[Keyform]

  ActiveAxis = object
    axisIndex: int
    low: float64
    high: float64
    t: float64


proc keyformValue*(value: float64): float64 =
  quantizeF32(value, "keyform.value")


proc keyform*(coordinates: openArray[ParameterSample]; values: openArray[float64]): Keyform =
  if coordinates.len == 0:
    raise newBonyLoadError(schemaViolation, "keyform must contain at least one parameter coordinate")
  if values.len == 0:
    raise newBonyLoadError(schemaViolation, "keyform must contain at least one value")
  result.coordinates = @coordinates
  for value in values:
    result.values.add keyformValue(value)


proc pointKeyform*(coordinates: openArray[ParameterSample]; points: openArray[DeformerPoint]): Keyform =
  var values: seq[float64]
  for point in points:
    values.add point.x
    values.add point.y
  keyform(coordinates, values)


proc blendedPoints*(values: openArray[float64]): seq[DeformerPoint] =
  if values.len == 0 or values.len mod 2 != 0:
    raise newBonyLoadError(schemaViolation, "point keyform values must contain x/y pairs")
  var index = 0
  while index < values.len:
    result.add deformerPoint(values[index], values[index + 1])
    inc index, 2


proc coordinateKey(coordinates: openArray[ParameterSample]): string =
  for coordinate in coordinates:
    result.add coordinate.name
    result.add "="
    result.add $coordinate.value
    result.add "\0"


proc sampleByName(samples: openArray[ParameterSample]; name: string): ParameterSample =
  for sample in samples:
    if sample.name == name:
      return sample
  raise newBonyLoadError(unknownRequiredReference, "missing keyform coordinate: " & name)


proc validateKeyformCoordinates(axes: openArray[ParameterAxis]; keyform: Keyform): seq[ParameterSample] =
  if keyform.coordinates.len != axes.len:
    raise newBonyLoadError(schemaViolation, "keyform coordinate count must match parameter axes")
  var names = initHashSet[string]()
  for axis in axes:
    let sample = parameterSample(axis, keyform.coordinates.sampleByName(axis.name).value)
    if sample.name in names:
      raise newBonyLoadError(duplicateKey, "duplicate keyform coordinate: " & sample.name)
    names.incl(sample.name)
    result.add sample


proc keyformBlend*(axes: openArray[ParameterAxis]; keyforms: openArray[Keyform]): KeyformBlend =
  if axes.len == 0:
    raise newBonyLoadError(schemaViolation, "keyform blend must contain at least one parameter axis")
  if keyforms.len == 0:
    raise newBonyLoadError(schemaViolation, "keyform blend must contain at least one keyform")
  validateParameterAxes(axes)
  result.axes = initParameterState(axes).axes
  result.valueCount = keyforms[0].values.len
  if result.valueCount == 0:
    raise newBonyLoadError(schemaViolation, "keyform values must not be empty")

  var coordinateKeys = initHashSet[string]()
  for input in keyforms:
    if input.values.len != result.valueCount:
      raise newBonyLoadError(schemaViolation, "keyform value counts must match")
    let coordinates = validateKeyformCoordinates(result.axes, input)
    let key = coordinateKey(coordinates)
    if key in coordinateKeys:
      raise newBonyLoadError(duplicateKey, "duplicate keyform coordinate")
    coordinateKeys.incl(key)
    var normalized = Keyform(coordinates: coordinates)
    for value in input.values:
      normalized.values.add keyformValue(value)
    result.keyforms.add normalized


proc axisCoordinateValues(blend: KeyformBlend): seq[seq[float64]] =
  result = newSeq[seq[float64]](blend.axes.len)
  for keyform in blend.keyforms:
    for axisIndex, axis in blend.axes:
      let value = keyform.coordinates.sampleByName(axis.name).value
      if value notin result[axisIndex]:
        result[axisIndex].add value
  for values in result.mitems:
    values.sort()


proc axisValue(samples: openArray[ParameterSample]; axis: ParameterAxis): float64 =
  parameterSample(axis, samples.sampleByName(axis.name).value).value


proc validateRuntimeSamples(samples: openArray[ParameterSample]; axes: openArray[ParameterAxis]) =
  var names = initHashSet[string]()
  for sample in samples:
    if sample.name in names:
      raise newBonyLoadError(duplicateKey, "duplicate parameter sample: " & sample.name)
    names.incl(sample.name)
  for axis in axes:
    discard samples.sampleByName(axis.name)


proc bracket(values: openArray[float64]; value: float64): tuple[low, high: float64; t: float64] =
  if values.len == 0:
    raise newBonyLoadError(schemaViolation, "keyform axis must contain at least one coordinate")
  if value <= values[0]:
    return (low: values[0], high: values[0], t: 0.0)
  for index in 0 ..< values.len - 1:
    if value <= values[index + 1]:
      let low = values[index]
      let high = values[index + 1]
      if high == low:
        return (low: low, high: high, t: 0.0)
      return (low: low, high: high, t: (value - low) / (high - low))
  (low: values[^1], high: values[^1], t: 0.0)


proc keyformTable(blend: KeyformBlend): Table[string, Keyform] =
  for keyform in blend.keyforms:
    result[coordinateKey(keyform.coordinates)] = keyform


proc cornerKey(axes: openArray[ParameterAxis]; corner: openArray[float64]): string =
  for index, axis in axes:
    result.add axis.name
    result.add "="
    result.add $corner[index]
    result.add "\0"


proc sampleKeyformValues*(blend: KeyformBlend; samples: openArray[ParameterSample]): seq[float64] =
  let blend = keyformBlend(blend.axes, blend.keyforms)
  validateRuntimeSamples(samples, blend.axes)
  let valuesByAxis = blend.axisCoordinateValues()
  let keyformsByCoordinate = blend.keyformTable()
  var lows = newSeq[float64](blend.axes.len)
  var highs = newSeq[float64](blend.axes.len)
  var ts = newSeq[float64](blend.axes.len)
  var activeAxes: seq[ActiveAxis]
  for axisIndex, axis in blend.axes:
    let value = samples.axisValue(axis)
    let axisBracket = bracket(valuesByAxis[axisIndex], value)
    lows[axisIndex] = axisBracket.low
    highs[axisIndex] = axisBracket.high
    ts[axisIndex] = axisBracket.t
    if axisBracket.low != axisBracket.high:
      activeAxes.add ActiveAxis(axisIndex: axisIndex, low: axisBracket.low, high: axisBracket.high, t: axisBracket.t)
  if activeAxes.len > maxVaryingKeyformAxes:
    raise newBonyLoadError(schemaViolation, "keyform blend has too many varying axes")

  result = newSeq[float64](blend.valueCount)
  let cornerCount = 1 shl activeAxes.len
  for mask in 0 ..< cornerCount:
    var corner = lows
    var weight = 1.0
    for activeIndex, activeAxis in activeAxes:
      if ((mask shr activeIndex) and 1) == 0:
        corner[activeAxis.axisIndex] = activeAxis.low
        weight *= 1.0 - activeAxis.t
      else:
        corner[activeAxis.axisIndex] = activeAxis.high
        weight *= activeAxis.t
    if weight == 0.0:
      continue
    let key = cornerKey(blend.axes, corner)
    if key notin keyformsByCoordinate:
      raise newBonyLoadError(unknownRequiredReference, "missing keyform corner")
    let cornerKeyform = keyformsByCoordinate[key]
    for valueIndex, value in cornerKeyform.values:
      result[valueIndex] += value * weight
  for value in result.mitems:
    value = keyformValue(value)


proc sampleKeyformPoints*(blend: KeyformBlend; samples: openArray[ParameterSample]): seq[DeformerPoint] =
  blendedPoints(sampleKeyformValues(blend, samples))
