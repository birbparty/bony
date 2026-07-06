// Dart M8 state machine: parsing, runtime, transitions, listeners, evaluate.
//
// Tests run from runtime-dart/ so ../conformance/ resolves to repo root.

import 'dart:io';
import 'dart:typed_data' show ByteData, Endian, Uint8List;
import 'package:test/test.dart';
import 'package:bony/bony.dart';

void _writeVaruint(List<int> out, int value) {
  var v = value;
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
}

void _writeString(List<int> out, String value) {
  final units = value.codeUnits;
  _writeVaruint(out, units.length);
  out.addAll(units);
}

void _writeProp(List<int> out, int key, List<int> payload) {
  _writeVaruint(out, key);
  _writeVaruint(out, payload.length);
  out.addAll(payload);
}

List<int> _str(int index) => _varuintBytes(index);

List<int> _varuintBytes(int value) {
  final out = <int>[];
  _writeVaruint(out, value);
  return out;
}

List<int> _boolBytes(bool value) => [value ? 1 : 0];

List<int> _f32Bytes(double value) {
  final bd = ByteData(4)..setFloat32(0, value, Endian.little);
  return [bd.getUint8(0), bd.getUint8(1), bd.getUint8(2), bd.getUint8(3)];
}

List<int> _polygonBytes(List<double> vertices) {
  final out = <int>[];
  _writeVaruint(out, vertices.length ~/ 2);
  for (final value in vertices) {
    out.addAll(_f32Bytes(value));
  }
  return out;
}

Uint8List _pointerListenerBnb({
  required int inputKind,
  required int listenerKind,
  required int helperKind,
  String helperTarget = 'tip',
  List<void Function(List<int>)> listenerExtraProps = const [],
  bool includeHitRadius = true,
  double hitRadius = 1,
  bool includeBoolValue = true,
  bool includeNumberValue = false,
  int slotIndex = 0,
  int inputIndex = 0,
}) {
  final strings = [
    'pointer',
    'root',
    'tip_slot',
    'tip',
    'idle',
    'ui',
    'input',
    helperTarget,
    'button_hit',
  ];
  final out = <int>[
    0x42, 0x4f, 0x4e, 0x59, // BONY
    0x00, // version
    0x02, // string table present
    0x00, // empty ToC
  ];
  _writeVaruint(out, strings.length);
  for (final value in strings) {
    _writeString(out, value);
  }

  void object(int typeKey, List<void Function(List<int>)> props) {
    _writeVaruint(out, typeKey);
    for (final prop in props) {
      prop(out);
    }
    out.add(0);
  }

  void prop(int key, List<int> payload) {
    _writeProp(out, key, payload);
  }

  object(1, [(out) => prop(1, _str(0))]); // skeleton
  object(2, [(out) => prop(1, _str(1))]); // bone
  object(1000, [
    (out) => prop(1, _str(2)),
    (out) => prop(1012, _str(1)),
    (out) => prop(1013, _str(3)),
  ]);
  object(1002, [
    (out) => prop(1, _str(3)),
    (out) => prop(1000, _f32Bytes(0)),
    (out) => prop(1001, _f32Bytes(0)),
    (out) => prop(1002, _f32Bytes(0)),
  ]);
  object(1003, [
    (out) => prop(1, _str(8)),
    (out) => prop(3000, _polygonBytes([-1, -1, 1, -1, 1, 1, -1, 1])),
  ]);
  object(2000, [(out) => prop(1, _str(4))]); // animation
  object(7000, [(out) => prop(1, _str(5))]); // state machine
  object(7001, [
    (out) => prop(1, _str(6)),
    (out) => prop(7000, _varuintBytes(inputKind)),
  ]);
  object(7002, [(out) => prop(1, _str(4))]); // layer
  object(7003, [
    (out) => prop(1, _str(4)),
    (out) => prop(7020, _varuintBytes(0)),
    (out) => prop(7021, _varuintBytes(0)),
  ]);
  object(7007, [
    (out) => prop(1, _str(6)),
    (out) => prop(7060, _varuintBytes(listenerKind)),
    (out) => prop(7064, _varuintBytes(slotIndex)),
    (out) => prop(7065, _varuintBytes(helperKind)),
    (out) => prop(7066, _str(7)),
    (out) => prop(7067, _varuintBytes(inputIndex)),
    if (includeBoolValue) (out) => prop(7068, _boolBytes(true)),
    if (includeNumberValue) (out) => prop(7069, _f32Bytes(1.25)),
    if (includeHitRadius) (out) => prop(7070, _f32Bytes(hitRadius)),
    ...listenerExtraProps,
  ]);
  out.add(0);
  return Uint8List.fromList(out);
}

