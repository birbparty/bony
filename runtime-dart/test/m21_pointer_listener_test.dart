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

void _expectInputSnapshotsMatch(
  List<_InputSnapshot> actual,
  List<_InputSnapshot> expected,
  String label,
) {
  expect(actual, hasLength(expected.length), reason: '$label inputs');
  for (var i = 0; i < expected.length; i++) {
    final a = actual[i];
    final e = expected[i];
    expect(a.name, e.name, reason: '$label.inputs[$i].name');
    expect(a.kind, e.kind, reason: '$label.inputs[$i].kind');
    switch (a.kind) {
      case StateMachineInputKind.bool_:
      case StateMachineInputKind.trigger:
        expect(a.value, e.value, reason: '$label.inputs[$i].value');
      case StateMachineInputKind.number:
        _expectClose(
            a.value as double, e.value as double, '$label.inputs[$i].value');
    }
  }
}

void _expectPoseMatches(MixedPose actual, MixedPose expected, String label) {
  expect(actual.scalars, hasLength(expected.scalars.length),
      reason: '$label.scalars');
  for (var i = 0; i < expected.scalars.length; i++) {
    final a = actual.scalars[i];
    final e = expected.scalars[i];
    expect(a.bone, e.bone, reason: '$label.scalars[$i].bone');
    expect(a.kind, e.kind, reason: '$label.scalars[$i].kind');
    _expectClose(a.value, e.value, '$label.scalars[$i].value');
  }
  expect(actual.vectors, hasLength(expected.vectors.length),
      reason: '$label.vectors');
  for (var i = 0; i < expected.vectors.length; i++) {
    final a = actual.vectors[i];
    final e = expected.vectors[i];
    expect(a.bone, e.bone, reason: '$label.vectors[$i].bone');
    expect(a.kind, e.kind, reason: '$label.vectors[$i].kind');
    _expectClose(a.x, e.x, '$label.vectors[$i].x');
    _expectClose(a.y, e.y, '$label.vectors[$i].y');
  }
  expect(actual.attachments, hasLength(expected.attachments.length),
      reason: '$label.attachments');
  for (var i = 0; i < expected.attachments.length; i++) {
    final a = actual.attachments[i];
    final e = expected.attachments[i];
    expect(a.slot, e.slot, reason: '$label.attachments[$i].slot');
    expect(a.attachment, e.attachment,
        reason: '$label.attachments[$i].attachment');
  }
  expect(actual.inherits, hasLength(expected.inherits.length),
      reason: '$label.inherits');
  for (var i = 0; i < expected.inherits.length; i++) {
    final a = actual.inherits[i];
    final e = expected.inherits[i];
    expect(a.bone, e.bone, reason: '$label.inherits[$i].bone');
    _expectClose(a.value.time, e.value.time, '$label.inherits[$i].time');
    expect(a.value.inheritRotation, e.value.inheritRotation,
        reason: '$label.inherits[$i].inheritRotation');
    expect(a.value.inheritScale, e.value.inheritScale,
        reason: '$label.inherits[$i].inheritScale');
    expect(a.value.inheritReflection, e.value.inheritReflection,
        reason: '$label.inherits[$i].inheritReflection');
    expect(a.value.transformMode, e.value.transformMode,
        reason: '$label.inherits[$i].transformMode');
  }
  expect(actual.colors, hasLength(expected.colors.length),
      reason: '$label.colors');
  for (var i = 0; i < expected.colors.length; i++) {
    final a = actual.colors[i];
    final e = expected.colors[i];
    expect(a.slot, e.slot, reason: '$label.colors[$i].slot');
    expect(a.kind, e.kind, reason: '$label.colors[$i].kind');
    _expectClose(a.color.r, e.color.r, '$label.colors[$i].r');
    _expectClose(a.color.g, e.color.g, '$label.colors[$i].g');
    _expectClose(a.color.b, e.color.b, '$label.colors[$i].b');
    _expectClose(a.color.a, e.color.a, '$label.colors[$i].a');
  }
  expect(actual.colors2, hasLength(expected.colors2.length),
      reason: '$label.colors2');
  for (var i = 0; i < expected.colors2.length; i++) {
    final a = actual.colors2[i];
    final e = expected.colors2[i];
    expect(a.slot, e.slot, reason: '$label.colors2[$i].slot');
    _expectClose(a.color.light.r, e.color.light.r, '$label.colors2[$i].r');
    _expectClose(a.color.light.g, e.color.light.g, '$label.colors2[$i].g');
    _expectClose(a.color.light.b, e.color.light.b, '$label.colors2[$i].b');
    _expectClose(a.color.light.a, e.color.light.a, '$label.colors2[$i].a');
    _expectClose(a.color.darkR, e.color.darkR, '$label.colors2[$i].darkR');
    _expectClose(a.color.darkG, e.color.darkG, '$label.colors2[$i].darkG');
    _expectClose(a.color.darkB, e.color.darkB, '$label.colors2[$i].darkB');
  }
  expect(actual.sequences, hasLength(expected.sequences.length),
      reason: '$label.sequences');
  for (var i = 0; i < expected.sequences.length; i++) {
    final a = actual.sequences[i];
    final e = expected.sequences[i];
    expect(a.slot, e.slot, reason: '$label.sequences[$i].slot');
    _expectClose(a.value.time, e.value.time, '$label.sequences[$i].time');
    expect(a.value.index, e.value.index, reason: '$label.sequences[$i].index');
    _expectClose(a.value.delay, e.value.delay, '$label.sequences[$i].delay');
    expect(a.value.mode, e.value.mode, reason: '$label.sequences[$i].mode');
  }
  expect(actual.deforms, hasLength(expected.deforms.length),
      reason: '$label.deforms');
  for (var i = 0; i < expected.deforms.length; i++) {
    final a = actual.deforms[i];
    final e = expected.deforms[i];
    expect(a.slot, e.slot, reason: '$label.deforms[$i].slot');
    expect(a.attachment, e.attachment, reason: '$label.deforms[$i].attachment');
    expect(a.deltas, hasLength(e.deltas.length),
        reason: '$label.deforms[$i].deltas');
    for (var d = 0; d < e.deltas.length; d++) {
      _expectClose(
          a.deltas[d].x, e.deltas[d].x, '$label.deforms[$i].deltas[$d].x');
      _expectClose(
          a.deltas[d].y, e.deltas[d].y, '$label.deforms[$i].deltas[$d].y');
    }
  }
}

