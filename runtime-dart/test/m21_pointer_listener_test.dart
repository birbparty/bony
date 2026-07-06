// Dart M21 POINTER-LISTENER STORY conformance gate.
//
// Replays conformance/scripts/m21_pointer_listener_story.json against both the
// .bony and .bnb M21 assets. Each pointer sample dispatches against the current
// posed helper geometry, then advances the state machine while preserving the
// pointer event so lifecycle transition events appear in the same sample
// window. The resulting inputs, layers, listener events, world transforms,
// helper slot metadata, and draw-batch surface are matched to the committed
// m21_pointer_listener_* goldens within 1e-4.

import 'dart:convert';
import 'dart:io';

import 'package:bony/bony.dart';
import 'package:test/test.dart';

const double _tol = 1e-4;

typedef _StorySample = ({
  String name,
  double time,
  StateMachineListenerKind? pointerKind,
  double pointerX,
  double pointerY,
});

typedef _InputSnapshot = ({
  String name,
  StateMachineInputKind kind,
  Object value,
});

typedef _ReplaySample = ({
  String name,
  double time,
  List<_InputSnapshot> inputs,
  EvaluatedStateMachine evaluated,
  List<StateMachineListenerEvent> events,
  SkeletonData posed,
  List<Affine2> worlds,
  List<DrawBatch> batches,
});

void _expectClose(double actual, double expected, String label) {
  expect((actual - expected).abs(), lessThanOrEqualTo(_tol),
      reason: '$label: actual=$actual expected=$expected');
}

void _expectAffine(Affine2 a, Map<String, dynamic> g, String label) {
  _expectClose(a.a, (g['a'] as num).toDouble(), '$label.a');
  _expectClose(a.b, (g['b'] as num).toDouble(), '$label.b');
  _expectClose(a.c, (g['c'] as num).toDouble(), '$label.c');
  _expectClose(a.d, (g['d'] as num).toDouble(), '$label.d');
  _expectClose(a.tx, (g['tx'] as num).toDouble(), '$label.tx');
  _expectClose(a.ty, (g['ty'] as num).toDouble(), '$label.ty');
}

String _inputKindName(StateMachineInputKind kind) => switch (kind) {
      StateMachineInputKind.bool_ => 'bool',
      StateMachineInputKind.number => 'number',
      StateMachineInputKind.trigger => 'trigger',
    };

String _listenerKindName(StateMachineListenerKind kind) => switch (kind) {
      StateMachineListenerKind.transition_ => 'transition',
      _ => kind.name,
    };

StateMachineListenerKind _pointerKind(String kind) => switch (kind) {
      'pointerDown' => StateMachineListenerKind.pointerDown,
      'pointerUp' => StateMachineListenerKind.pointerUp,
      'pointerEnter' => StateMachineListenerKind.pointerEnter,
      'pointerExit' => StateMachineListenerKind.pointerExit,
      'pointerMove' => StateMachineListenerKind.pointerMove,
      _ => throw FormatException('unknown pointer kind: $kind'),
    };

