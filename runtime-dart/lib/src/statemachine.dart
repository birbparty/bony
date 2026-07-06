// M8 state machine runtime: inputs, layers, transitions, listeners, evaluate.
// Ports runtime-nim/src/bony/statemachine/core.nim.

import 'dart:math' as math;
import 'package:bony/src/anim.dart';
import 'deform.dart' show quantizeF32;
import 'model.dart';
import 'transform.dart'
    show Affine2, pointerHitsBoundingBoxTarget, pointerHitsPointTarget;

// --- Runtime input value ---

class _InputValue {
  _InputValue(
      {required this.name,
      required this.kind,
      this.boolValue = false,
      this.numberValue = 0.0});
  final String name;
  final StateMachineInputKind kind;
  bool boolValue;
  double numberValue;
}

// --- Runtime layer state ---

class _LayerRuntime {
  _LayerRuntime({required this.layer, required this.currentState});
  final StateMachineLayer layer;
  String currentState;
  double time = 0.0;
}

// --- Evaluated output types ---

class EvaluatedStateMachineLayer {
  const EvaluatedStateMachineLayer({
    required this.layer,
    required this.state,
    required this.time,
    required this.pose,
  });
  final String layer;
  final String state;
  final double time;
  final MixedPose pose;
}

class EvaluatedStateMachine {
  const EvaluatedStateMachine({required this.layers, required this.pose});
  final List<EvaluatedStateMachineLayer> layers;
  final MixedPose pose;
}

// --- Listener event ---

class StateMachineListenerEvent {
  const StateMachineListenerEvent({
    required this.listener,
    required this.kind,
    required this.layer,
    required this.fromState,
    required this.toState,
    this.slot = '',
    this.targetKind = PointerHelperTargetKind.point,
    this.target = '',
    this.input = '',
    this.inputKind = StateMachineInputKind.bool_,
    this.boolValue = false,
    this.hasBoolValue = false,
    this.numberValue = 0.0,
    this.hasNumberValue = false,
    this.triggerValue = false,
    this.pointerX = 0.0,
    this.pointerY = 0.0,
    this.hasPointer = false,
  });
  final String listener;
  final StateMachineListenerKind kind;
  final String layer;
  final String fromState;
  final String toState;
  final String slot;
  final PointerHelperTargetKind targetKind;
  final String target;
  final String input;
  final StateMachineInputKind inputKind;
  final bool boolValue;
  final bool hasBoolValue;
  final double numberValue;
  final bool hasNumberValue;
  final bool triggerValue;
  final double pointerX;
  final double pointerY;
  final bool hasPointer;
}

// --- Runtime ---

class StateMachineRuntime {
  StateMachineRuntime._(this._data, this._layers, this._inputs);

  final StateMachineData _data;
  final List<_LayerRuntime> _layers;
  final List<_InputValue> _inputs;
  final List<StateMachineListenerEvent> events = [];
  final List<DispatchedEvent> animationEvents = [];
  final List<AnimationState?> _layerAnimationStates = [];
  final List<String> _layerLoadedStates = [];
  final List<double> _layerPreviousTimes = [];
  SkeletonData? _layerAnimationData;
  bool _animationEventsValid = false;

  // Expose read-only state for tests/evaluation.
  String currentState(String layerName) {
    for (final lr in _layers) {
      if (lr.layer.name == layerName) return lr.currentState;
    }
    throw FormatException('unknown state machine layer: $layerName');
  }

  double layerTime(String layerName) {
    for (final lr in _layers) {
      if (lr.layer.name == layerName) return lr.time;
    }
    throw FormatException('unknown state machine layer: $layerName');
  }

  bool getBoolInput(String name) {
    for (final iv in _inputs) {
      if (iv.name == name) {
        if (iv.kind != StateMachineInputKind.bool_) {
          throw FormatException('state machine input is not bool: $name');
        }
        return iv.boolValue;
      }
    }
    throw FormatException('unknown state machine input: $name');
  }

