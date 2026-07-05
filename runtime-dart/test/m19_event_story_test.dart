import 'dart:convert';
import 'dart:io';

import 'package:bony/bony.dart';
import 'package:test/test.dart';

/// M19 event-timeline parity. Reproduces the committed `m19_event_story_*`
/// goldens' `animationEvents` channel from the Dart runtime.
///
/// Stepping model (docs/event-timeline-contract.md "Incremental per-sample-window
/// stepping"): event dispatch is delta-based, so the goldens MUST be replayed
/// INCREMENTALLY on a single carried runtime — advance one `AnimationState` by
/// `sample.time - previousTime` per sample and read the events fired in that
/// sample's window (`AnimationState.update` resets its event list every call).
/// A fresh-runtime absolute-time `rt.update(t)` per sample would fire the
/// cumulative `[0, t]` window and diverge (end = [land] vs [hit, hit2, land]).
///
/// The `event_story` machine is a single `base` layer holding one `pulse` clip
/// with no transitions, so the Nim story runner's per-layer clip-mirror bridge
/// (cli/bony_cli.nim:1456-1525) reduces here to advancing that one clip's
/// `AnimationState` by the per-sample delta.
void main() {
  const tol = 1e-4;

  // Golden window contents, per docs/event-timeline-contract.md and
  // conformance/goldens/m19_event_story_*.json. `rest` (t=0) advances by 0 and
  // fires nothing (the golden omits `animationEvents` entirely).
  final samples = <(String, double)>[
    ('rest', 0.0),
    ('mid', 0.5),
    ('end', 1.0),
  ];

  void expectEventsMatchGolden(
      List<DispatchedEvent> fired, String sampleName) {
    final golden = jsonDecodeGolden('m19_event_story_$sampleName.json');
    final expected = (golden['animationEvents'] as List<dynamic>?) ?? const [];
    expect(fired, hasLength(expected.length),
        reason: '$sampleName: event count');
    for (var i = 0; i < expected.length; i++) {
      final e = expected[i] as Map<String, dynamic>;
      final got = fired[i];
      // Exact string/int fields.
      expect(got.name, e['name'], reason: '$sampleName[$i].name');
      expect(got.trackIndex, e['trackIndex'],
          reason: '$sampleName[$i].trackIndex');
      expect(got.event.intValue, e['intValue'],
          reason: '$sampleName[$i].intValue');
      expect(got.event.stringValue, e['stringValue'],
          reason: '$sampleName[$i].stringValue');
      expect(got.event.audioPath, e['audioPath'],
          reason: '$sampleName[$i].audioPath');
      // Numeric fields within 1e-4 (docs/float-math-contract.md).
      expect(got.time, closeTo((e['time'] as num).toDouble(), tol),
          reason: '$sampleName[$i].time');
      expect(got.event.floatValue,
          closeTo((e['floatValue'] as num).toDouble(), tol),
          reason: '$sampleName[$i].floatValue');
      expect(got.event.volume, closeTo((e['volume'] as num).toDouble(), tol),
          reason: '$sampleName[$i].volume');
      expect(got.event.balance, closeTo((e['balance'] as num).toDouble(), tol),
          reason: '$sampleName[$i].balance');
    }
  }

  // Replay the `pulse` clip incrementally on one carried AnimationState, one
  // entry per (sampleName -> events fired in that sample's window).
  Map<String, List<DispatchedEvent>> replay(SkeletonData base) {
    final clip = base.animations.firstWhere((a) => a.name == 'pulse');
    final anim = AnimationState(base)..setAnimation(0, clip);
    final out = <String, List<DispatchedEvent>>{};
    var prevTime = 0.0;
    for (final (name, t) in samples) {
      anim.update(t - prevTime);
      out[name] = List<DispatchedEvent>.from(anim.events);
      prevTime = t;
    }
    return out;
  }

  group('M19 event-story goldens', () {
    late SkeletonData fromJson;

    setUpAll(() {
      fromJson = loadBonyJson(
          File('../conformance/assets/m19_event_rig.bony').readAsStringSync());
    });

    test('reproduces animationEvents from .bony', () {
      final fired = replay(fromJson);
      expectEventsMatchGolden(fired['rest']!, 'rest');
      expectEventsMatchGolden(fired['mid']!, 'mid');
      expectEventsMatchGolden(fired['end']!, 'end');
    });

    test('mid window fires [hit, hit2] in authoring order, end fires [land]',
        () {
      final fired = replay(fromJson);
      expect(fired['rest'], isEmpty);
      expect(fired['mid']!.map((e) => e.name), ['hit', 'hit2']);
      expect(fired['end']!.map((e) => e.name), ['land']);
    });
  });

  group('M19 event rig .bony-vs-.bnb parity', () {
    test('dispatched events are identical from .bony and .bnb', () {
      final fromJson = loadBonyJson(
          File('../conformance/assets/m19_event_rig.bony').readAsStringSync());
      final fromBnb = loadBonyBnb(
          File('../conformance/assets/bnb/m19_event_rig.bnb').readAsBytesSync());
      final j = replay(fromJson);
      final b = replay(fromBnb);
      for (final (name, _) in samples) {
        final je = j[name]!;
        final be = b[name]!;
        expect(be, hasLength(je.length), reason: '$name: count parity');
        for (var i = 0; i < je.length; i++) {
          expect(be[i].name, je[i].name, reason: '$name[$i].name');
          expect(be[i].trackIndex, je[i].trackIndex,
              reason: '$name[$i].trackIndex');
          expect(be[i].event.intValue, je[i].event.intValue,
              reason: '$name[$i].intValue');
          expect(be[i].event.stringValue, je[i].event.stringValue,
              reason: '$name[$i].stringValue');
          expect(be[i].event.audioPath, je[i].event.audioPath,
              reason: '$name[$i].audioPath');
          expect(be[i].time, closeTo(je[i].time, tol),
              reason: '$name[$i].time');
          expect(be[i].event.floatValue, closeTo(je[i].event.floatValue, tol),
              reason: '$name[$i].floatValue');
          expect(be[i].event.volume, closeTo(je[i].event.volume, tol),
              reason: '$name[$i].volume');
          expect(be[i].event.balance, closeTo(je[i].event.balance, tol),
              reason: '$name[$i].balance');
        }
      }
    });
  });
}

/// Loads and JSON-decodes a committed golden from `../conformance/goldens/`.
Map<String, dynamic> jsonDecodeGolden(String name) {
  final text = File('../conformance/goldens/$name').readAsStringSync();
  return jsonDecode(text) as Map<String, dynamic>;
}
