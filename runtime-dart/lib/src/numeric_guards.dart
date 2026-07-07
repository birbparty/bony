import 'dart:math' as math;

double requireFinite(double value, String context) {
  if (value.isNaN || value.isInfinite) {
    throw FormatException('$context must be finite');
  }
  return value;
}

double requireNonNegative(double value, String context) {
  final result = requireFinite(value, context);
  if (result < 0.0) {
    throw FormatException('$context must be non-negative');
  }
  return result;
}

double requireMix(double value, String context) {
  final result = requireFinite(value, context);
  if (result < 0.0 || result > 1.0) {
    throw FormatException('$context must be in [0, 1]');
  }
  return result;
}

double lerp(double a, double b, double mix) => a + (b - a) * mix;

double degToRad(double degrees) => degrees * math.pi / 180.0;

double radToDeg(double radians) => radians * 180.0 / math.pi;

double hypot2(double dx, double dy) => math.sqrt(dx * dx + dy * dy);

double distance2(double ax, double ay, double bx, double by) =>
    hypot2(bx - ax, by - ay);