  double getNumberInput(String name) {
    for (final iv in _inputs) {
      if (iv.name == name) {
        if (iv.kind != StateMachineInputKind.number) {
          throw FormatException('state machine input is not number: $name');
        }
        return iv.numberValue;
      }
    }
    throw FormatException('unknown state machine input: $name');
  }

  void setBoolInput(String name, bool value) {
    for (final iv in _inputs) {
      if (iv.name == name) {
        if (iv.kind != StateMachineInputKind.bool_) {
          throw FormatException('state machine input is not bool: $name');
        }
        iv.boolValue = value;
        return;
      }
    }
    throw FormatException('unknown state machine input: $name');
  }

  void setNumberInput(String name, double value) {
    for (final iv in _inputs) {
      if (iv.name == name) {
        if (iv.kind != StateMachineInputKind.number) {
          throw FormatException('state machine input is not number: $name');
        }
        iv.numberValue = quantizeF32(value);
        return;
      }
    }
    throw FormatException('unknown state machine input: $name');
  }

  void fireTrigger(String name) {
    for (final iv in _inputs) {
      if (iv.name == name) {
        if (iv.kind != StateMachineInputKind.trigger) {
          throw FormatException('state machine input is not trigger: $name');
        }
        iv.boolValue = true;
        return;
      }
    }
    throw FormatException('unknown state machine input: $name');
  }

  void dispatchPointerListeners(
    SkeletonData data,
    List<Affine2> worlds,
    String activeSkin,
    StateMachineListenerKind kind,
    double pointerX,
    double pointerY,
  ) {
    if (!_isPointerListenerKind(kind)) {
      throw const FormatException(
          'state-machine pointer dispatch kind is not a pointer listener kind');
    }
    if (!pointerX.isFinite) {
      throw const FormatException('stateMachine.pointer.x must be finite');
    }
    if (!pointerY.isFinite) {
      throw const FormatException('stateMachine.pointer.y must be finite');
    }
    for (final listener in _data.listeners) {
      if (listener.kind != kind) continue;
      if (_visibleSlotTarget(data, activeSkin, listener.slot) !=
          listener.target) {
        continue;
      }
      if (!_listenerHit(data, worlds, listener, pointerX, pointerY)) continue;

      final input = _inputByName(listener.input);
      switch (input.kind) {
        case StateMachineInputKind.bool_:
          setBoolInput(listener.input, listener.boolValue ?? false);
        case StateMachineInputKind.number:
          setNumberInput(listener.input, listener.numberValue ?? 0.0);
        case StateMachineInputKind.trigger:
          fireTrigger(listener.input);
      }
      events.add(StateMachineListenerEvent(
        listener: listener.name,
        kind: listener.kind,
        layer: '',
        fromState: '',
        toState: '',
        slot: listener.slot,
        targetKind: listener.targetKind,
        target: listener.target,
        input: listener.input,
        inputKind: input.kind,
        boolValue: listener.boolValue ?? false,
        hasBoolValue: listener.boolValue != null,
        numberValue: listener.numberValue ?? 0.0,
        hasNumberValue: listener.numberValue != null,
        triggerValue: input.kind == StateMachineInputKind.trigger,
        pointerX: pointerX,
        pointerY: pointerY,
        hasPointer: true,
      ));
    }
  }

  void update(double dt, {bool preserveEvents = false}) {
    if (dt < 0.0) throw ArgumentError.value(dt, 'dt', 'must be >= 0');
    if (!preserveEvents) {
      events.clear();
    }
    final step = quantizeF32(dt);
    for (final lr in _layers) {
      lr.time = quantizeF32(lr.time + step);
    }
    _applyTransitions();
    _animationEventsValid = false;
  }