List<_StorySample> _loadScriptSamples() {
  final script = jsonDecode(
    File('../conformance/scripts/m21_pointer_listener_story.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  return [
    for (final raw in (script['samples'] as List).cast<Map<String, dynamic>>())
      (
        name: raw['name'] as String,
        time: (raw['t'] as num).toDouble(),
        pointerKind: raw['pointer'] == null
            ? null
            : _pointerKind(
                (raw['pointer'] as Map<String, dynamic>)['kind'] as String),
        pointerX: raw['pointer'] == null
            ? 0.0
            : ((raw['pointer'] as Map<String, dynamic>)['x'] as num).toDouble(),
        pointerY: raw['pointer'] == null
            ? 0.0
            : ((raw['pointer'] as Map<String, dynamic>)['y'] as num).toDouble(),
      ),
  ];
}

Map<String, dynamic> _loadGolden(String sample) => jsonDecode(
      File('../conformance/goldens/m21_pointer_listener_$sample.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;

List<_InputSnapshot> _snapshotInputs(
  StateMachineRuntime runtime,
  StateMachineData machine,
) =>
    [
      for (final input in machine.inputs)
        (
          name: input.name,
          kind: input.kind,
          value: switch (input.kind) {
            StateMachineInputKind.bool_ => runtime.getBoolInput(input.name),
            StateMachineInputKind.number => runtime.getNumberInput(input.name),
            StateMachineInputKind.trigger =>
              runtime.getTriggerInput(input.name),
          },
        ),
    ];

List<_ReplaySample> _replay(SkeletonData base, List<_StorySample> samples) {
  final story = base.stateMachines.firstWhere((s) => s.name == 'pointer_story');
  final runtime = initStateMachineRuntime(story);
  final out = <_ReplaySample>[];
  var posed = base;
  var worlds = computeWorldTransforms(posed);
  var previousTime = 0.0;

  for (final sample in samples) {
    final pointerKind = sample.pointerKind;
    if (pointerKind != null) {
      runtime.clearEvents();
      runtime.dispatchPointerListeners(
        posed,
        worlds,
        'default',
        pointerKind,
        sample.pointerX,
        sample.pointerY,
      );
    }

    runtime.update(
      sample.time - previousTime,
      preserveEvents: pointerKind != null,
    );
    final evaluated = runtime.evaluate(base);
    posed = applyPose(base, evaluated.pose);
    worlds = computeWorldTransforms(posed);
    out.add((
      name: sample.name,
      time: sample.time,
      inputs: _snapshotInputs(runtime, story),
      evaluated: evaluated,
      events: List<StateMachineListenerEvent>.from(runtime.events),
      posed: posed,
      worlds: worlds,
      batches: buildDrawBatches(posed),
    ));
    previousTime = sample.time;
  }

  return out;
}

void _expectInputs(
  List<_InputSnapshot> actual,
  List<dynamic> expected,
  String label,
) {
  expect(actual, hasLength(expected.length), reason: '$label input count');
  for (var i = 0; i < expected.length; i++) {
    final e = expected[i] as Map<String, dynamic>;
    final a = actual[i];
    expect(a.name, e['name'], reason: '$label.inputs[$i].name');
    expect(_inputKindName(a.kind), e['kind'], reason: '$label.inputs[$i].kind');
    switch (a.kind) {
      case StateMachineInputKind.bool_:
      case StateMachineInputKind.trigger:
        expect(a.value as bool, e['value'] as bool,
            reason: '$label.inputs[$i].value');
      case StateMachineInputKind.number:
        _expectClose(a.value as double, (e['value'] as num).toDouble(),
            '$label.inputs[$i].value');
    }
  }
}

void _expectPose(
  MixedPose actual,
  Map<String, dynamic> expected,
  String label,
) {
  final scalars =
      (expected['scalars'] as List<dynamic>).cast<Map<String, dynamic>>();
  expect(actual.scalars, hasLength(scalars.length),
      reason: '$label.scalars count');
  for (var i = 0; i < scalars.length; i++) {
    final e = scalars[i];
    final a = actual.scalars[i];
    expect(a.bone, e['target'], reason: '$label.scalars[$i].target');
    expect(a.kind.name, e['kind'], reason: '$label.scalars[$i].kind');
    _expectClose(
        a.value, (e['value'] as num).toDouble(), '$label.scalars[$i].value');
  }
  expect(actual.vectors, hasLength((expected['vectors'] as List).length),
      reason: '$label.vectors count');
  expect(
      actual.attachments, hasLength((expected['attachments'] as List).length),
      reason: '$label.attachments count');
  expect(actual.inherits, hasLength((expected['inherits'] as List).length),
      reason: '$label.inherits count');
  expect(actual.colors, hasLength((expected['colors'] as List).length),
      reason: '$label.colors count');
  expect(actual.colors2, hasLength((expected['colors2'] as List).length),
      reason: '$label.colors2 count');
  expect(actual.sequences, hasLength((expected['sequences'] as List).length),
      reason: '$label.sequences count');
}

void _expectLayers(
  EvaluatedStateMachine actual,
  List<dynamic> expected,
  String label,
) {
  expect(actual.layers, hasLength(expected.length), reason: '$label layers');
  for (var i = 0; i < expected.length; i++) {
    final e = expected[i] as Map<String, dynamic>;
    final a = actual.layers[i];
    expect(a.layer, e['name'], reason: '$label.layers[$i].name');
    expect(a.state, e['state'], reason: '$label.layers[$i].state');
    _expectClose(
        a.time, (e['time'] as num).toDouble(), '$label.layers[$i].time');
    _expectPose(
        a.pose, e['pose'] as Map<String, dynamic>, '$label.layers[$i].pose');
  }
}

void _expectEvents(
  List<StateMachineListenerEvent> actual,
  List<dynamic> expected,
  String label,
) {
  expect(actual, hasLength(expected.length), reason: '$label events');
  for (var i = 0; i < expected.length; i++) {
    final e = expected[i] as Map<String, dynamic>;
    final a = actual[i];
    expect(a.listener, e['listener'], reason: '$label.events[$i].listener');
    expect(_listenerKindName(a.kind), e['kind'],
        reason: '$label.events[$i].kind');
    if (e.containsKey('layer')) {
      expect(a.layer, e['layer'], reason: '$label.events[$i].layer');
      expect(a.fromState, e['fromState'],
          reason: '$label.events[$i].fromState');
      expect(a.toState, e['toState'], reason: '$label.events[$i].toState');
    } else {
      expect(a.layer, isEmpty, reason: '$label.events[$i].layer absent');
      expect(a.fromState, isEmpty,
          reason: '$label.events[$i].fromState absent');
      expect(a.toState, isEmpty, reason: '$label.events[$i].toState absent');
    }
    if (e.containsKey('slot')) {
      expect(a.slot, e['slot'], reason: '$label.events[$i].slot');
      expect(a.targetKind.name, e['targetKind'],
          reason: '$label.events[$i].targetKind');
      expect(a.target, e['target'], reason: '$label.events[$i].target');
      expect(a.input, e['input'], reason: '$label.events[$i].input');
      expect(_inputKindName(a.inputKind), e['inputKind'],
          reason: '$label.events[$i].inputKind');
      _expectClose(a.pointerX, (e['pointerX'] as num).toDouble(),
          '$label.events[$i].pointerX');
      _expectClose(a.pointerY, (e['pointerY'] as num).toDouble(),
          '$label.events[$i].pointerY');
      expect(a.hasPointer, isTrue, reason: '$label.events[$i].hasPointer');
    } else {
      expect(a.hasPointer, isFalse,
          reason: '$label.events[$i].hasPointer absent');
      expect(a.slot, isEmpty, reason: '$label.events[$i].slot absent');
      expect(a.target, isEmpty, reason: '$label.events[$i].target absent');
      expect(a.input, isEmpty, reason: '$label.events[$i].input absent');
    }
    if (e.containsKey('boolValue')) {
      expect(a.hasBoolValue, isTrue, reason: '$label.events[$i].hasBoolValue');
      expect(a.boolValue, e['boolValue'],
          reason: '$label.events[$i].boolValue');
    } else {
      expect(a.hasBoolValue, isFalse,
          reason: '$label.events[$i].hasBoolValue absent');
    }
    if (e.containsKey('numberValue')) {
      expect(a.hasNumberValue, isTrue,
          reason: '$label.events[$i].hasNumberValue');
      _expectClose(a.numberValue, (e['numberValue'] as num).toDouble(),
          '$label.events[$i].numberValue');
    } else {
      expect(a.hasNumberValue, isFalse,
          reason: '$label.events[$i].hasNumberValue absent');
    }
    if (e.containsKey('triggerValue')) {
      expect(a.triggerValue, e['triggerValue'],
          reason: '$label.events[$i].triggerValue');
    } else {
      expect(a.triggerValue, isFalse,
          reason: '$label.events[$i].triggerValue absent');
    }
  }
}

void _expectWorlds(
  SkeletonData posed,
  List<Affine2> worlds,
  List<dynamic> expected,
  String label,
) {
  expect(worlds, hasLength(expected.length), reason: '$label bone count');
  final byName = {
    for (final b in expected.cast<Map<String, dynamic>>())
      b['name'] as String: b['world'] as Map<String, dynamic>,
  };
  for (var i = 0; i < posed.bones.length; i++) {
    final name = posed.bones[i].name;
    final g = byName[name];
    expect(g, isNotNull, reason: '$label missing bone: $name');
    _expectAffine(worlds[i], g!, '$label.bones[$name].world');
  }
}

void _expectSlots(SkeletonData posed, List<dynamic> expected, String label) {
  expect(posed.slots, hasLength(expected.length), reason: '$label slot count');
  for (var i = 0; i < expected.length; i++) {
    final e = expected[i] as Map<String, dynamic>;
    final a = posed.slots[i];
    expect(a.name, e['name'], reason: '$label.slots[$i].name');
    expect(a.bone, e['bone'], reason: '$label.slots[$i].bone');
    expect(a.attachment, e['attachment'],
        reason: '$label.slots[$i].attachment');
    _expectClose(1.0, (e['r'] as num).toDouble(), '$label.slots[$i].r');
    _expectClose(1.0, (e['g'] as num).toDouble(), '$label.slots[$i].g');
    _expectClose(1.0, (e['b'] as num).toDouble(), '$label.slots[$i].b');
    _expectClose(1.0, (e['a'] as num).toDouble(), '$label.slots[$i].a');
  }
}

void _expectDrawBatches(
  List<DrawBatch> actual,
  List<dynamic> expected,
  String label,
) {
  expect(actual, hasLength(expected.length), reason: '$label drawBatches');
  for (var i = 0; i < expected.length; i++) {
    final e = expected[i] as Map<String, dynamic>;
    final a = actual[i];
    expect(a.slot, e['slot'], reason: '$label.drawBatches[$i].slot');
    expect(a.bone, e['bone'], reason: '$label.drawBatches[$i].bone');
    expect(a.attachment, e['attachment'],
        reason: '$label.drawBatches[$i].attachment');
    expect(a.blendMode, e['blendMode'],
        reason: '$label.drawBatches[$i].blendMode');
    expect(a.texturePage, e['texturePage'],
        reason: '$label.drawBatches[$i].texturePage');
    expect(a.clipId, e['clipId'], reason: '$label.drawBatches[$i].clipId');
    _expectAffine(
      a.world,
      e['world'] as Map<String, dynamic>,
      '$label.drawBatches[$i].world',
    );
    final vertices = e['vertices'] as List<dynamic>;
    expect(a.vertices, hasLength(vertices.length),
        reason: '$label.drawBatches[$i].vertices');
    for (var v = 0; v < vertices.length; v++) {
      final ev = vertices[v] as Map<String, dynamic>;
      final av = a.vertices[v];
      final vLabel = '$label.drawBatches[$i].vertices[$v]';
      _expectClose(av.x, (ev['x'] as num).toDouble(), '$vLabel.x');
      _expectClose(av.y, (ev['y'] as num).toDouble(), '$vLabel.y');
      _expectClose(av.u, (ev['u'] as num).toDouble(), '$vLabel.u');
      _expectClose(av.v, (ev['v'] as num).toDouble(), '$vLabel.v');
      _expectClose(av.r, (ev['r'] as num).toDouble(), '$vLabel.r');
      _expectClose(av.g, (ev['g'] as num).toDouble(), '$vLabel.g');
      _expectClose(av.b, (ev['b'] as num).toDouble(), '$vLabel.b');
      _expectClose(av.a, (ev['a'] as num).toDouble(), '$vLabel.a');
    }
    expect(a.indices, (e['indices'] as List<dynamic>).cast<int>(),
        reason: '$label.drawBatches[$i].indices');
  }
}

void _expectGolden(
  SkeletonData base,
  _ReplaySample sample,
  Map<String, dynamic> golden,
) {
  final label = sample.name;
  expect(golden['format'], 'bony.numeric-golden.v1');
  expect(golden['skeleton'], base.header.name);
  expect(golden['version'], base.header.version);
  expect(golden['stateMachine'], 'pointer_story');
  expect(golden['sample'], sample.name);
  _expectClose(sample.time, (golden['time'] as num).toDouble(), '$label.time');
  _expectInputs(sample.inputs, golden['inputs'] as List<dynamic>, label);
  _expectLayers(sample.evaluated, golden['layers'] as List<dynamic>, label);
  _expectEvents(sample.events, golden['events'] as List<dynamic>, label);
  _expectWorlds(
      sample.posed, sample.worlds, golden['bones'] as List<dynamic>, label);
  _expectSlots(sample.posed, golden['slots'] as List<dynamic>, label);
  _expectDrawBatches(
      sample.batches, golden['drawBatches'] as List<dynamic>, label);
}

void main() {
  final samples = _loadScriptSamples();

  for (final loader in const ['bony', 'bnb']) {
    group('M21 pointer-listener story via .$loader loader', () {
      late SkeletonData base;
      late Map<String, _ReplaySample> replayed;

      setUpAll(() {
        base = loader == 'bony'
            ? loadBonyJson(
                File('../conformance/assets/m21_pointer_listener_rig.bony')
                    .readAsStringSync(),
              )
            : loadBonyBnb(
                File('../conformance/assets/bnb/m21_pointer_listener_rig.bnb')
                    .readAsBytesSync(),
              );
        replayed = {
          for (final sample in _replay(base, samples)) sample.name: sample,
        };
      });

      for (final sample in samples) {
        test('${sample.name} matches the committed golden', () {
          _expectGolden(base, replayed[sample.name]!, _loadGolden(sample.name));
        });
      }

      test('pointer story is non-vacuous across event and input channels', () {
        expect(replayed['rest']!.events, isEmpty);
        expect(replayed['enter']!.events.map((e) => e.listener), ['box_enter']);
        expect(replayed['down']!.events.map((e) => e.listener), [
          'box_down',
          'idle_exit',
          'idle_to_pressed',
          'pressed_enter',
        ]);
        expect(replayed['move']!.events.map((e) => e.listener), ['point_move']);
        expect(replayed['up']!.events.map((e) => e.listener), ['point_up']);
        expect(replayed['exit']!.events.map((e) => e.listener), ['box_exit']);
        expect(replayed['down']!.evaluated.layers.single.state, 'pressed');
        expect(
          replayed['move']!
              .inputs
              .firstWhere((input) => input.name == 'intensity')
              .value,
          closeTo(4.5, _tol),
        );
        expect(
          replayed['up']!
              .inputs
              .firstWhere((input) => input.name == 'pulse')
              .value,
          isTrue,
        );
      });

      test('runtime trigger getter and event clear expose only runtime state',
          () {
        final story =
            base.stateMachines.firstWhere((s) => s.name == 'pointer_story');
        final runtime = initStateMachineRuntime(story);
        final worlds = computeWorldTransforms(base);

        expect(runtime.getTriggerInput('pulse'), isFalse);
        expect(() => runtime.getTriggerInput('pressed'), throwsFormatException);
        expect(() => runtime.getTriggerInput('missing'), throwsFormatException);

        runtime.dispatchPointerListeners(
          base,
          worlds,
          'default',
          StateMachineListenerKind.pointerEnter,
          40,
          0,
        );
        expect(runtime.events.map((e) => e.listener), ['box_enter']);
        runtime.clearEvents();
        expect(runtime.events, isEmpty);
        expect(runtime.currentState('main'), 'idle');
        expect(runtime.getBoolInput('hover'), isTrue);
      });
    });
  }
}
