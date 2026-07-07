part of 'loader.dart';

StateMachineData _parseStateMachine(Map<String, dynamic> j) {
  final name = _required<String>(j['name'], 'stateMachine.name');

  final inputsRaw = j['inputs'] as List<dynamic>? ?? [];
  final inputs = inputsRaw.map((i) {
    final m = i as Map<String, dynamic>;
    final iname = _required<String>(m['name'], 'input.name');
    final kind = _required<String>(m['kind'], 'input.kind');
    switch (kind) {
      case 'bool':
        return StateMachineInput(
          name: iname,
          kind: StateMachineInputKind.bool_,
          defaultBool: (m['default'] as bool?) ?? false,
        );
      case 'number':
        return StateMachineInput(
          name: iname,
          kind: StateMachineInputKind.number,
          defaultNumber: quantizeF32((m['default'] as num?)?.toDouble() ?? 0.0),
        );
      case 'trigger':
        return StateMachineInput(
            name: iname, kind: StateMachineInputKind.trigger);
      default:
        throw FormatException('unknown input kind: $kind');
    }
  }).toList();

  final layersRaw =
      _required<List<dynamic>>(j['layers'], 'stateMachine.layers');
  final layers = layersRaw.map((l) {
    final lm = l as Map<String, dynamic>;
    final lname = _required<String>(lm['name'], 'layer.name');
    final initialState = (lm['initialState'] as String?) ?? '';

    final statesRaw = _required<List<dynamic>>(lm['states'], 'layer.states');
    final states = statesRaw.map((s) {
      final sm = s as Map<String, dynamic>;
      final sname = _required<String>(sm['name'], 'state.name');
      final kind = _required<String>(sm['kind'], 'state.kind');
      if (kind == 'clip') {
        return StateMachineState(
          name: sname,
          kind: StateMachineStateKind.clip,
          clipName: _required<String>(sm['clip'], 'state.clip'),
          loop: (sm['loop'] as bool?) ?? false,
        );
      } else if (kind == 'blend1d') {
        final blendClipsRaw =
            _required<List<dynamic>>(sm['blendClips'], 'state.blendClips');
        final blendClips = blendClipsRaw.map((bc) {
          final bcm = bc as Map<String, dynamic>;
          return StateMachineBlendClip(
            clipName: _required<String>(bcm['clip'], 'blendClip.clip'),
            value: quantizeF32(
                _required<num>(bcm['value'], 'blendClip.value').toDouble()),
            loop: (bcm['loop'] as bool?) ?? false,
          );
        }).toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        for (var bi = 1; bi < blendClips.length; bi++) {
          if (blendClips[bi].value == blendClips[bi - 1].value) {
            throw FormatException(
                'duplicate blend clip value: ${blendClips[bi].value}');
          }
        }
        return StateMachineState(
          name: sname,
          kind: StateMachineStateKind.blend1d,
          blendInput: _required<String>(sm['blendInput'], 'state.blendInput'),
          blendClips: blendClips,
        );
      } else {
        throw FormatException('unknown state kind: $kind');
      }
    }).toList();

    final transitionsRaw = lm['transitions'] as List<dynamic>? ?? [];
    final transitions = transitionsRaw.map((t) {
      final tm = t as Map<String, dynamic>;
      final conditionsRaw =
          _required<List<dynamic>>(tm['conditions'], 'transition.conditions');
      final conditions = conditionsRaw.map((c) {
        final cm = c as Map<String, dynamic>;
        final cinput = _required<String>(cm['input'], 'condition.input');
        final ckind = _required<String>(cm['kind'], 'condition.kind');
        switch (ckind) {
          case 'boolEquals':
            return StateMachineCondition(
              input: cinput,
              kind: StateMachineConditionKind.boolEquals,
              boolValue: _required<bool>(cm['value'], 'condition.value'),
            );
          case 'numberEquals':
            return StateMachineCondition(
              input: cinput,
              kind: StateMachineConditionKind.numberEquals,
              numberValue: quantizeF32(
                  _required<num>(cm['value'], 'condition.value').toDouble()),
            );
          case 'numberGreater':
            return StateMachineCondition(
              input: cinput,
              kind: StateMachineConditionKind.numberGreater,
              numberValue: quantizeF32(
                  _required<num>(cm['value'], 'condition.value').toDouble()),
            );
          case 'numberGreaterOrEqual':
            return StateMachineCondition(
              input: cinput,
              kind: StateMachineConditionKind.numberGreaterOrEqual,
              numberValue: quantizeF32(
                  _required<num>(cm['value'], 'condition.value').toDouble()),
            );
          case 'numberLess':
            return StateMachineCondition(
              input: cinput,
              kind: StateMachineConditionKind.numberLess,
              numberValue: quantizeF32(
                  _required<num>(cm['value'], 'condition.value').toDouble()),
            );
          case 'numberLessOrEqual':
            return StateMachineCondition(
              input: cinput,
              kind: StateMachineConditionKind.numberLessOrEqual,
              numberValue: quantizeF32(
                  _required<num>(cm['value'], 'condition.value').toDouble()),
            );
          case 'triggerSet':
            return StateMachineCondition(
              input: cinput,
              kind: StateMachineConditionKind.triggerSet,
            );
          default:
            throw FormatException('unknown condition kind: $ckind');
        }
      }).toList();
      return StateMachineTransition(
        fromState: _required<String>(tm['fromState'], 'transition.fromState'),
        toState: _required<String>(tm['toState'], 'transition.toState'),
        conditions: conditions,
      );
    }).toList();

    if (states.isEmpty)
      throw FormatException(
          'state machine layer "$lname" must have at least one state');
    final resolvedInitial =
        initialState.isEmpty ? states[0].name : initialState;
    if (!states.any((s) => s.name == resolvedInitial)) {
      throw FormatException(
          'state machine layer "$lname" initialState "$resolvedInitial" not found');
    }
    return StateMachineLayer(
      name: lname,
      states: states,
      initialState: resolvedInitial,
      transitions: transitions,
    );
  }).toList();

  final listenersRaw = j['listeners'] as List<dynamic>? ?? [];
  final listeners = listenersRaw.map((l) {
    final lm = l as Map<String, dynamic>;
    final lname = _required<String>(lm['name'], 'listener.name');
    final lkind = _required<String>(lm['kind'], 'listener.kind');
    bool hasAny(Iterable<String> keys) => keys.any(lm.containsKey);

    switch (lkind) {
      case 'stateEnter':
        if (hasAny(
            ['slot', 'targetKind', 'target', 'hitRadius', 'input', 'value'])) {
          throw const FormatException(
              'lifecycle listener must not contain pointer fields');
        }
        final llayer = _required<String>(lm['layer'], 'listener.layer');
        return StateMachineListener(
          name: lname,
          kind: StateMachineListenerKind.stateEnter,
          layer: llayer,
          toState: _required<String>(lm['toState'], 'listener.toState'),
        );
      case 'stateExit':
        if (hasAny(
            ['slot', 'targetKind', 'target', 'hitRadius', 'input', 'value'])) {
          throw const FormatException(
              'lifecycle listener must not contain pointer fields');
        }
        final llayer = _required<String>(lm['layer'], 'listener.layer');
        return StateMachineListener(
          name: lname,
          kind: StateMachineListenerKind.stateExit,
          layer: llayer,
          fromState: _required<String>(lm['fromState'], 'listener.fromState'),
        );
      case 'transition':
        if (hasAny(
            ['slot', 'targetKind', 'target', 'hitRadius', 'input', 'value'])) {
          throw const FormatException(
              'lifecycle listener must not contain pointer fields');
        }
        final llayer = _required<String>(lm['layer'], 'listener.layer');
        return StateMachineListener(
          name: lname,
          kind: StateMachineListenerKind.transition_,
          layer: llayer,
          fromState: _required<String>(lm['fromState'], 'listener.fromState'),
          toState: _required<String>(lm['toState'], 'listener.toState'),
        );
      case 'pointerDown':
      case 'pointerUp':
      case 'pointerEnter':
      case 'pointerExit':
      case 'pointerMove':
        if (hasAny(['layer', 'fromState', 'toState'])) {
          throw const FormatException(
              'pointer listener must not contain lifecycle fields');
        }
        final targetKindRaw =
            _required<String>(lm['targetKind'], 'listener.targetKind');
        final targetKind = switch (targetKindRaw) {
          'point' => PointerHelperTargetKind.point,
          'boundingBox' => PointerHelperTargetKind.boundingBox,
          _ => throw FormatException(
              'unknown listener targetKind: $targetKindRaw'),
        };
        bool? boolValue;
        double? numberValue;
        final value = lm['value'];
        if (value is bool) {
          boolValue = value;
        } else if (value is num) {
          numberValue = quantizeF32(value.toDouble());
        } else if (lm.containsKey('value')) {
          throw const FormatException('listener.value must be bool or number');
        }
        return StateMachineListener(
          name: lname,
          kind: switch (lkind) {
            'pointerDown' => StateMachineListenerKind.pointerDown,
            'pointerUp' => StateMachineListenerKind.pointerUp,
            'pointerEnter' => StateMachineListenerKind.pointerEnter,
            'pointerExit' => StateMachineListenerKind.pointerExit,
            _ => StateMachineListenerKind.pointerMove,
          },
          slot: _required<String>(lm['slot'], 'listener.slot'),
          targetKind: targetKind,
          target: _required<String>(lm['target'], 'listener.target'),
          hitRadius: lm.containsKey('hitRadius')
              ? quantizeF32(
                  _required<num>(lm['hitRadius'], 'listener.hitRadius')
                      .toDouble())
              : null,
          input: _required<String>(lm['input'], 'listener.input'),
          boolValue: boolValue,
          numberValue: numberValue,
        );
      default:
        throw FormatException('unknown listener kind: $lkind');
    }
  }).toList();

  return StateMachineData(
    name: name,
    layers: layers,
    inputs: inputs,
    listeners: listeners,
  );
}