void main() {
  late SkeletonData data;
  late SkeletonData bnbData;
  late StateMachineData sm;
  late StateMachineData bnbSm;

  setUpAll(() {
    data = loadBonyJson(
      File('../conformance/assets/m8_rig.bony').readAsStringSync(),
    );
    bnbData = loadBonyBnb(
      File('../conformance/assets/bnb/m8_rig.bnb').readAsBytesSync(),
    );
    expect(data.stateMachines, hasLength(1),
        reason: 'expected one state machine');
    expect(bnbData.stateMachines, hasLength(1),
        reason: 'expected one binary state machine');
    sm = data.stateMachines[0];
    bnbSm = bnbData.stateMachines[0];
  });

  // --- Parsing ---

  List<String> _inputSurface(StateMachineData machine) => [
        for (final input in machine.inputs)
          '${input.name}:${input.kind.name}:${input.defaultBool}:${input.defaultNumber}',
      ];

  List<String> _layerSurface(StateMachineData machine) => [
        for (final layer in machine.layers)
          '${layer.name}:${layer.initialState}',
      ];

  List<String> _stateSurface(StateMachineData machine) => [
        for (final layer in machine.layers)
          for (final state in layer.states)
            '${layer.name}:${state.name}:${state.kind.name}:${state.clipName}:${state.loop}:${state.blendInput}:'
                '${state.blendClips.map((c) => '${c.clipName}/${c.value}/${c.loop}').join('|')}',
      ];

  List<String> _transitionSurface(StateMachineData machine) => [
        for (final layer in machine.layers)
          for (final transition in layer.transitions)
            '${layer.name}:${transition.fromState}->${transition.toState}:'
                '${transition.conditions.map((c) => '${c.input}/${c.kind.name}/${c.boolValue}/${c.numberValue}').join('|')}',
      ];

  List<String> _listenerSurface(StateMachineData machine) => [
        for (final listener in machine.listeners)
          '${listener.name}:${listener.kind.name}:${listener.layer}:${listener.fromState}:${listener.toState}:'
              '${listener.slot}:${listener.targetKind.name}:${listener.target}:${listener.hitRadius}:${listener.input}:${listener.boolValue}:${listener.numberValue}',
      ];

  group('M8 state machine parsed', () {
    test('machine name', () {
      expect(sm.name, 'gesture');
    });

    test('.bnb machine graph matches JSON', () {
      expect(bnbData.animations.map((a) => a.name),
          data.animations.map((a) => a.name));
      expect(bnbSm.name, sm.name);
      expect(_inputSurface(bnbSm), _inputSurface(sm));
      expect(_layerSurface(bnbSm), _layerSurface(sm));
      expect(_stateSurface(bnbSm), _stateSurface(sm));
      expect(_transitionSurface(bnbSm), _transitionSurface(sm));
      expect(_listenerSurface(bnbSm), _listenerSurface(sm));
    });

    test('3 inputs', () {
      expect(sm.inputs, hasLength(3));
    });

    test('input kinds', () {
      final byName = {for (final i in sm.inputs) i.name: i};
      expect(byName['wave']!.kind, StateMachineInputKind.bool_);
      expect(byName['speed']!.kind, StateMachineInputKind.number);
      expect(byName['jump']!.kind, StateMachineInputKind.trigger);
    });

    test('speed default 0.0', () {
      final speed = sm.inputs.firstWhere((i) => i.name == 'speed');
      expect(speed.defaultNumber, 0.0);
    });

    test('2 layers', () {
      expect(sm.layers, hasLength(2));
    });

    test('body layer initial state', () {
      final body = sm.layers.firstWhere((l) => l.name == 'body');
      expect(body.initialState, 'idle');
    });

    test('body layer has 2 states', () {
      final body = sm.layers.firstWhere((l) => l.name == 'body');
      expect(body.states, hasLength(2));
    });

    test('body layer move state is blend1d', () {
      final body = sm.layers.firstWhere((l) => l.name == 'body');
      final move = body.states.firstWhere((s) => s.name == 'move');
      expect(move.kind, StateMachineStateKind.blend1d);
      expect(move.blendInput, 'speed');
      expect(move.blendClips, hasLength(2));
    });

    test('body layer has 2 transitions', () {
      final body = sm.layers.firstWhere((l) => l.name == 'body');
      expect(body.transitions, hasLength(2));
    });

    test('face layer initial state defaults to first', () {
      final face = sm.layers.firstWhere((l) => l.name == 'face');
      expect(face.initialState, 'normal');
    });

    test('3 listeners', () {
      expect(sm.listeners, hasLength(3));
    });

    test('move_enter is stateEnter for body→move', () {
      final listener = sm.listeners.firstWhere((l) => l.name == 'move_enter');
      expect(listener.kind, StateMachineListenerKind.stateEnter);
      expect(listener.layer, 'body');
      expect(listener.toState, 'move');
    });

    test('idle_exit is stateExit for idle', () {
      final listener = sm.listeners.firstWhere((l) => l.name == 'idle_exit');
      expect(listener.kind, StateMachineListenerKind.stateExit);
      expect(listener.layer, 'body');
      expect(listener.fromState, 'idle');
    });

    test('idle_to_move is transition listener', () {
      final listener = sm.listeners.firstWhere((l) => l.name == 'idle_to_move');
      expect(listener.kind, StateMachineListenerKind.transition_);
      expect(listener.layer, 'body');
      expect(listener.fromState, 'idle');
      expect(listener.toState, 'move');
    });
  });

  // --- Runtime init ---

  group('M8 runtime init', () {
    test('initial body state is idle', () {
      final rt = initStateMachineRuntime(sm);
      expect(rt.currentState('body'), 'idle');
    });

    test('initial face state is normal', () {
      final rt = initStateMachineRuntime(sm);
      expect(rt.currentState('face'), 'normal');
    });

    test('wave default false', () {
      final rt = initStateMachineRuntime(sm);
      expect(rt.getBoolInput('wave'), false);
    });

    test('speed default 0.0', () {
      final rt = initStateMachineRuntime(sm);
      expect(rt.getNumberInput('speed'), 0.0);
    });

    test('initial layer time is 0', () {
      final rt = initStateMachineRuntime(sm);
      expect(rt.layerTime('body'), 0.0);
    });

    test('update accumulates layer time through quantizeF32', () {
      final rt = initStateMachineRuntime(sm);
      rt.update(0.1);
      rt.update(0.1);
      // f32-quantized accumulation differs from float64 sum 0.2
      final expected = quantizeF32(quantizeF32(0.1) + quantizeF32(0.1));
      expect(rt.layerTime('body'), expected);
    });
  });

  // --- Input setters ---

  group('M8 input setters', () {
    test('setBoolInput wave=true', () {
      final rt = initStateMachineRuntime(sm);
      rt.setBoolInput('wave', true);
      expect(rt.getBoolInput('wave'), true);
    });

    test('setNumberInput speed=0.7 stores quantized value', () {
      final rt = initStateMachineRuntime(sm);
      rt.setNumberInput('speed', 0.7);
      expect(rt.getNumberInput('speed'), quantizeF32(0.7));
    });

    test('fireTrigger consumes after transition', () {
      final rt = initStateMachineRuntime(sm);
      rt.fireTrigger('jump');
      rt.update(0.0);
      // After transition, trigger is consumed and face is in jump_pose.
      expect(rt.currentState('face'), 'jump_pose');
    });
  });

  // --- Transitions ---

  group('M8 transitions', () {
    test('wave=true triggers idle→move', () {
      final rt = initStateMachineRuntime(sm);
      rt.setBoolInput('wave', true);
      rt.update(0.0);
      expect(rt.currentState('body'), 'move');
    });

    test('wave=false from move triggers move→idle', () {
      final rt = initStateMachineRuntime(sm);
      rt.setBoolInput('wave', true);
      rt.update(0.0);
      expect(rt.currentState('body'), 'move');
      rt.setBoolInput('wave', false);
      rt.update(0.0);
      expect(rt.currentState('body'), 'idle');
    });

    test('no transition when condition not met', () {
      final rt = initStateMachineRuntime(sm);
      rt.update(1.0);
      expect(rt.currentState('body'), 'idle');
    });

    test('transition resets layer time', () {
      final rt = initStateMachineRuntime(sm);
      rt.update(1.0);
      expect(rt.layerTime('body'), greaterThan(0.0));
      rt.setBoolInput('wave', true);
      rt.update(0.0);
      expect(rt.layerTime('body'), 0.0);
    });

    test('body transition does not affect face', () {
      final rt = initStateMachineRuntime(sm);
      rt.setBoolInput('wave', true);
      rt.update(0.0);
      expect(rt.currentState('body'), 'move');
      expect(rt.currentState('face'), 'normal');
    });
  });

  // --- Listener events ---

  group('M8 listener events', () {
    test('idle→move fires stateExit, transition, stateEnter', () {
      final rt = initStateMachineRuntime(sm);
      rt.setBoolInput('wave', true);
      rt.update(0.0);
      final names = rt.events.map((e) => e.listener).toSet();
      expect(names, containsAll(['idle_exit', 'idle_to_move', 'move_enter']));
    });

    test('lifecycle event payload fields remain compatible', () {
      final rt = initStateMachineRuntime(sm);
      rt.setBoolInput('wave', true);
      rt.update(0.0);
      expect(rt.events.map((event) => event.listener), [
        'idle_exit',
        'idle_to_move',
        'move_enter',
      ]);
      final byName = {for (final event in rt.events) event.listener: event};

      final exit = byName['idle_exit']!;
      expect(exit.kind, StateMachineListenerKind.stateExit);
      expect(exit.layer, 'body');
      expect(exit.fromState, 'idle');
      expect(exit.toState, 'move');

      final transition = byName['idle_to_move']!;
      expect(transition.kind, StateMachineListenerKind.transition_);
      expect(transition.layer, 'body');
      expect(transition.fromState, 'idle');
      expect(transition.toState, 'move');

      final enter = byName['move_enter']!;
      expect(enter.kind, StateMachineListenerKind.stateEnter);
      expect(enter.layer, 'body');
      expect(enter.fromState, 'idle');
      expect(enter.toState, 'move');
    });

    test('lifecycle event constructor keeps pointer fields defaulted', () {
      const event = StateMachineListenerEvent(
        listener: 'move_enter',
        kind: StateMachineListenerKind.stateEnter,
        layer: 'body',
        fromState: 'idle',
        toState: 'move',
      );

      expect(event.listener, 'move_enter');
      expect(event.kind, StateMachineListenerKind.stateEnter);
      expect(event.layer, 'body');
      expect(event.fromState, 'idle');
      expect(event.toState, 'move');
      expect(event.slot, '');
      expect(event.targetKind, PointerHelperTargetKind.point);
      expect(event.target, '');
      expect(event.input, '');
      expect(event.inputKind, StateMachineInputKind.bool_);
      expect(event.boolValue, isFalse);
      expect(event.hasBoolValue, isFalse);
      expect(event.numberValue, 0.0);
      expect(event.hasNumberValue, isFalse);
      expect(event.triggerValue, isFalse);
      expect(event.pointerX, 0.0);
      expect(event.pointerY, 0.0);
      expect(event.hasPointer, isFalse);
    });

    test(
        'pointer listener events can represent bool, number, and trigger payloads',
        () {
      const boolEvent = StateMachineListenerEvent(
        listener: 'box_down',
        kind: StateMachineListenerKind.pointerDown,
        layer: '',
        fromState: '',
        toState: '',
        slot: 'button_box_slot',
        targetKind: PointerHelperTargetKind.boundingBox,
        target: 'button_hit',
        input: 'pressed',
        inputKind: StateMachineInputKind.bool_,
        boolValue: true,
        hasBoolValue: true,
        pointerX: 12.5,
        pointerY: -3.25,
        hasPointer: true,
      );
      expect(boolEvent.layer, '');
      expect(boolEvent.slot, 'button_box_slot');
      expect(boolEvent.targetKind, PointerHelperTargetKind.boundingBox);
      expect(boolEvent.target, 'button_hit');
      expect(boolEvent.input, 'pressed');
      expect(boolEvent.inputKind, StateMachineInputKind.bool_);
      expect(boolEvent.boolValue, isTrue);
      expect(boolEvent.hasBoolValue, isTrue);
      expect(boolEvent.hasNumberValue, isFalse);
      expect(boolEvent.triggerValue, isFalse);
      expect(boolEvent.pointerX, 12.5);
      expect(boolEvent.pointerY, -3.25);
      expect(boolEvent.hasPointer, isTrue);

      const numberEvent = StateMachineListenerEvent(
        listener: 'point_move',
        kind: StateMachineListenerKind.pointerMove,
        layer: '',
        fromState: '',
        toState: '',
        slot: 'button_point_slot',
        targetKind: PointerHelperTargetKind.point,
        target: 'spark_point',
        input: 'intensity',
        inputKind: StateMachineInputKind.number,
        numberValue: 4.5,
        hasNumberValue: true,
        pointerX: 3,
        pointerY: 4,
        hasPointer: true,
      );
      expect(numberEvent.inputKind, StateMachineInputKind.number);
      expect(numberEvent.hasBoolValue, isFalse);
      expect(numberEvent.numberValue, 4.5);
      expect(numberEvent.hasNumberValue, isTrue);
      expect(numberEvent.hasPointer, isTrue);

      const triggerEvent = StateMachineListenerEvent(
        listener: 'point_up',
        kind: StateMachineListenerKind.pointerUp,
        layer: '',
        fromState: '',
        toState: '',
        slot: 'button_point_slot',
        targetKind: PointerHelperTargetKind.point,
        target: 'spark_point',
        input: 'pulse',
        inputKind: StateMachineInputKind.trigger,
        triggerValue: true,
        pointerX: 3,
        pointerY: 4,
        hasPointer: true,
      );
      expect(triggerEvent.inputKind, StateMachineInputKind.trigger);
      expect(triggerEvent.hasBoolValue, isFalse);
      expect(triggerEvent.hasNumberValue, isFalse);
      expect(triggerEvent.triggerValue, isTrue);
      expect(triggerEvent.hasPointer, isTrue);
    });

    test('events cleared on next update', () {
      final rt = initStateMachineRuntime(sm);
      rt.setBoolInput('wave', true);
      rt.update(0.0);
      expect(rt.events, isNotEmpty);
      rt.update(0.1);
      expect(rt.events, isEmpty);
    });
  });

  group('M21 pointer listener dispatch', () {
    late SkeletonData pointerData;
    late StateMachineData pointerMachine;

    setUpAll(() {
      pointerData = loadBonyJson(
        File('../conformance/assets/m21_pointer_listener_rig.bony')
            .readAsStringSync(),
      );
      pointerMachine = pointerData.stateMachines.single;
    });

    test('rejects non-pointer kinds and non-finite coordinates', () {
      final rt = initStateMachineRuntime(pointerMachine);
      final worlds = computeWorldTransforms(pointerData);

      expect(
        () => rt.dispatchPointerListeners(
          pointerData,
          worlds,
          'default',
          StateMachineListenerKind.stateEnter,
          40,
          0,
        ),
        throwsFormatException,
      );
      expect(
        () => rt.dispatchPointerListeners(
          pointerData,
          worlds,
          'default',
          StateMachineListenerKind.pointerDown,
          double.nan,
          0,
        ),
        throwsFormatException,
      );
      expect(
        () => rt.dispatchPointerListeners(
          pointerData,
          worlds,
          'default',
          StateMachineListenerKind.pointerDown,
          40,
          double.infinity,
        ),
        throwsFormatException,
      );
    });

    test(
        'mutates bool input and preserves pointer event before lifecycle events',
        () {
      final rt = initStateMachineRuntime(pointerMachine);
      final worlds = computeWorldTransforms(pointerData);

      rt.dispatchPointerListeners(
        pointerData,
        worlds,
        'default',
        StateMachineListenerKind.pointerDown,
        40,
        0,
      );

      expect(rt.getBoolInput('pressed'), isTrue);
      expect(rt.animationEvents, isEmpty);
      expect(rt.events.map((event) => event.listener), ['box_down']);
      final pointerEvent = rt.events.single;
      expect(pointerEvent.kind, StateMachineListenerKind.pointerDown);
      expect(pointerEvent.slot, 'button_box_slot');
      expect(pointerEvent.targetKind, PointerHelperTargetKind.boundingBox);
      expect(pointerEvent.target, 'button_hit');
      expect(pointerEvent.input, 'pressed');
      expect(pointerEvent.inputKind, StateMachineInputKind.bool_);
      expect(pointerEvent.boolValue, isTrue);
      expect(pointerEvent.hasBoolValue, isTrue);
      expect(pointerEvent.hasNumberValue, isFalse);
      expect(pointerEvent.triggerValue, isFalse);
      expect(pointerEvent.pointerX, 40);
      expect(pointerEvent.pointerY, 0);
      expect(pointerEvent.hasPointer, isTrue);

      rt.update(0.0, preserveEvents: true);
      expect(rt.currentState('main'), 'pressed');
      expect(rt.events.map((event) => event.listener), [
        'box_down',
        'idle_exit',
        'idle_to_pressed',
        'pressed_enter',
      ]);

      rt.update(0.0);
      expect(rt.events, isEmpty);
    });

    test('mutates number and trigger inputs with pointer payloads', () {
      final rt = initStateMachineRuntime(pointerMachine);
      final worlds = computeWorldTransforms(pointerData);

      rt.dispatchPointerListeners(
        pointerData,
        worlds,
        'default',
        StateMachineListenerKind.pointerMove,
        60,
        0,
      );
      expect(rt.getNumberInput('intensity'), closeTo(4.5, 1e-9));
      final numberEvent = rt.events.single;
      expect(numberEvent.listener, 'point_move');
      expect(numberEvent.inputKind, StateMachineInputKind.number);
      expect(numberEvent.numberValue, closeTo(4.5, 1e-9));
      expect(numberEvent.hasNumberValue, isTrue);
      expect(numberEvent.hasBoolValue, isFalse);
      expect(numberEvent.hasPointer, isTrue);

      rt.update(0.0);
      rt.dispatchPointerListeners(
        pointerData,
        worlds,
        'default',
        StateMachineListenerKind.pointerUp,
        60,
        0,
      );
      final triggerEvent = rt.events.single;
      expect(triggerEvent.listener, 'point_up');
      expect(triggerEvent.inputKind, StateMachineInputKind.trigger);
      expect(triggerEvent.triggerValue, isTrue);
      expect(triggerEvent.hasBoolValue, isFalse);
      expect(triggerEvent.hasNumberValue, isFalse);
      rt.update(0.0, preserveEvents: true);
      expect(rt.events.map((event) => event.listener), ['point_up']);
    });

    test('keeps multiple matching pointer listeners in declaration order', () {
      final orderedData = loadBonyJson('''
      {
        "skeleton": {"name": "ordered-pointer"},
        "bones": [{"name": "root"}],
        "slots": [{"name": "hitSlot", "bone": "root", "attachment": "button_hit"}],
        "skins": [
          {"name": "default", "entries": [
            {"slot": "hitSlot", "attachment": "button_hit", "target": "button_hit"}
          ]},
          {"name": "noPress", "entries": [
            {"slot": "hitSlot", "attachment": "button_hit", "target": "no_press_hit"}
          ]},
          {"name": "noPulse", "entries": [
            {"slot": "hitSlot", "attachment": "button_hit", "target": "no_pulse_hit"}
          ]}
        ],
        "boundingBoxAttachments": [
          {"name": "button_hit", "vertices": [-1, -1, 1, -1, 1, 1, -1, 1]},
          {"name": "no_press_hit", "vertices": [-1, -1, 1, -1, 1, 1, -1, 1]},
          {"name": "no_pulse_hit", "vertices": [-1, -1, 1, -1, 1, 1, -1, 1]}
        ],
        "animations": [
          {"name": "idle", "boneTimelines": []},
          {"name": "active", "boneTimelines": []}
        ],
        "stateMachines": [{"name": "ui",
          "inputs": [
            {"name": "pressed", "kind": "bool"},
            {"name": "level", "kind": "number"},
            {"name": "pulse", "kind": "trigger"}
          ],
          "layers": [{"name": "base",
            "states": [
              {"name": "idle", "kind": "clip", "clip": "idle"},
              {"name": "active", "kind": "clip", "clip": "active"}
            ],
            "transitions": [{
              "fromState": "idle",
              "toState": "active",
              "conditions": [
                {"input": "pressed", "kind": "boolEquals", "value": true},
                {"input": "pulse", "kind": "triggerSet"}
              ]
            }, {
              "fromState": "active",
              "toState": "idle",
              "conditions": [
                {"input": "pulse", "kind": "triggerSet"}
              ]
            }]
          }],
          "listeners": [
            {"name": "level_down", "kind": "pointerDown", "slot": "hitSlot",
             "targetKind": "boundingBox", "target": "button_hit",
             "input": "level", "value": 2.5},
            {"name": "pulse_down", "kind": "pointerDown", "slot": "hitSlot",
             "targetKind": "boundingBox", "target": "button_hit",
             "input": "pulse"},
            {"name": "press_down", "kind": "pointerDown", "slot": "hitSlot",
             "targetKind": "boundingBox", "target": "button_hit",
             "input": "pressed", "value": true},
            {"name": "level_no_press", "kind": "pointerDown", "slot": "hitSlot",
             "targetKind": "boundingBox", "target": "no_press_hit",
             "input": "level", "value": 2.5},
            {"name": "pulse_no_press", "kind": "pointerDown", "slot": "hitSlot",
             "targetKind": "boundingBox", "target": "no_press_hit",
             "input": "pulse"},
            {"name": "level_no_pulse", "kind": "pointerDown", "slot": "hitSlot",
             "targetKind": "boundingBox", "target": "no_pulse_hit",
             "input": "level", "value": 2.5},
            {"name": "press_no_pulse", "kind": "pointerDown", "slot": "hitSlot",
             "targetKind": "boundingBox", "target": "no_pulse_hit",
             "input": "pressed", "value": true},
            {"name": "idle_exit", "kind": "stateExit", "layer": "base",
             "fromState": "idle"},
            {"name": "idle_to_active", "kind": "transition", "layer": "base",
             "fromState": "idle", "toState": "active"},
            {"name": "active_enter", "kind": "stateEnter", "layer": "base",
             "toState": "active"}
          ]
        }]
      }
      ''');
      final rt = initStateMachineRuntime(orderedData.stateMachines.single);
      final worlds = computeWorldTransforms(orderedData);
      final pulseOnlyRt =
          initStateMachineRuntime(orderedData.stateMachines.single);
      pulseOnlyRt.dispatchPointerListeners(
        orderedData,
        worlds,
        'noPress',
        StateMachineListenerKind.pointerDown,
        0,
        0,
      );
      expect(pulseOnlyRt.getBoolInput('pressed'), isFalse);
      expect(pulseOnlyRt.events.map((event) => event.listener), [
        'level_no_press',
        'pulse_no_press',
      ]);
      pulseOnlyRt.update(0.0, preserveEvents: true);
      expect(pulseOnlyRt.currentState('base'), 'idle');

      final pressedOnlyRt =
          initStateMachineRuntime(orderedData.stateMachines.single);
      pressedOnlyRt.dispatchPointerListeners(
        orderedData,
        worlds,
        'noPulse',
        StateMachineListenerKind.pointerDown,
        0,
        0,
      );
      expect(pressedOnlyRt.getBoolInput('pressed'), isTrue);
      expect(pressedOnlyRt.events.map((event) => event.listener), [
        'level_no_pulse',
        'press_no_pulse',
      ]);
      pressedOnlyRt.update(0.0, preserveEvents: true);
      expect(pressedOnlyRt.currentState('base'), 'idle');

      rt.dispatchPointerListeners(
        orderedData,
        worlds,
        'default',
        StateMachineListenerKind.pointerDown,
        0,
        0,
      );

      expect(rt.getNumberInput('level'), closeTo(2.5, 1e-9));
      expect(rt.getBoolInput('pressed'), isTrue);
      expect(rt.animationEvents, isEmpty);
      expect(rt.events.map((event) => event.listener), [
        'level_down',
        'pulse_down',
        'press_down',
      ]);
      expect(rt.events.map((event) => event.inputKind), [
        StateMachineInputKind.number,
        StateMachineInputKind.trigger,
        StateMachineInputKind.bool_,
      ]);

      rt.update(0.0, preserveEvents: true);
      expect(rt.currentState('base'), 'active');
      expect(rt.events.map((event) => event.listener), [
        'level_down',
        'pulse_down',
        'press_down',
        'idle_exit',
        'idle_to_active',
        'active_enter',
      ]);

      rt.update(0.0);
      expect(rt.currentState('base'), 'active');
      expect(rt.events, isEmpty);
    });

    test('skips misses and inactive active-skin targets', () {
      final rt = initStateMachineRuntime(pointerMachine);
      final worlds = computeWorldTransforms(pointerData);

      rt.dispatchPointerListeners(
        pointerData,
        worlds,
        'default',
        StateMachineListenerKind.pointerDown,
        400,
        400,
      );
      expect(rt.getBoolInput('pressed'), isFalse);
      expect(rt.events, isEmpty);
      expect(rt.animationEvents, isEmpty);

      final skinnedData = loadBonyJson('''
      {
        "skeleton": {"name": "skinned-pointer"},
        "bones": [{"name": "root"}],
        "slots": [{"name": "hitSlot", "bone": "root", "attachment": "button"}],
        "skins": [
          {"name": "default", "entries": [
            {"slot": "hitSlot", "attachment": "button", "target": "button_hit"}
          ]},
          {"name": "alt", "entries": [
            {"slot": "hitSlot", "attachment": "button", "target": "other_hit"}
          ]}
        ],
        "boundingBoxAttachments": [
          {"name": "button_hit", "vertices": [-1, -1, 1, -1, 1, 1, -1, 1]},
          {"name": "other_hit", "vertices": [-1, -1, 1, -1, 1, 1, -1, 1]}
        ],
        "animations": [{"name": "idle", "boneTimelines": []}],
        "stateMachines": [{"name": "ui",
          "inputs": [{"name": "pressed", "kind": "bool"}],
          "layers": [{"name": "base", "states": [{"name": "idle", "kind": "clip", "clip": "idle"}]}],
          "listeners": [
            {"name": "down", "kind": "pointerDown", "slot": "hitSlot",
             "targetKind": "boundingBox", "target": "button_hit",
             "input": "pressed", "value": true}
          ]
        }]
      }
      ''');
      final skinnedRt =
          initStateMachineRuntime(skinnedData.stateMachines.single);
      final skinnedWorlds = computeWorldTransforms(skinnedData);

      skinnedRt.dispatchPointerListeners(
        skinnedData,
        skinnedWorlds,
        'alt',
        StateMachineListenerKind.pointerDown,
        0,
        0,
      );
      expect(skinnedRt.getBoolInput('pressed'), isFalse);
      expect(skinnedRt.events, isEmpty);

      skinnedRt.dispatchPointerListeners(
        skinnedData,
        skinnedWorlds,
        'default',
        StateMachineListenerKind.pointerDown,
        0,
        0,
      );
      expect(skinnedRt.getBoolInput('pressed'), isTrue);
      expect(skinnedRt.events.map((event) => event.listener), ['down']);
    });
  });

  // --- Evaluate ---

  group('M8 evaluate', () {
    test('returns one layer result per layer', () {
      final rt = initStateMachineRuntime(sm);
      final eval = rt.evaluate(data);
      expect(eval.layers, hasLength(sm.layers.length));
    });

    test('layer names match', () {
      final rt = initStateMachineRuntime(sm);
      final eval = rt.evaluate(data);
      expect(eval.layers.map((l) => l.layer).toList(), ['body', 'face']);
    });

    test('combined pose is non-null', () {
      final rt = initStateMachineRuntime(sm);
      final eval = rt.evaluate(data);
      expect(eval.pose, isNotNull);
    });

    test('evaluate with speed=0.7 uses blend pose', () {
      final rt = initStateMachineRuntime(sm);
      rt.setBoolInput('wave', true);
      rt.update(0.0);
      rt.setNumberInput('speed', 0.7);
      final eval = rt.evaluate(data);
      expect(eval.layers[0].state, 'move');
      // blend1d pose should have scalars.
      expect(eval.pose.scalars, isNotEmpty);
    });
  });

  group('M8 blend1d deform channel (bony-353d parity)', () {
    // Regression: the blend1d path (_blendPoses) silently dropped the deforms
    // channel, so a blend state playing a deform-timeline clip rendered the
    // static mesh — the same bug fixed on the Nim side. Deforms resolve
    // winner-take-by-track-weight (docs/deform-timeline-contract.md): the
    // higher-weight clip's deltas win outright, never a linear blend.
    const fixture = '{"skeleton":{"name":"blenddeform"},'
        '"bones":[{"name":"root"}],'
        '"slots":[{"name":"body","bone":"root","attachment":"cloth"}],'
        '"meshAttachments":[{"name":"cloth","weighted":false,'
        '"vertices":[{"x":0,"y":0},{"x":50,"y":0},{"x":0,"y":50}],'
        '"uvs":[0,0,1,0,0,1],"triangles":[0,1,2]}],'
        '"animations":['
        '{"name":"low","deformTimelines":[{"skin":"default","slot":"body",'
        '"attachment":"cloth","vertexCount":3,'
        '"keyframes":[{"t":0.0,"offset":0,"deltas":[{"x":2,"y":0}]}]}]},'
        '{"name":"high","deformTimelines":[{"skin":"default","slot":"body",'
        '"attachment":"cloth","vertexCount":3,'
        '"keyframes":[{"t":0.0,"offset":0,"deltas":[{"x":5,"y":0}]}]}]}'
        '],'
        '"stateMachines":[{"name":"m",'
        '"inputs":[{"name":"speed","kind":"number"}],'
        '"layers":[{"name":"base","states":['
        '{"name":"move","kind":"blend1d","blendInput":"speed",'
        '"blendClips":[{"clip":"low","value":0.0},{"clip":"high","value":1.0}]}'
        '],"transitions":[]}]'
        '}]}';

    late SkeletonData blendData;
    late StateMachineData blendSm;

    setUpAll(() {
      blendData = loadBonyJson(fixture);
      blendSm = blendData.stateMachines[0];
    });

    test('t<0.5 carries the low clip deform outright', () {
      final rt = initStateMachineRuntime(blendSm);
      rt.setNumberInput('speed', 0.25);
      final eval = rt.evaluate(blendData);
      expect(eval.pose.deforms, hasLength(1));
      expect(eval.pose.deforms[0].slot, 'body');
      expect(eval.pose.deforms[0].attachment, 'cloth');
      // low is the higher-weight winner (weight 0.75) at t=0.25.
      expect((eval.pose.deforms[0].deltas[0].x - 2.0).abs(),
          lessThanOrEqualTo(1e-4));
    });

    test('t>=0.5 carries the high clip deform, not a weighted sum', () {
      final rt = initStateMachineRuntime(blendSm);
      rt.setNumberInput('speed', 0.75);
      final eval = rt.evaluate(blendData);
      expect(eval.pose.deforms, hasLength(1));
      // high wins outright: 5.0, NOT the blended 5*0.75 + 2*0.25 = 4.25.
      expect((eval.pose.deforms[0].deltas[0].x - 5.0).abs(),
          lessThanOrEqualTo(1e-4));
    });
  });

  group('M8 blend asymmetric-clip setup fallback (bony-6dkk)', () {
    // The low and high blend clips drive DIFFERENT bones, so each numeric channel
    // is present in only one clip. _blendPoses must union the channels and fall
    // back to the SETUP pose for the side that lacks a key (setupScalar/
    // setupVector). Mirrors the Nim guard; pins Nim<->Dart parity on this path.
    const fixture = '{"skeleton":{"name":"allasym"},'
        '"bones":[{"name":"root"},'
        '{"name":"a","parent":"root","x":100,"y":200,"rotation":10},'
        '{"name":"b","parent":"root","x":300,"y":400,"rotation":20}],'
        '"animations":['
        '{"name":"low","boneTimelines":['
        '{"bone":"a","property":"rotate","keyframes":[{"t":0.0,"value":40}]},'
        '{"bone":"a","property":"translate","keyframes":[{"t":0.0,"x":4,"y":6}]}'
        ']},'
        '{"name":"high","boneTimelines":['
        '{"bone":"b","property":"rotate","keyframes":[{"t":0.0,"value":80}]},'
        '{"bone":"b","property":"translate","keyframes":[{"t":0.0,"x":10,"y":2}]}'
        ']}'
        '],'
        '"stateMachines":[{"name":"m",'
        '"inputs":[{"name":"speed","kind":"number"}],'
        '"layers":[{"name":"base","states":['
        '{"name":"move","kind":"blend1d","blendInput":"speed",'
        '"blendClips":[{"clip":"low","value":0.0},{"clip":"high","value":1.0}]}'
        '],"transitions":[]}]'
        '}]}';

    late SkeletonData asymData;
    late StateMachineData asymSm;

    setUpAll(() {
      asymData = loadBonyJson(fixture);
      asymSm = asymData.stateMachines[0];
    });

    test('unions both clips channels with setup-pose fallback at t=0.5', () {
      final rt = initStateMachineRuntime(asymSm);
      rt.setNumberInput('speed', 0.5);
      final eval = rt.evaluate(asymData);
      // Union of both clips (sorted a before b), not just the winner's channels.
      expect(eval.pose.scalars, hasLength(2));
      expect(eval.pose.scalars[0].bone, 'a');
      expect(eval.pose.scalars[1].bone, 'b');
      // a: low=40, high falls back to setup rotation 10 -> 40 + (10-40)*0.5 = 25.
      expect(
          (eval.pose.scalars[0].value - 25.0).abs(), lessThanOrEqualTo(1e-4));
      // b: low falls back to setup rotation 20, high=80 -> 20 + (80-20)*0.5 = 50.
      expect(
          (eval.pose.scalars[1].value - 50.0).abs(), lessThanOrEqualTo(1e-4));
      expect(eval.pose.vectors, hasLength(2));
      expect(eval.pose.vectors[0].bone, 'a');
      expect(eval.pose.vectors[1].bone, 'b');
      // a: low=(4,6), high falls back to setup (100,200) -> (52,103).
      expect((eval.pose.vectors[0].x - 52.0).abs(), lessThanOrEqualTo(1e-4));
      expect((eval.pose.vectors[0].y - 103.0).abs(), lessThanOrEqualTo(1e-4));
      // b: low falls back to setup (300,400), high=(10,2) -> (155,201).
      expect((eval.pose.vectors[1].x - 155.0).abs(), lessThanOrEqualTo(1e-4));
      expect((eval.pose.vectors[1].y - 201.0).abs(), lessThanOrEqualTo(1e-4));
    });
  });

  group('M8 MixedPose channel completeness guard (bony-bna8)', () {
    // Mirrors the Nim completeness guard: a fixture whose clip drives ALL eight
    // MixedPose channels, pushed through the blend1D (_blendPoses/_addWeighted)
    // and multi-layer overlay (_overlayPose) aggregators. If a channel is dropped
    // by any aggregator (as deforms was in blend1D), it shows up empty here.
    // Dart lacks cheap field reflection, so the enumeration is explicit — adding
    // a channel #9 means adding it to droppedChannels and to the fixture (the
    // 'enumerates all MixedPose channels' tripwire below backstops the count).
    const fixture = '{"skeleton":{"name":"allchan"},'
        '"bones":[{"name":"root"}],'
        '"slots":[{"name":"body","bone":"root","attachment":""},'
        '{"name":"meshSlot","bone":"root","attachment":"cloth"}],'
        '"regions":[{"name":"idle","width":1,"height":1},'
        '{"name":"wave","width":1,"height":1}],'
        '"meshAttachments":[{"name":"cloth","weighted":false,'
        '"vertices":[{"x":0,"y":0},{"x":50,"y":0},{"x":0,"y":50}],'
        '"uvs":[0,0,1,0,0,1],"triangles":[0,1,2]}],'
        '"animations":[{"name":"all",'
        '"boneTimelines":['
        '{"bone":"root","property":"rotate","keyframes":[{"t":0.0,"value":30}]},'
        '{"bone":"root","property":"translate","keyframes":[{"t":0.0,"x":4,"y":5}]},'
        '{"bone":"root","property":"inherit","keyframes":[{"t":0.0}]}'
        '],'
        '"slotTimelines":['
        '{"slot":"body","property":"attachment","keyframes":[{"t":0.0,"attachment":"idle"}]},'
        '{"slot":"body","property":"rgba","keyframes":[{"t":0.0,"r":0.5,"g":0.25,"b":0.75,"a":1}]},'
        '{"slot":"body","property":"rgba2","keyframes":[{"t":0.0,"r":1,"g":1,"b":1,"a":1,"dr":0.1,"dg":0.2,"db":0.3}]},'
        '{"slot":"body","property":"sequence","keyframes":[{"t":0.0,"index":2,"delay":0.1,"mode":"loop"}]}'
        '],'
        '"deformTimelines":[{"skin":"default","slot":"meshSlot","attachment":"cloth",'
        '"vertexCount":3,"keyframes":[{"t":0.0,"offset":0,"deltas":[{"x":2,"y":0}]}]}]'
        '}],'
        '"stateMachines":['
        '{"name":"blendm","inputs":[{"name":"speed","kind":"number"}],'
        '"layers":[{"name":"base","states":['
        '{"name":"move","kind":"blend1d","blendInput":"speed",'
        '"blendClips":[{"clip":"all","value":0.0},{"clip":"all","value":1.0}]}'
        '],"transitions":[]}]},'
        '{"name":"overlaym","inputs":[],'
        '"layers":['
        '{"name":"base","states":[{"name":"hold","kind":"clip","clip":"all"}],"transitions":[]},'
        '{"name":"overlay","states":[{"name":"hold","kind":"clip","clip":"all"}],"transitions":[]}'
        ']}'
        ']}';

    late SkeletonData chanData;

    List<String> droppedChannels(MixedPose p) => [
          if (p.scalars.isEmpty) 'scalars',
          if (p.vectors.isEmpty) 'vectors',
          if (p.attachments.isEmpty) 'attachments',
          if (p.inherits.isEmpty) 'inherits',
          if (p.colors.isEmpty) 'colors',
          if (p.colors2.isEmpty) 'colors2',
          if (p.sequences.isEmpty) 'sequences',
          if (p.deforms.isEmpty) 'deforms',
        ];

    setUpAll(() {
      chanData = loadBonyJson(fixture);
    });

    test('blend1D aggregation drops no MixedPose channel', () {
      final sm = chanData.stateMachines.firstWhere((s) => s.name == 'blendm');
      final rt = initStateMachineRuntime(sm);
      rt.setNumberInput('speed', 0.75);
      rt.update(0.0);
      final eval = rt.evaluate(chanData);
      expect(droppedChannels(eval.pose), isEmpty);
    });

    test('multi-layer overlay aggregation drops no MixedPose channel', () {
      final sm = chanData.stateMachines.firstWhere((s) => s.name == 'overlaym');
      final rt = initStateMachineRuntime(sm);
      rt.update(0.0);
      final eval = rt.evaluate(chanData);
      expect(droppedChannels(eval.pose), isEmpty);
    });

    test('droppedChannels enumerates every MixedPose channel', () {
      // Genuineness + tripwire: an empty pose must flag ALL channels. This proves
      // droppedChannels isn't a tautology (each isEmpty branch fires) and pins the
      // enumeration size — if a 9th MixedPose channel is added, this count breaks
      // and points the author at droppedChannels, the manual backstop for the
      // reflection the Nim fieldPairs guard gets for free.
      const empty = MixedPose(
        scalars: [],
        vectors: [],
        attachments: [],
        inherits: [],
        colors: [],
        colors2: [],
        sequences: [],
      );
      expect(droppedChannels(empty), hasLength(8));
    });
  });

  group('M8 cross-reference validation', () {
    // Minimal fixture with two animations, two inputs, two layers, and a listener.
    // Each test breaks exactly one cross-reference.
    const base = '{"skeleton":{"name":"xref"},"bones":[{"name":"root"}],'
        '"animations":[{"name":"idle","boneTimelines":[]},{"name":"walk","boneTimelines":[]}],'
        '"stateMachines":[{"name":"m",'
        '"inputs":[{"name":"wave","kind":"bool"},{"name":"speed","kind":"number"}],'
        '"layers":['
        '{"name":"body","states":['
        '{"name":"idle","kind":"clip","clip":"idle"},'
        '{"name":"move","kind":"blend1d","blendInput":"speed","blendClips":[{"clip":"walk","value":0.0}]}'
        '],"transitions":[{"fromState":"idle","toState":"move","conditions":[{"input":"wave","kind":"boolEquals","value":true}]}]},'
        '{"name":"face","states":[{"name":"normal","kind":"clip","clip":"idle"}],"transitions":[]}'
        '],'
        '"listeners":[{"name":"ev","kind":"stateEnter","layer":"body","toState":"move"}]'
        '}]}';

    test('valid base fixture loads without error', () {
      expect(() => loadBonyJson(base), returnsNormally);
    });

    test('rejects unknown animation in clip state', () {
      expect(
        () => loadBonyJson(
            base.replaceFirst('"clip":"idle"', '"clip":"missing"')),
        throwsFormatException,
      );
    });

    test('rejects unknown animation in blendClip', () {
      expect(
        () => loadBonyJson(
            base.replaceFirst('"clip":"walk"', '"clip":"missing"')),
        throwsFormatException,
      );
    });

    test('rejects unknown input in blendInput', () {
      expect(
        () => loadBonyJson(base.replaceFirst(
            '"blendInput":"speed"', '"blendInput":"missing"')),
        throwsFormatException,
      );
    });

    test('rejects unknown fromState in transition', () {
      expect(
        () => loadBonyJson(
            base.replaceFirst('"fromState":"idle"', '"fromState":"missing"')),
        throwsFormatException,
      );
    });

    test('rejects unknown toState in transition', () {
      expect(
        () => loadBonyJson(base.replaceFirst('"toState":"move","conditions"',
            '"toState":"missing","conditions"')),
        throwsFormatException,
      );
    });

    test('rejects unknown input in condition', () {
      expect(
        () => loadBonyJson(
            base.replaceFirst('"input":"wave"', '"input":"missing"')),
        throwsFormatException,
      );
    });

    test('rejects unknown layer in listener', () {
      expect(
        () => loadBonyJson(
            base.replaceFirst('"layer":"body"', '"layer":"missing"')),
        throwsFormatException,
      );
    });

    test('rejects unknown toState in stateEnter listener', () {
      // Use a self-contained fixture so replaceFirst can't accidentally hit
      // the transition's toState (which also appears in `base`).
      final json = '{"skeleton":{"name":"xref"},"bones":[{"name":"root"}],'
          '"animations":[{"name":"idle","boneTimelines":[]}],'
          '"stateMachines":[{"name":"m","inputs":[],'
          '"layers":[{"name":"body","states":[{"name":"idle","kind":"clip","clip":"idle"}],"transitions":[]}],'
          '"listeners":[{"name":"ev","kind":"stateEnter","layer":"body","toState":"missing"}]}]}';
      expect(() => loadBonyJson(json), throwsFormatException);
    });

    test('rejects unknown fromState in stateExit listener', () {
      final json = '{"skeleton":{"name":"xref"},"bones":[{"name":"root"}],'
          '"animations":[{"name":"idle","boneTimelines":[]}],'
          '"stateMachines":[{"name":"m","inputs":[],'
          '"layers":[{"name":"body","states":[{"name":"idle","kind":"clip","clip":"idle"}],"transitions":[]}],'
          '"listeners":[{"name":"ev","kind":"stateExit","layer":"body","fromState":"missing"}]}]}';
      expect(() => loadBonyJson(json), throwsFormatException);
    });

    test('rejects unknown fromState in transition listener', () {
      final json = '{"skeleton":{"name":"xref"},"bones":[{"name":"root"}],'
          '"animations":[{"name":"idle","boneTimelines":[]}],'
          '"stateMachines":[{"name":"m","inputs":[],'
          '"layers":[{"name":"body","states":[{"name":"idle","kind":"clip","clip":"idle"},{"name":"move","kind":"clip","clip":"idle"}],"transitions":[]}],'
          '"listeners":[{"name":"ev","kind":"transition","layer":"body","fromState":"missing","toState":"move"}]}]}';
      expect(() => loadBonyJson(json), throwsFormatException);
    });

    test('rejects unknown toState in transition listener', () {
      final json = '{"skeleton":{"name":"xref"},"bones":[{"name":"root"}],'
          '"animations":[{"name":"idle","boneTimelines":[]}],'
          '"stateMachines":[{"name":"m","inputs":[],'
          '"layers":[{"name":"body","states":[{"name":"idle","kind":"clip","clip":"idle"},{"name":"move","kind":"clip","clip":"idle"}],"transitions":[]}],'
          '"listeners":[{"name":"ev","kind":"transition","layer":"body","fromState":"idle","toState":"missing"}]}]}';
      expect(() => loadBonyJson(json), throwsFormatException);
    });

    test('loads pointer helper listeners', () {
      final json = '{"skeleton":{"name":"pointer"},"bones":[{"name":"root"}],'
          '"slots":[{"name":"tip_slot","bone":"root","attachment":"tip"},{"name":"button_slot","bone":"root","attachment":"button"}],'
          '"pointAttachments":[{"name":"tip","x":1,"y":2,"rotation":0}],'
          '"boundingBoxAttachments":[{"name":"button_hit","vertices":[-2,-1,2,-1,2,1,-2,1]}],'
          '"skins":[{"name":"default","entries":[{"slot":"tip_slot","attachment":"tip","target":"tip"},{"slot":"button_slot","attachment":"button","target":"button_hit"}]}],'
          '"animations":[{"name":"idle","boneTimelines":[]}],'
          '"stateMachines":[{"name":"ui",'
          '"inputs":[{"name":"pressed","kind":"bool"},{"name":"hover","kind":"number"},{"name":"fire","kind":"trigger"}],'
          '"layers":[{"name":"base","states":[{"name":"idle","kind":"clip","clip":"idle"}]}],'
          '"listeners":['
          '{"name":"down","kind":"pointerDown","slot":"tip_slot","targetKind":"point","target":"tip","hitRadius":4,"input":"pressed","value":false},'
          '{"name":"move","kind":"pointerMove","slot":"button_slot","targetKind":"boundingBox","target":"button_hit","input":"hover","value":0.25},'
          '{"name":"up","kind":"pointerUp","slot":"tip_slot","targetKind":"point","target":"tip","hitRadius":0,"input":"fire"}'
          ']}]}';
      final machine = loadBonyJson(json).stateMachines.single;
      expect(machine.listeners, hasLength(3));
      expect(machine.listeners[0].kind, StateMachineListenerKind.pointerDown);
      expect(machine.listeners[0].targetKind, PointerHelperTargetKind.point);
      expect(machine.listeners[0].boolValue, isFalse);
      expect(
          machine.listeners[1].targetKind, PointerHelperTargetKind.boundingBox);
      expect(machine.listeners[1].numberValue, closeTo(0.25, 1e-9));
      expect(machine.listeners[2].boolValue, isNull);
      expect(machine.listeners[2].numberValue, isNull);
    });

    test('loads committed M21 pointer helper listeners from JSON and BNB', () {
      final fromJson = loadBonyJson(
        File('../conformance/assets/m21_pointer_listener_rig.bony')
            .readAsStringSync(),
      );
      final fromBnb = loadBonyBnb(
        File('../conformance/assets/bnb/m21_pointer_listener_rig.bnb')
            .readAsBytesSync(),
      );
      final jsonMachine = fromJson.stateMachines.single;
      final bnbMachine = fromBnb.stateMachines.single;
      expect(_listenerSurface(bnbMachine), _listenerSurface(jsonMachine));

      for (final machine in [jsonMachine, bnbMachine]) {
        final byName = {
          for (final listener in machine.listeners) listener.name: listener,
        };
        expect(byName.keys, [
          'box_enter',
          'box_down',
          'point_move',
          'point_up',
          'box_exit',
          'idle_exit',
          'idle_to_pressed',
          'pressed_enter',
        ]);

        final boxEnter = byName['box_enter']!;
        expect(boxEnter.kind, StateMachineListenerKind.pointerEnter);
        expect(boxEnter.slot, 'button_box_slot');
        expect(boxEnter.targetKind, PointerHelperTargetKind.boundingBox);
        expect(boxEnter.target, 'button_hit');
        expect(boxEnter.hitRadius, isNull);
        expect(boxEnter.input, 'hover');
        expect(boxEnter.boolValue, isTrue);
        expect(boxEnter.numberValue, isNull);

        final boxDown = byName['box_down']!;
        expect(boxDown.kind, StateMachineListenerKind.pointerDown);
        expect(boxDown.slot, 'button_box_slot');
        expect(boxDown.targetKind, PointerHelperTargetKind.boundingBox);
        expect(boxDown.target, 'button_hit');
        expect(boxDown.input, 'pressed');
        expect(boxDown.boolValue, isTrue);

        final pointMove = byName['point_move']!;
        expect(pointMove.kind, StateMachineListenerKind.pointerMove);
        expect(pointMove.slot, 'button_point_slot');
        expect(pointMove.targetKind, PointerHelperTargetKind.point);
        expect(pointMove.target, 'spark_point');
        expect(pointMove.hitRadius, closeTo(3, 1e-9));
        expect(pointMove.input, 'intensity');
        expect(pointMove.boolValue, isNull);
        expect(pointMove.numberValue, closeTo(4.5, 1e-9));

        final pointUp = byName['point_up']!;
        expect(pointUp.kind, StateMachineListenerKind.pointerUp);
        expect(pointUp.slot, 'button_point_slot');
        expect(pointUp.targetKind, PointerHelperTargetKind.point);
        expect(pointUp.target, 'spark_point');
        expect(pointUp.hitRadius, closeTo(3, 1e-9));
        expect(pointUp.input, 'pulse');
        expect(pointUp.boolValue, isNull);
        expect(pointUp.numberValue, isNull);

        final boxExit = byName['box_exit']!;
        expect(boxExit.kind, StateMachineListenerKind.pointerExit);
        expect(boxExit.slot, 'button_box_slot');
        expect(boxExit.targetKind, PointerHelperTargetKind.boundingBox);
        expect(boxExit.target, 'button_hit');
        expect(boxExit.input, 'hover');
        expect(boxExit.boolValue, isFalse);
      }
    });

    test('rejects malformed pointer helper listeners', () {
      const base = '{"skeleton":{"name":"pointer"},"bones":[{"name":"root"}],'
          '"slots":[{"name":"tip_slot","bone":"root","attachment":"tip"},{"name":"box_slot","bone":"root","attachment":"button_hit"}],'
          '"pointAttachments":[{"name":"tip","x":0,"y":0,"rotation":0}],'
          '"boundingBoxAttachments":[{"name":"button_hit","vertices":[-1,-1,1,-1,1,1,-1,1]}],'
          '"animations":[{"name":"idle","boneTimelines":[]}],'
          '"stateMachines":[{"name":"ui",'
          '"inputs":[{"name":"pressed","kind":"bool"},{"name":"level","kind":"number"},{"name":"fire","kind":"trigger"}],'
          '"layers":[{"name":"base","states":[{"name":"idle","kind":"clip","clip":"idle"}]}],'
          '"listeners":[REPLACE_LISTENER]}]}';
      void expectBad(String listener) {
        expect(
          () => loadBonyJson(base.replaceFirst('REPLACE_LISTENER', listener)),
          throwsFormatException,
        );
      }

      expectBad(
          '{"name":"bad","kind":"pointerDown","layer":"base","slot":"tip_slot","targetKind":"point","target":"tip","hitRadius":1,"input":"pressed","value":true}');
      expectBad(
          '{"name":"bad","kind":"stateEnter","layer":"base","toState":"idle","slot":"tip_slot"}');
      expectBad(
          '{"name":"bad","kind":"pointerDown","slot":"missing","targetKind":"point","target":"tip","hitRadius":1,"input":"pressed","value":true}');
      expectBad(
          '{"name":"bad","kind":"pointerDown","slot":"tip_slot","targetKind":"point","target":"other","hitRadius":1,"input":"pressed","value":true}');
      expectBad(
          '{"name":"bad","kind":"pointerDown","slot":"tip_slot","targetKind":"point","target":"tip","hitRadius":1,"input":"missing","value":true}');
      expectBad(
          '{"name":"bad","kind":"pointerDown","slot":"tip_slot","targetKind":"triangle","target":"tip","hitRadius":1,"input":"pressed","value":true}');
      expectBad(
          '{"name":"bad","kind":"pointerDown","slot":"tip_slot","targetKind":"point","target":"tip","input":"pressed","value":true}');
      expectBad(
          '{"name":"bad","kind":"pointerDown","slot":"tip_slot","targetKind":"point","target":"tip","hitRadius":-1,"input":"pressed","value":true}');
      expectBad(
          '{"name":"bad","kind":"pointerDown","slot":"box_slot","targetKind":"boundingBox","target":"button_hit","hitRadius":1,"input":"pressed","value":true}');
      expectBad(
          '{"name":"bad","kind":"pointerDown","slot":"tip_slot","targetKind":"point","target":"tip","hitRadius":1,"input":"pressed"}');
      expectBad(
          '{"name":"bad","kind":"pointerDown","slot":"tip_slot","targetKind":"point","target":"tip","hitRadius":1,"input":"level"}');
      expectBad(
          '{"name":"bad","kind":"pointerDown","slot":"tip_slot","targetKind":"point","target":"tip","hitRadius":1,"input":"pressed","value":0.5}');
      expectBad(
          '{"name":"bad","kind":"pointerDown","slot":"tip_slot","targetKind":"point","target":"tip","hitRadius":1,"input":"level","value":true}');
      expectBad(
          '{"name":"bad","kind":"pointerUp","slot":"tip_slot","targetKind":"point","target":"tip","hitRadius":1,"input":"fire","value":true}');
    });

    test('loads hand-built pointer helper listener BNB fixture', () {
      final fixture = loadBonyBnb(_pointerListenerBnb(
        inputKind: 0,
        listenerKind: 3,
        helperKind: 0,
      ));

      final listener = fixture.stateMachines.single.listeners.single;
      expect(listener.kind, StateMachineListenerKind.pointerDown);
      expect(listener.slot, 'tip_slot');
      expect(listener.targetKind, PointerHelperTargetKind.point);
      expect(listener.target, 'tip');
      expect(listener.hitRadius, closeTo(1, 1e-9));
      expect(listener.input, 'input');
      expect(listener.boolValue, isTrue);
      expect(listener.numberValue, isNull);
    });

    test('rejects malformed pointer helper listeners from BNB', () {
      void expectBad(Uint8List bytes, String messagePart) {
        expect(
          () => loadBonyBnb(bytes),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'message', contains(messagePart))),
        );
      }

      expectBad(
          _pointerListenerBnb(
            inputKind: 0,
            listenerKind: 3,
            helperKind: 0,
            listenerExtraProps: [
              (out) => _writeProp(out, 7061, _varuintBytes(0)),
            ],
          ),
          '.bnb pointer listener must not contain lifecycle fields');
      expectBad(
          _pointerListenerBnb(
            inputKind: 0,
            listenerKind: 0,
            helperKind: 0,
            listenerExtraProps: [
              (out) => _writeProp(out, 7061, _varuintBytes(0)),
              (out) => _writeProp(out, 7063, _varuintBytes(0)),
            ],
          ),
          '.bnb lifecycle listener must not contain pointer fields');
      expectBad(
          _pointerListenerBnb(
            inputKind: 0,
            listenerKind: 3,
            helperKind: 2,
          ),
          '.bnb stateMachineListener.helperKind is invalid: 2');
      expectBad(
          _pointerListenerBnb(
            inputKind: 0,
            listenerKind: 3,
            helperKind: 0,
            slotIndex: 2,
          ),
          '.bnb stateMachineListener.slot index is out of range');
      expectBad(
          _pointerListenerBnb(
            inputKind: 0,
            listenerKind: 3,
            helperKind: 0,
            helperTarget: 'missing',
          ),
          'target references unknown helper attachment: missing');
      expectBad(
          _pointerListenerBnb(
            inputKind: 0,
            listenerKind: 3,
            helperKind: 0,
            inputIndex: 2,
          ),
          '.bnb stateMachineListener.input index is out of range');
      expectBad(
          _pointerListenerBnb(
            inputKind: 0,
            listenerKind: 3,
            helperKind: 0,
            includeHitRadius: false,
          ),
          '.bnb required property missing: stateMachineListener.hitRadius');
      expectBad(
          _pointerListenerBnb(
            inputKind: 0,
            listenerKind: 3,
            helperKind: 0,
            hitRadius: -1,
          ),
          'hitRadius is required and non-negative');
      expectBad(
          _pointerListenerBnb(
            inputKind: 0,
            listenerKind: 3,
            helperKind: 1,
            helperTarget: 'button_hit',
          ),
          '.bnb pointer bounding-box listener must not contain hitRadius');
      expectBad(
          _pointerListenerBnb(
            inputKind: 0,
            listenerKind: 3,
            helperKind: 0,
            includeBoolValue: false,
          ),
          '.bnb pointer bool listener value is required');
      expectBad(
          _pointerListenerBnb(
            inputKind: 1,
            listenerKind: 3,
            helperKind: 0,
            includeBoolValue: false,
            includeNumberValue: false,
          ),
          '.bnb required property missing: stateMachineListener.numberValue');
      expectBad(
          _pointerListenerBnb(
            inputKind: 0,
            listenerKind: 3,
            helperKind: 0,
            includeNumberValue: true,
          ),
          '.bnb pointer bool listener must not contain number value');
      expectBad(
          _pointerListenerBnb(
            inputKind: 1,
            listenerKind: 3,
            helperKind: 0,
            includeBoolValue: true,
          ),
          '.bnb pointer number listener must not contain bool value');
      expectBad(
          _pointerListenerBnb(
            inputKind: 2,
            listenerKind: 3,
            helperKind: 0,
            includeBoolValue: true,
          ),
          '.bnb pointer trigger listener must not contain values');
    });
  });
}