  void _applyTransitions() {
    // Collect matched transitions per layer (one per layer at most, first match wins).
    final matched = <({int layerIndex, StateMachineTransition transition})>[];
    final consumedTriggers = <String>{};

    for (var li = 0; li < _layers.length; li++) {
      final lr = _layers[li];
      for (final t in lr.layer.transitions) {
        if (t.fromState != lr.currentState) continue;
        if (_transitionMatches(t)) {
          matched.add((layerIndex: li, transition: t));
          for (final c in t.conditions) {
            if (c.kind == StateMachineConditionKind.triggerSet) {
              consumedTriggers.add(c.input);
            }
          }
          break;
        }
      }
    }

    for (final m in matched) {
      final lr = _layers[m.layerIndex];
      final layerName = lr.layer.name;
      final from = m.transition.fromState;
      final to = m.transition.toState;
      _emitEvents(StateMachineListenerKind.stateExit, layerName, from, to);
      _emitEvents(StateMachineListenerKind.transition_, layerName, from, to);
      lr.currentState = to;
      lr.time = 0.0;
      _emitEvents(StateMachineListenerKind.stateEnter, layerName, from, to);
    }

    for (final name in consumedTriggers) {
      for (final iv in _inputs) {
        if (iv.name == name && iv.kind == StateMachineInputKind.trigger) {
          iv.boolValue = false;
          break;
        }
      }
    }
  }

  bool _transitionMatches(StateMachineTransition t) {
    for (final c in t.conditions) {
      if (!_conditionMatches(c)) return false;
    }
    return true;
  }

  StateMachineInput _inputByName(String name) {
    for (final input in _data.inputs) {
      if (input.name == name) return input;
    }
    throw FormatException('unknown state-machine input: $name');
  }

  bool _conditionMatches(StateMachineCondition c) {
    _InputValue? iv;
    for (final v in _inputs) {
      if (v.name == c.input) {
        iv = v;
        break;
      }
    }
    if (iv == null)
      throw FormatException('missing state machine runtime input: ${c.input}');
    switch (c.kind) {
      case StateMachineConditionKind.boolEquals:
        return iv.boolValue == c.boolValue;
      case StateMachineConditionKind.numberEquals:
        return iv.numberValue == c.numberValue;
      case StateMachineConditionKind.numberGreater:
        return iv.numberValue > c.numberValue;
      case StateMachineConditionKind.numberGreaterOrEqual:
        return iv.numberValue >= c.numberValue;
      case StateMachineConditionKind.numberLess:
        return iv.numberValue < c.numberValue;
      case StateMachineConditionKind.numberLessOrEqual:
        return iv.numberValue <= c.numberValue;
      case StateMachineConditionKind.triggerSet:
        return iv.boolValue;
    }
  }

  void _emitEvents(
    StateMachineListenerKind kind,
    String layerName,
    String fromState,
    String toState,
  ) {
    for (final listener in _data.listeners) {
      if (listener.kind != kind || listener.layer != layerName) continue;
      switch (kind) {
        case StateMachineListenerKind.stateEnter:
          if (listener.toState != toState) continue;
        case StateMachineListenerKind.stateExit:
          if (listener.fromState != fromState) continue;
        case StateMachineListenerKind.transition_:
          if (listener.fromState != fromState || listener.toState != toState)
            continue;
        case StateMachineListenerKind.pointerDown:
        case StateMachineListenerKind.pointerUp:
        case StateMachineListenerKind.pointerEnter:
        case StateMachineListenerKind.pointerExit:
        case StateMachineListenerKind.pointerMove:
          continue;
      }
      events.add(StateMachineListenerEvent(
        listener: listener.name,
        kind: kind,
        layer: layerName,
        fromState: fromState,
        toState: toState,
      ));
    }
  }

  EvaluatedStateMachine evaluate(SkeletonData data) {
    _updateAnimationEvents(data);

    final evalLayers = <EvaluatedStateMachineLayer>[];
    var combined = const MixedPose(
        scalars: [],
        vectors: [],
        attachments: [],
        inherits: [],
        colors: [],
        colors2: [],
        sequences: []);

    for (final lr in _layers) {
      final state = _stateByName(lr.layer, lr.currentState);
      final sampleTime = _computeSampleTime(data, state, lr.time);
      final pose = _sampleStatePose(data, state, lr.time);
      evalLayers.add(EvaluatedStateMachineLayer(
        layer: lr.layer.name,
        state: lr.currentState,
        time: sampleTime,
        pose: pose,
      ));
      combined = _overlayPose(combined, pose);
    }

    return EvaluatedStateMachine(layers: evalLayers, pose: combined);
  }