void _expectLayersMatch(
  EvaluatedStateMachine actual,
  EvaluatedStateMachine expected,
  String label,
) {
  expect(actual.layers, hasLength(expected.layers.length),
      reason: '$label layers');
  for (var i = 0; i < expected.layers.length; i++) {
    final a = actual.layers[i];
    final e = expected.layers[i];
    expect(a.layer, e.layer, reason: '$label.layers[$i].layer');
    expect(a.state, e.state, reason: '$label.layers[$i].state');
    _expectClose(a.time, e.time, '$label.layers[$i].time');
    _expectPoseMatches(a.pose, e.pose, '$label.layers[$i].pose');
  }
}

void _expectEventsMatch(
  List<StateMachineListenerEvent> actual,
  List<StateMachineListenerEvent> expected,
  String label,
) {
  expect(actual, hasLength(expected.length), reason: '$label events');
  for (var i = 0; i < expected.length; i++) {
    final a = actual[i];
    final e = expected[i];
    expect(a.listener, e.listener, reason: '$label.events[$i].listener');
    expect(a.kind, e.kind, reason: '$label.events[$i].kind');
    expect(a.layer, e.layer, reason: '$label.events[$i].layer');
    expect(a.fromState, e.fromState, reason: '$label.events[$i].fromState');
    expect(a.toState, e.toState, reason: '$label.events[$i].toState');
    expect(a.slot, e.slot, reason: '$label.events[$i].slot');
    expect(a.targetKind, e.targetKind, reason: '$label.events[$i].targetKind');
    expect(a.target, e.target, reason: '$label.events[$i].target');
    expect(a.input, e.input, reason: '$label.events[$i].input');
    expect(a.inputKind, e.inputKind, reason: '$label.events[$i].inputKind');
    expect(a.boolValue, e.boolValue, reason: '$label.events[$i].boolValue');
    expect(a.hasBoolValue, e.hasBoolValue,
        reason: '$label.events[$i].hasBoolValue');
    _expectClose(a.numberValue, e.numberValue, '$label.events[$i].numberValue');
    expect(a.hasNumberValue, e.hasNumberValue,
        reason: '$label.events[$i].hasNumberValue');
    expect(a.triggerValue, e.triggerValue,
        reason: '$label.events[$i].triggerValue');
    _expectClose(a.pointerX, e.pointerX, '$label.events[$i].pointerX');
    _expectClose(a.pointerY, e.pointerY, '$label.events[$i].pointerY');
    expect(a.hasPointer, e.hasPointer, reason: '$label.events[$i].hasPointer');
  }
}

