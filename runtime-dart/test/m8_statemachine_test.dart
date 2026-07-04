// Dart M8 state machine: parsing, runtime, transitions, listeners, evaluate.
//
// Tests run from runtime-dart/ so ../conformance/ resolves to repo root.

import 'dart:io';
import 'package:test/test.dart';
import 'package:bony/bony.dart';

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
          '${listener.name}:${listener.kind.name}:${listener.layer}:${listener.fromState}:${listener.toState}',
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

  group('M8 MixedPose channel completeness guard (bony-bna8)', () {
    // Mirrors the Nim completeness guard: a fixture whose clip drives ALL eight
    // MixedPose channels, pushed through the blend1D (_blendPoses/_addWeighted)
    // and multi-layer overlay (_overlayPose) aggregators. If a channel is dropped
    // by any aggregator (as deforms was in blend1D), it shows up empty here.
    // Dart lacks cheap field reflection, so the enumeration is explicit — adding
    // a channel #9 means adding it to _droppedChannels and to the fixture.
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
  });
}