  void _ensureAnimationEventBridge(SkeletonData data) {
    if (identical(_layerAnimationData, data) &&
        _layerAnimationStates.length == _layers.length) {
      return;
    }
    final preserveLayerState = _layerPreviousTimes.length == _layers.length &&
        _layerLoadedStates.length == _layers.length;
    _layerAnimationData = data;
    _layerAnimationStates
      ..clear()
      ..addAll(List<AnimationState?>.filled(_layers.length, null));
    if (!preserveLayerState) {
      _layerLoadedStates
        ..clear()
        ..addAll(List<String>.filled(_layers.length, ''));
      _layerPreviousTimes
        ..clear()
        ..addAll(List<double>.filled(_layers.length, 0.0));
    }
  }

  void _updateAnimationEvents(SkeletonData data) {
    if (_animationEventsValid) return;
    animationEvents.clear();
    _ensureAnimationEventBridge(data);

    for (var layerIndex = 0; layerIndex < _layers.length; layerIndex++) {
      final lr = _layers[layerIndex];
      final state = _stateByName(lr.layer, lr.currentState);
      final previousTime = _layerPreviousTimes[layerIndex];
      final layerTimeReset = lr.time < previousTime;

      if (state.kind != StateMachineStateKind.clip) {
        _layerAnimationStates[layerIndex] = null;
        _layerLoadedStates[layerIndex] = '';
        _layerPreviousTimes[layerIndex] = lr.time;
        continue;
      }

      final sameLoadedState = _layerLoadedStates[layerIndex] == state.name;
      final needsReload = _layerAnimationStates[layerIndex] == null ||
          !sameLoadedState ||
          layerTimeReset;
      if (needsReload) {
        final clip = _findClip(data, state.clipName);
        _layerAnimationStates[layerIndex] = AnimationState(data)
          ..setAnimation(0, clip, loop: state.loop);
        if (!layerTimeReset && sameLoadedState && previousTime > 0.0) {
          _layerAnimationStates[layerIndex]!.tracks[0].current!.time =
              quantizeF32(previousTime);
        }
        _layerLoadedStates[layerIndex] = state.name;
      }

      final anim = _layerAnimationStates[layerIndex]!;
      final current = anim.tracks[0].current;
      final currentTime = current?.time ?? 0.0;
      final amount = math.max(0.0, lr.time - currentTime);
      anim.update(amount);
      animationEvents.addAll(anim.events);
      _layerPreviousTimes[layerIndex] = lr.time;
    }
    _animationEventsValid = true;
  }

  // Compute the wrapped sample time for evaluate's reported time field.
  // For blend1d: raw time. For clip: wrapped by loop/clamp then quantized.
  double _computeSampleTime(
      SkeletonData data, StateMachineState state, double time) {
    if (state.kind == StateMachineStateKind.blend1d) return time;
    final clip = _findClip(data, state.clipName);
    final wrapped = state.loop && clip.duration > 0
        ? time % clip.duration
        : math.min(time, clip.duration);
    return quantizeF32(wrapped);
  }

  MixedPose _sampleStatePose(
      SkeletonData data, StateMachineState state, double time) {
    if (state.kind == StateMachineStateKind.clip) {
      final clip = _findClip(data, state.clipName);
      return _sampleClipPose(data, clip, state.loop, time);
    } else {
      return _sampleBlendPose(data, state, time);
    }
  }

