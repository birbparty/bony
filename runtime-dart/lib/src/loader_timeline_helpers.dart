part of 'loader.dart';

void _ensureStrictlyIncreasing(List<double> times, String ctx) {
  for (var i = 1; i < times.length; i++) {
    if (times[i] <= times[i - 1]) {
      throw FormatException(
          '$ctx.keyframes: times must be strictly increasing');
    }
  }
}

/// Event-timeline ordering: non-decreasing (equal times allowed), unlike the
/// strict bone/slot/deform rule. Rejects only a strictly decreasing adjacent
/// pair, mirroring Nim `ensureEventSorted` (timelines.nim:245-248) /
/// docs/event-timeline-contract.md edge case (c).
void _ensureNonDecreasing(List<double> times, String ctx) {
  for (var i = 1; i < times.length; i++) {
    if (times[i] < times[i - 1]) {
      throw FormatException('$ctx.keyframes: times must be non-decreasing');
    }
  }
}
