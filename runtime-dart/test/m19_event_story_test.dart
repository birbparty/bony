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

  Map<String, List<DispatchedEvent>> replayStateMachine(SkeletonData base) {
    final story = base.stateMachines.firstWhere((s) => s.name == 'event_story');
    final rt = initStateMachineRuntime(story);
    final out = <String, List<DispatchedEvent>>{};
    var prevTime = 0.0;
    for (final (name, t) in samples) {
      rt.update(t - prevTime);
      rt.evaluate(base);
      out[name] = List<DispatchedEvent>.from(rt.animationEvents);
      prevTime = t;
    }
    return out;
  }

  SkeletonData copySkeleton(SkeletonData data) => SkeletonData(
        header: data.header,
        bones: data.bones,
        slots: data.slots,
        regions: data.regions,
        paths: data.paths,
        pathAttachments: data.pathAttachments,
        clippingAttachments: data.clippingAttachments,
        meshAttachments: data.meshAttachments,
        ikConstraints: data.ikConstraints,
        transformConstraints: data.transformConstraints,
        physicsConstraints: data.physicsConstraints,
        animations: data.animations,
        parameters: data.parameters,
        deformers: data.deformers,
        stateMachines: data.stateMachines,
        deformOverrides: data.deformOverrides,
      );

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

    test('state-machine evaluate path surfaces animationEvents', () {
      final fired = replayStateMachine(fromJson);
      expectEventsMatchGolden(fired['rest']!, 'rest');
      expectEventsMatchGolden(fired['mid']!, 'mid');
      expectEventsMatchGolden(fired['end']!, 'end');
    });

    test('state-machine evaluate is idempotent for animationEvents', () {
      final story = fromJson.stateMachines.firstWhere((s) => s.name == 'event_story');
      final rt = initStateMachineRuntime(story)..update(0.5);
      rt.evaluate(fromJson);
      final first = List<DispatchedEvent>.from(rt.animationEvents);
      rt.evaluate(fromJson);
      expect(rt.animationEvents.map((e) => e.name), first.map((e) => e.name));
      expectEventsMatchGolden(rt.animationEvents, 'mid');
    });

    test('state-machine bridge preserves event window across data swaps', () {
      final story = fromJson.stateMachines.firstWhere((s) => s.name == 'event_story');
      final rt = initStateMachineRuntime(story);
      rt.update(0.5);
      rt.evaluate(fromJson);
      expect(rt.animationEvents.map((e) => e.name), ['hit', 'hit2']);

      rt.update(0.5);
      rt.evaluate(copySkeleton(fromJson));
      expect(rt.animationEvents.map((e) => e.name), ['land']);
      expectEventsMatchGolden(rt.animationEvents, 'end');
    });
  });

  // Unit coverage for the dispatch primitive on branches the m19 rig (single
  // non-looping, non-mixing clip) does not exercise: mix-in threshold gating,
  // cross-timeline co-timed ordering, and the loop-aware cycle walk. Uses
  // synthetic clips, not goldens.
  group('mixer event dispatch primitive', () {
    final data = SkeletonData(
      header: const SkeletonHeader(name: 'synthetic', version: '1.0.0'),
      bones: const [],
      slots: const [],
      regions: const [],
      paths: const [],
      pathAttachments: const [],
    );

    AnimationClip eventClip(String name, double duration, List<EventKeyframe> keys) =>
        AnimationClip(
          name: name,
          duration: duration,
          boneTimelines: const [],
          eventTimelines: [EventTimeline(keys: keys)],
        );

    test('events fired entirely below the mix-in threshold are suppressed', () {
      // eventThreshold defaults to 0.5, mixDuration 1.0 -> thresholdTime 0.5.
      // Advancing mixTime only to 0.2 (< 0.5) must dispatch nothing, even though
      // the event at t=0.1 falls in the (0, 0.2] window. (Regression: an earlier
      // draft dispatched the whole window here, defeating eventThreshold.)
      final a = eventClip('a', 1.0, const []);
      final b = eventClip('b', 1.0,
          [EventKeyframe(time: 0.1, event: const EventData(name: 'early'))]);
      final anim = AnimationState(data)
        ..setAnimation(0, a)
        ..setAnimation(0, b, mixDuration: 1.0);
      anim.update(0.2);
      expect(anim.events, isEmpty);
    });

    test('mix-in dispatches only from the threshold-crossing point', () {
      // Single advance 0 -> 1.0 crosses the threshold at mixTime 0.5; the
      // dispatch window is [0.5, 1.0], so the below-threshold event (0.1) is
      // suppressed and only the above-threshold event (0.6) fires.
      final a = eventClip('a', 1.0, const []);
      final b = eventClip('b', 1.0, [
        EventKeyframe(time: 0.1, event: const EventData(name: 'early')),
        EventKeyframe(time: 0.6, event: const EventData(name: 'late')),
      ]);
      final anim = AnimationState(data)
        ..setAnimation(0, a)
        ..setAnimation(0, b, mixDuration: 1.0);
      anim.update(1.0);
      expect(anim.events.map((e) => e.name), ['late']);
    });

    test('co-timed events across timelines sort by time then insertion order', () {
      final clip = AnimationClip(
        name: 'c',
        duration: 1.0,
        boneTimelines: const [],
        eventTimelines: [
          EventTimeline(keys: [
            EventKeyframe(time: 0.5, event: const EventData(name: 't0a')),
            EventKeyframe(time: 0.9, event: const EventData(name: 't0b')),
          ]),
          EventTimeline(keys: [
            EventKeyframe(time: 0.5, event: const EventData(name: 't1a')),
          ]),
        ],
      );
      final anim = AnimationState(data)..setAnimation(0, clip);
      anim.update(1.0);
      // Row-major insertion order: t0a(0.5,#0), t0b(0.9,#1), t1a(0.5,#2).
      // Sorted by (time, order): t0a, t1a, then t0b.
      expect(anim.events.map((e) => e.name), ['t0a', 't1a', 't0b']);
    });

    test('looping clip fires events across every crossed cycle', () {
      final clip = eventClip('loopy', 1.0,
          [EventKeyframe(time: 0.5, event: const EventData(name: 'beat'))]);
      final anim = AnimationState(data)..setAnimation(0, clip, loop: true);
      anim.update(2.0); // (0, 2.0], duration 1.0 -> beats at 0.5 and 1.5
      expect(anim.events.map((e) => e.name), ['beat', 'beat']);
      expect(anim.events.map((e) => e.time), [0.5, 1.5]);
    });
  });

  group('M19 event rig .bony-vs-.bnb parity', () {
    test('dispatched events are identical from .bony and .bnb', () {
      final fromJson = loadBonyJson(
          File('../conformance/assets/m19_event_rig.bony').readAsStringSync());
      final fromBnb = loadBonyBnb(
          File('../conformance/assets/bnb/m19_event_rig.bnb').readAsBytesSync());
      final j = replayStateMachine(fromJson);
      final b = replayStateMachine(fromBnb);
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