  MixedPose _sampleBlendPose(
      SkeletonData data, StateMachineState state, double time) {
    final input = getNumberInput(state.blendInput);
    final clips = state.blendClips;
    if (clips.isEmpty)
      return const MixedPose(
          scalars: [],
          vectors: [],
          attachments: [],
          inherits: [],
          colors: [],
          colors2: [],
          sequences: []);
    if (input <= clips.first.value) {
      return _sampleClipPose(
          data, _findClip(data, clips.first.clipName), clips.first.loop, time);
    }
    for (var i = 0; i < clips.length - 1; i++) {
      final lo = clips[i];
      final hi = clips[i + 1];
      if (input <= hi.value) {
        final t = hi.value == lo.value
            ? 0.0
            : (input - lo.value) / (hi.value - lo.value);
        final loClip = _findClip(data, lo.clipName);
        final hiClip = _findClip(data, hi.clipName);
        final loPose = _sampleClipPose(data, loClip, lo.loop, time);
        final hiPose = _sampleClipPose(data, hiClip, hi.loop, time);
        return _blendPoses(data, loPose, hiPose, t);
      }
    }
    final last = clips.last;
    return _sampleClipPose(
        data, _findClip(data, last.clipName), last.loop, time);
  }
}

// --- Free helpers ---

bool _isPointerListenerKind(StateMachineListenerKind kind) {
  switch (kind) {
    case StateMachineListenerKind.pointerDown:
    case StateMachineListenerKind.pointerUp:
    case StateMachineListenerKind.pointerEnter:
    case StateMachineListenerKind.pointerExit:
    case StateMachineListenerKind.pointerMove:
      return true;
    case StateMachineListenerKind.stateEnter:
    case StateMachineListenerKind.stateExit:
    case StateMachineListenerKind.transition_:
      return false;
  }
}

String _visibleSlotTarget(
  SkeletonData data,
  String activeSkin,
  String slotName,
) {
  for (final slot in data.slots) {
    if (slot.name == slotName) {
      return data.resolveSkinAttachmentTarget(
        activeSkin,
        slot.name,
        slot.attachment,
      );
    }
  }
  throw FormatException(
      'state-machine pointer listener slot references unknown slot: $slotName');
}

bool _listenerHit(
  SkeletonData data,
  List<Affine2> worlds,
  StateMachineListener listener,
  double pointerX,
  double pointerY,
) {
  switch (listener.targetKind) {
    case PointerHelperTargetKind.point:
      return pointerHitsPointTarget(
        data,
        worlds,
        listener.slot,
        listener.target,
        pointerX,
        pointerY,
        listener.hitRadius ?? 0.0,
      );
    case PointerHelperTargetKind.boundingBox:
      return pointerHitsBoundingBoxTarget(
        data,
        worlds,
        listener.slot,
        listener.target,
        pointerX,
        pointerY,
      );
  }
}

AnimationClip _findClip(SkeletonData data, String name) {
  for (final a in data.animations) {
    if (a.name == name) return a;
  }
  throw FormatException('state machine: clip not found: $name');
}

StateMachineState _stateByName(StateMachineLayer layer, String name) {
  for (final s in layer.states) {
    if (s.name == name) return s;
  }
  throw FormatException(
      'state machine: unknown state: $name in layer ${layer.name}');
}

MixedPose _sampleClipPose(
    SkeletonData data, AnimationClip clip, bool loop, double time) {
  final anim = AnimationState(data);
  anim.setAnimation(0, clip, loop: loop);
  final wrapped = loop && clip.duration > 0
      ? time % clip.duration
      : math.min(time, clip.duration);
  anim.tracks[0].current!.time = quantizeF32(wrapped);
  return anim.sample();
}

String _scalarKey(String bone, BoneTimelineKind kind) =>
    '$bone\x00${kind.index}';