void _expectWorldsMatch(
  List<Affine2> actual,
  List<Affine2> expected,
  String label,
) {
  expect(actual, hasLength(expected.length), reason: '$label worlds');
  for (var i = 0; i < expected.length; i++) {
    final e = expected[i];
    _expectAffine(
      actual[i],
      {'a': e.a, 'b': e.b, 'c': e.c, 'd': e.d, 'tx': e.tx, 'ty': e.ty},
      '$label.worlds[$i]',
    );
  }
}

void _expectSlotsMatch(
    SkeletonData actual, SkeletonData expected, String label) {
  expect(actual.slots, hasLength(expected.slots.length),
      reason: '$label slots');
  for (var i = 0; i < expected.slots.length; i++) {
    final a = actual.slots[i];
    final e = expected.slots[i];
    expect(a.name, e.name, reason: '$label.slots[$i].name');
    expect(a.bone, e.bone, reason: '$label.slots[$i].bone');
    expect(a.attachment, e.attachment, reason: '$label.slots[$i].attachment');
  }
}

void _expectBatchesMatch(
  List<DrawBatch> actual,
  List<DrawBatch> expected,
  String label,
) {
  expect(actual, hasLength(expected.length), reason: '$label drawBatches');
  for (var i = 0; i < expected.length; i++) {
    final a = actual[i];
    final e = expected[i];
    expect(a.slot, e.slot, reason: '$label.drawBatches[$i].slot');
    expect(a.bone, e.bone, reason: '$label.drawBatches[$i].bone');
    expect(a.attachment, e.attachment,
        reason: '$label.drawBatches[$i].attachment');
    expect(a.blendMode, e.blendMode,
        reason: '$label.drawBatches[$i].blendMode');
    expect(a.texturePage, e.texturePage,
        reason: '$label.drawBatches[$i].texturePage');
    expect(a.clipId, e.clipId, reason: '$label.drawBatches[$i].clipId');
    _expectWorldsMatch([a.world], [e.world], '$label.drawBatches[$i]');
    expect(a.vertices, hasLength(e.vertices.length),
        reason: '$label.drawBatches[$i].vertices');
    for (var v = 0; v < e.vertices.length; v++) {
      final av = a.vertices[v];
      final ev = e.vertices[v];
      final vLabel = '$label.drawBatches[$i].vertices[$v]';
      _expectClose(av.x, ev.x, '$vLabel.x');
      _expectClose(av.y, ev.y, '$vLabel.y');
      _expectClose(av.u, ev.u, '$vLabel.u');
      _expectClose(av.v, ev.v, '$vLabel.v');
      _expectClose(av.r, ev.r, '$vLabel.r');
      _expectClose(av.g, ev.g, '$vLabel.g');
      _expectClose(av.b, ev.b, '$vLabel.b');
      _expectClose(av.a, ev.a, '$vLabel.a');
    }
    expect(a.indices, e.indices, reason: '$label.drawBatches[$i].indices');
  }
}

