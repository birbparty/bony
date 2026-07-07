## Shared numeric guards and tiny math helpers for constraint solvers.

import std/math

import bony/model


proc requireFinite*(value: float64; context: string): float64 =
  if classify(value) in {fcNan, fcInf, fcNegInf}:
    raise newBonyLoadError(numericOutOfRange, context & " must be finite")
  value


proc requireNonNegative*(value: float64; context: string): float64 =
  result = requireFinite(value, context)
  if result < 0.0:
    raise newBonyLoadError(schemaViolation, context & " must be non-negative")


proc requireUnit*(value: float64; context: string): float64 =
  result = requireFinite(value, context)
  if result < 0.0 or result > 1.0:
    raise newBonyLoadError(schemaViolation, context & " must be in [0, 1]")


proc requirePoint*[T](point: T; context: string): T =
  result = point
  result.x = requireFinite(point.x, context & ".x")
  result.y = requireFinite(point.y, context & ".y")


proc lerp*(a, b, mix: float64): float64 =
  a + (b - a) * mix


proc pointDistance*[T](a, b: T): float64 =
  hypot(b.x - a.x, b.y - a.y)