// Overlay: later layer's value wins per channel key.
MixedPose _overlayPose(MixedPose base, MixedPose overlay) {
  final scalarMap =
      <String, ({String bone, BoneTimelineKind kind, double value})>{};
  for (final s in base.scalars) scalarMap[_scalarKey(s.bone, s.kind)] = s;
  for (final s in overlay.scalars) scalarMap[_scalarKey(s.bone, s.kind)] = s;
  final scalars = scalarMap.values.toList()
    ..sort((a, b) {
      final c = a.bone.compareTo(b.bone);
      return c != 0 ? c : a.kind.index.compareTo(b.kind.index);
    });

  final vecMap =
      <String, ({String bone, BoneTimelineKind kind, double x, double y})>{};
  for (final v in base.vectors) vecMap['${v.bone}\x00${v.kind.index}'] = v;
  for (final v in overlay.vectors) vecMap['${v.bone}\x00${v.kind.index}'] = v;
  final vectors = vecMap.values.toList()
    ..sort((a, b) {
      final c = a.bone.compareTo(b.bone);
      return c != 0 ? c : a.kind.index.compareTo(b.kind.index);
    });

  final attMap = <String, ({String slot, String attachment})>{};
  for (final a in base.attachments) attMap[a.slot] = a;
  for (final a in overlay.attachments) attMap[a.slot] = a;
  final attachments = attMap.values.toList()
    ..sort((a, b) => a.slot.compareTo(b.slot));

  final inhMap = <String, ({String bone, InheritKeyframe value})>{};
  for (final ih in base.inherits) inhMap[ih.bone] = ih;
  for (final ih in overlay.inherits) inhMap[ih.bone] = ih;
  final inherits = inhMap.values.toList()
    ..sort((a, b) => a.bone.compareTo(b.bone));

  final colMap =
      <String, ({String slot, SlotTimelineKind kind, ColorRgba color})>{};
  for (final c in base.colors) colMap['${c.slot}\x00${c.kind.index}'] = c;
  for (final c in overlay.colors) colMap['${c.slot}\x00${c.kind.index}'] = c;
  final colors = colMap.values.toList()
    ..sort((a, b) {
      final c = a.slot.compareTo(b.slot);
      return c != 0 ? c : a.kind.index.compareTo(b.kind.index);
    });

  final col2Map = <String, ({String slot, ColorRgba2 color})>{};
  for (final c in base.colors2) col2Map[c.slot] = c;
  for (final c in overlay.colors2) col2Map[c.slot] = c;
  final colors2 = col2Map.values.toList()
    ..sort((a, b) => a.slot.compareTo(b.slot));

  final seqMap = <String, ({String slot, SequenceKeyframe value})>{};
  for (final s in base.sequences) seqMap[s.slot] = s;
  for (final s in overlay.sequences) seqMap[s.slot] = s;
  final sequences = seqMap.values.toList()
    ..sort((a, b) => a.slot.compareTo(b.slot));

  // Carry the deform channel through the overlay (later layer wins per
  // slot+attachment key), mirroring the sibling discrete channels. Omitting it
  // silently drops every state-machine-driven mesh deform.
  final deformMap =
      <String, ({String slot, String attachment, List<MeshDelta> deltas})>{};
  for (final d in base.deforms) deformMap['${d.slot}\x00${d.attachment}'] = d;
  for (final d in overlay.deforms)
    deformMap['${d.slot}\x00${d.attachment}'] = d;
  final deforms = deformMap.values.toList()
    ..sort((a, b) {
      final c = a.slot.compareTo(b.slot);
      return c != 0 ? c : a.attachment.compareTo(b.attachment);
    });

  return MixedPose(
    scalars: scalars,
    vectors: vectors,
    attachments: attachments,
    inherits: inherits,
    colors: colors,
    colors2: colors2,
    sequences: sequences,
    deforms: deforms,
  );
}