void _expectReplaySampleMatches(
  _ReplaySample actual,
  _ReplaySample expected,
  String label,
) {
  expect(actual.name, expected.name, reason: '$label.name');
  _expectClose(actual.time, expected.time, '$label.time');
  _expectInputSnapshotsMatch(actual.inputs, expected.inputs, label);
  _expectLayersMatch(actual.evaluated, expected.evaluated, label);
  _expectEventsMatch(actual.events, expected.events, label);
  _expectWorldsMatch(actual.worlds, expected.worlds, label);
  _expectSlotsMatch(actual.posed, expected.posed, label);
  _expectBatchesMatch(actual.batches, expected.batches, label);
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
  SkeletonData loadM21(String loader) => loader == 'bony'
      ? loadBonyJson(
          File('../conformance/assets/m21_pointer_listener_rig.bony')
              .readAsStringSync(),
        )
      : loadBonyBnb(
          File('../conformance/assets/bnb/m21_pointer_listener_rig.bnb')
              .readAsBytesSync(),
        );

  for (final loader in const ['bony', 'bnb']) {
    group('M21 pointer-listener story via .$loader loader', () {
      late SkeletonData base;
      late Map<String, _ReplaySample> replayed;

      setUpAll(() {
        base = loadM21(loader);
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
        final downEvents = replayed['down']!.events;
        expect(downEvents.map((e) => e.listener), [
          'box_down',
          'idle_exit',
          'idle_to_pressed',
          'pressed_enter',
        ]);
        expect(downEvents.first.kind, StateMachineListenerKind.pointerDown);
        expect(downEvents.skip(1).map((e) => e.kind), [
          StateMachineListenerKind.stateExit,
          StateMachineListenerKind.transition_,
          StateMachineListenerKind.stateEnter,
        ]);
        expect(replayed['move']!.events.map((e) => e.listener), ['point_move']);
        expect(replayed['up']!.events.map((e) => e.listener), ['point_up']);
        expect(replayed['exit']!.events.map((e) => e.listener), ['box_exit']);
        expect(replayed['down']!.evaluated.layers.single.state, 'pressed');
        final movePoint = worldPointAttachmentPose(
          replayed['move']!.posed,
          replayed['move']!.worlds,
          'button_point_slot',
          'spark_point',
        );
        final moveEvent = replayed['move']!.events.single;
        expect(moveEvent.targetKind, PointerHelperTargetKind.point);
        _expectClose(moveEvent.pointerX, movePoint.x, 'move pointerX');
        _expectClose(moveEvent.pointerY, movePoint.y, 'move pointerY');
        final upPoint = worldPointAttachmentPose(
          replayed['up']!.posed,
          replayed['up']!.worlds,
          'button_point_slot',
          'spark_point',
        );
        final upEvent = replayed['up']!.events.single;
        expect(upEvent.targetKind, PointerHelperTargetKind.point);
        _expectClose(upEvent.pointerX, upPoint.x, 'up pointerX');
        _expectClose(upEvent.pointerY, upPoint.y, 'up pointerY');
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
        final exitHover = replayed['exit']!
            .inputs
            .firstWhere((input) => input.name == 'hover');
        expect(exitHover.value, isFalse);
        final exitEvent = replayed['exit']!.events.single;
        expect(exitEvent.input, 'hover');
        expect(exitEvent.boolValue, isFalse);
        expect(exitEvent.hasBoolValue, isTrue);
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

  test('M21 pointer-listener replay output matches between JSON and BNB', () {
    final jsonReplay = {
      for (final sample in _replay(loadM21('bony'), samples))
        sample.name: sample,
    };
    final bnbReplay = {
      for (final sample in _replay(loadM21('bnb'), samples))
        sample.name: sample,
    };

    expect(bnbReplay.keys, jsonReplay.keys);
    for (final sample in samples) {
      _expectReplaySampleMatches(
        bnbReplay[sample.name]!,
        jsonReplay[sample.name]!,
        'bnb parity ${sample.name}',
      );
    }
  });
}
