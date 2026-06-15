// Dart M8 state machine: parsing, runtime, transitions, listeners, evaluate.
//
// Tests run from runtime-dart/ so ../conformance/ resolves to repo root.

import 'dart:io';
import 'package:test/test.dart';
import 'package:bony/bony.dart';

void main() {
  late SkeletonData data;
  late StateMachineData sm;

  setUpAll(() {
    data = loadBonyJson(
      File('../conformance/assets/m8_rig.bony').readAsStringSync(),
    );
    expect(data.stateMachines, hasLength(1), reason: 'expected one state machine');
    sm = data.stateMachines[0];
  });

  // --- Parsing ---

  group('M8 state machine parsed', () {
    test('machine name', () {
      expect(sm.name, 'gesture');
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

    test('events cleared on next update', () {
      final rt = initStateMachineRuntime(sm);
      rt.setBoolInput('wave', true);
      rt.update(0.0);
      expect(rt.events, isNotEmpty);
      rt.update(0.1);
      expect(rt.events, isEmpty);
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

  group('M8 cross-reference validation', () {
    // Minimal fixture with two animations, two inputs, two layers, and a listener.
    // Each test breaks exactly one cross-reference.
    const base =
        '{"skeleton":{"name":"xref"},"bones":[{"name":"root"}],'
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
        () => loadBonyJson(base.replaceFirst('"clip":"idle"', '"clip":"missing"')),
        throwsFormatException,
      );
    });

    test('rejects unknown animation in blendClip', () {
      expect(
        () => loadBonyJson(base.replaceFirst('"clip":"walk"', '"clip":"missing"')),
        throwsFormatException,
      );
    });

    test('rejects unknown input in blendInput', () {
      expect(
        () => loadBonyJson(base.replaceFirst('"blendInput":"speed"', '"blendInput":"missing"')),
        throwsFormatException,
      );
    });

    test('rejects unknown fromState in transition', () {
      expect(
        () => loadBonyJson(base.replaceFirst('"fromState":"idle"', '"fromState":"missing"')),
        throwsFormatException,
      );
    });

    test('rejects unknown toState in transition', () {
      expect(
        () => loadBonyJson(base.replaceFirst('"toState":"move","conditions"', '"toState":"missing","conditions"')),
        throwsFormatException,
      );
    });

    test('rejects unknown input in condition', () {
      expect(
        () => loadBonyJson(base.replaceFirst('"input":"wave"', '"input":"missing"')),
        throwsFormatException,
      );
    });

    test('rejects unknown layer in listener', () {
      expect(
        () => loadBonyJson(base.replaceFirst('"layer":"body"', '"layer":"missing"')),
        throwsFormatException,
      );
    });

    test('rejects unknown toState in stateEnter listener', () {
      // Use a self-contained fixture so replaceFirst can't accidentally hit
      // the transition's toState (which also appears in `base`).
      final json =
          '{"skeleton":{"name":"xref"},"bones":[{"name":"root"}],'
          '"animations":[{"name":"idle","boneTimelines":[]}],'
          '"stateMachines":[{"name":"m","inputs":[],'
          '"layers":[{"name":"body","states":[{"name":"idle","kind":"clip","clip":"idle"}],"transitions":[]}],'
          '"listeners":[{"name":"ev","kind":"stateEnter","layer":"body","toState":"missing"}]}]}';
      expect(() => loadBonyJson(json), throwsFormatException);
    });

    test('rejects unknown fromState in stateExit listener', () {
      final json =
          '{"skeleton":{"name":"xref"},"bones":[{"name":"root"}],'
          '"animations":[{"name":"idle","boneTimelines":[]}],'
          '"stateMachines":[{"name":"m","inputs":[],'
          '"layers":[{"name":"body","states":[{"name":"idle","kind":"clip","clip":"idle"}],"transitions":[]}],'
          '"listeners":[{"name":"ev","kind":"stateExit","layer":"body","fromState":"missing"}]}]}';
      expect(() => loadBonyJson(json), throwsFormatException);
    });

    test('rejects unknown fromState in transition listener', () {
      final json =
          '{"skeleton":{"name":"xref"},"bones":[{"name":"root"}],'
          '"animations":[{"name":"idle","boneTimelines":[]}],'
          '"stateMachines":[{"name":"m","inputs":[],'
          '"layers":[{"name":"body","states":[{"name":"idle","kind":"clip","clip":"idle"},{"name":"move","kind":"clip","clip":"idle"}],"transitions":[]}],'
          '"listeners":[{"name":"ev","kind":"transition","layer":"body","fromState":"missing","toState":"move"}]}]}';
      expect(() => loadBonyJson(json), throwsFormatException);
    });

    test('rejects unknown toState in transition listener', () {
      final json =
          '{"skeleton":{"name":"xref"},"bones":[{"name":"root"}],'
          '"animations":[{"name":"idle","boneTimelines":[]}],'
          '"stateMachines":[{"name":"m","inputs":[],'
          '"layers":[{"name":"body","states":[{"name":"idle","kind":"clip","clip":"idle"},{"name":"move","kind":"clip","clip":"idle"}],"transitions":[]}],'
          '"listeners":[{"name":"ev","kind":"transition","layer":"body","fromState":"idle","toState":"missing"}]}]}';
      expect(() => loadBonyJson(json), throwsFormatException);
    });
  });
}