// Linear blend between two blend1d clip poses.
// Vectors and scalars: lerp. Attachments/inherits/sequences: snap at t>=0.5.
// Colors: per-channel lerp.
MixedPose _blendPoses(SkeletonData data, MixedPose lo, MixedPose hi, double t) {
  // --- Scalars ---
  final scalarChannels = <String, ({String bone, BoneTimelineKind kind})>{};
  for (final s in lo.scalars)
    scalarChannels[_scalarKey(s.bone, s.kind)] = (bone: s.bone, kind: s.kind);
  for (final s in hi.scalars)
    scalarChannels[_scalarKey(s.bone, s.kind)] = (bone: s.bone, kind: s.kind);
  final loScalar = {
    for (final s in lo.scalars) _scalarKey(s.bone, s.kind): s.value
  };
  final hiScalar = {
    for (final s in hi.scalars) _scalarKey(s.bone, s.kind): s.value
  };

  double setupScalar(String bone, BoneTimelineKind kind) {
    for (final b in data.bones) {
      if (b.name != bone) continue;
      return switch (kind) {
        BoneTimelineKind.rotate => b.rotation,
        BoneTimelineKind.translateX => b.x,
        BoneTimelineKind.translateY => b.y,
        BoneTimelineKind.scaleX => b.scaleX,
        BoneTimelineKind.scaleY => b.scaleY,
        BoneTimelineKind.shearX => b.shearX,
        BoneTimelineKind.shearY => b.shearY,
        _ => 0.0,
      };
    }
    return 0.0;
  }

  final scalars = <({String bone, BoneTimelineKind kind, double value})>[];
  for (final entry in scalarChannels.entries) {
    final key = entry.key;
    final ch = entry.value;
    final setup = setupScalar(ch.bone, ch.kind);
    final loV = loScalar[key] ?? setup;
    final hiV = hiScalar[key] ?? setup;
    scalars.add((bone: ch.bone, kind: ch.kind, value: loV + (hiV - loV) * t));
  }
  scalars.sort((a, b) {
    final c = a.bone.compareTo(b.bone);
    return c != 0 ? c : a.kind.index.compareTo(b.kind.index);
  });

  // --- Vectors ---
  final vecChannels = <String, ({String bone, BoneTimelineKind kind})>{};
  for (final v in lo.vectors)
    vecChannels['${v.bone}\x00${v.kind.index}'] = (bone: v.bone, kind: v.kind);
  for (final v in hi.vectors)
    vecChannels['${v.bone}\x00${v.kind.index}'] = (bone: v.bone, kind: v.kind);
  final loVec = {
    for (final v in lo.vectors) '${v.bone}\x00${v.kind.index}': (x: v.x, y: v.y)
  };
  final hiVec = {
    for (final v in hi.vectors) '${v.bone}\x00${v.kind.index}': (x: v.x, y: v.y)
  };

  (double, double) setupVector(String bone, BoneTimelineKind kind) {
    for (final b in data.bones) {
      if (b.name != bone) continue;
      return switch (kind) {
        BoneTimelineKind.translate => (b.x, b.y),
        BoneTimelineKind.scale => (b.scaleX, b.scaleY),
        BoneTimelineKind.shear => (b.shearX, b.shearY),
        _ => (0.0, 0.0),
      };
    }
    return (0.0, 0.0);
  }

  final vectors =
      <({String bone, BoneTimelineKind kind, double x, double y})>[];
  for (final entry in vecChannels.entries) {
    final key = entry.key;
    final ch = entry.value;
    final setup = setupVector(ch.bone, ch.kind);
    final loV = loVec[key] ?? (x: setup.$1, y: setup.$2);
    final hiV = hiVec[key] ?? (x: setup.$1, y: setup.$2);
    vectors.add((
      bone: ch.bone,
      kind: ch.kind,
      x: loV.x + (hiV.x - loV.x) * t,
      y: loV.y + (hiV.y - loV.y) * t
    ));
  }
  vectors.sort((a, b) {
    final c = a.bone.compareTo(b.bone);
    return c != 0 ? c : a.kind.index.compareTo(b.kind.index);
  });

  // --- Stepped channels (attachments, inherits, sequences): snap at t >= 0.5 ---
  final snapPose = t >= 0.5 ? hi : lo;

  final attachments = snapPose.attachments.map((a) => a).toList()
    ..sort((a, b) => a.slot.compareTo(b.slot));

  final inherits = snapPose.inherits.map((ih) => ih).toList()
    ..sort((a, b) => a.bone.compareTo(b.bone));

  final sequences = snapPose.sequences.map((s) => s).toList()
    ..sort((a, b) => a.slot.compareTo(b.slot));

  // Deforms resolve winner-take-by-track-weight (docs/deform-timeline-contract.md),
  // like an attachment channel — the higher-weight clip's deltas win outright, never
  // a linear blend of the two sparse delta runs. So they snap with the other stepped
  // channels rather than lerping.
  final deforms = snapPose.deforms.map((d) => d).toList()
    ..sort((a, b) {
      final c = a.slot.compareTo(b.slot);
      return c != 0 ? c : a.attachment.compareTo(b.attachment);
    });

  // --- Colors: per-channel lerp ---
  final colChannels = <String, ({String slot, SlotTimelineKind kind})>{};
  for (final c in lo.colors)
    colChannels['${c.slot}\x00${c.kind.index}'] = (slot: c.slot, kind: c.kind);
  for (final c in hi.colors)
    colChannels['${c.slot}\x00${c.kind.index}'] = (slot: c.slot, kind: c.kind);
  final loCol = {
    for (final c in lo.colors) '${c.slot}\x00${c.kind.index}': c.color
  };
  final hiCol = {
    for (final c in hi.colors) '${c.slot}\x00${c.kind.index}': c.color
  };

  ColorRgba lerpColor(ColorRgba a, ColorRgba b, double f) => ColorRgba(
        r: a.r + (b.r - a.r) * f,
        g: a.g + (b.g - a.g) * f,
        b: a.b + (b.b - a.b) * f,
        a: a.a + (b.a - a.a) * f,
      );

  const _white = ColorRgba(r: 1.0, g: 1.0, b: 1.0, a: 1.0);
  final colors = <({String slot, SlotTimelineKind kind, ColorRgba color})>[];
  for (final entry in colChannels.entries) {
    final key = entry.key;
    final ch = entry.value;
    final loC = loCol[key] ?? _white;
    final hiC = hiCol[key] ?? _white;
    colors.add((slot: ch.slot, kind: ch.kind, color: lerpColor(loC, hiC, t)));
  }
  colors.sort((a, b) {
    final c = a.slot.compareTo(b.slot);
    return c != 0 ? c : a.kind.index.compareTo(b.kind.index);
  });

  // rgba2 channels
  final col2Channels = <String, String>{};
  for (final c in lo.colors2) col2Channels[c.slot] = c.slot;
  for (final c in hi.colors2) col2Channels[c.slot] = c.slot;
  final loCol2 = {for (final c in lo.colors2) c.slot: c.color};
  final hiCol2 = {for (final c in hi.colors2) c.slot: c.color};

  const _defaultColor2 = ColorRgba2(
    light: ColorRgba(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
    darkR: 0.0,
    darkG: 0.0,
    darkB: 0.0,
  );
  final colors2 = <({String slot, ColorRgba2 color})>[];
  for (final slot in col2Channels.keys) {
    final loC = loCol2[slot] ?? _defaultColor2;
    final hiC = hiCol2[slot] ?? _defaultColor2;
    colors2.add((
      slot: slot,
      color: ColorRgba2(
        light: lerpColor(loC.light, hiC.light, t),
        darkR: loC.darkR + (hiC.darkR - loC.darkR) * t,
        darkG: loC.darkG + (hiC.darkG - loC.darkG) * t,
        darkB: loC.darkB + (hiC.darkB - loC.darkB) * t,
      ),
    ));
  }
  colors2.sort((a, b) => a.slot.compareTo(b.slot));

  return MixedPose(
    scalars: scalars,
    vectors: vectors,
    attachments: attachments,
    inherits: inherits,
    colors: colors,
    colors2: colors2,
    sequences: sequences,
    deforms: deforms,
  );
}

// --- Factory ---

StateMachineRuntime initStateMachineRuntime(StateMachineData data) {
  final layers = data.layers.map((l) {
    final initial =
        l.initialState.isNotEmpty ? l.initialState : l.states.first.name;
    return _LayerRuntime(layer: l, currentState: initial);
  }).toList();

  final inputs = data.inputs.map((inp) {
    switch (inp.kind) {
      case StateMachineInputKind.bool_:
        return _InputValue(
            name: inp.name, kind: inp.kind, boolValue: inp.defaultBool);
      case StateMachineInputKind.number:
        return _InputValue(
            name: inp.name, kind: inp.kind, numberValue: inp.defaultNumber);
      case StateMachineInputKind.trigger:
        return _InputValue(name: inp.name, kind: inp.kind);
    }
  }).toList();

  return StateMachineRuntime._(data, layers, inputs);
}
