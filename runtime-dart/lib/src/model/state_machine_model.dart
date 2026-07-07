// --- M8 state machine types ---

enum StateMachineInputKind { bool_, number, trigger }

class StateMachineInput {
  const StateMachineInput({
    required this.name,
    required this.kind,
    this.defaultBool = false,
    this.defaultNumber = 0.0,
  });
  final String name;
  final StateMachineInputKind kind;
  final bool defaultBool;
  final double defaultNumber;
}

enum StateMachineConditionKind {
  boolEquals,
  numberEquals,
  numberGreater,
  numberGreaterOrEqual,
  numberLess,
  numberLessOrEqual,
  triggerSet,
}

class StateMachineCondition {
  const StateMachineCondition({
    required this.input,
    required this.kind,
    this.boolValue = false,
    this.numberValue = 0.0,
  });
  final String input;
  final StateMachineConditionKind kind;
  final bool boolValue;
  final double numberValue;
}

class StateMachineTransition {
  const StateMachineTransition({
    required this.fromState,
    required this.toState,
    required this.conditions,
  });
  final String fromState;
  final String toState;
  final List<StateMachineCondition> conditions;
}

enum StateMachineListenerKind {
  stateEnter,
  stateExit,
  transition_,
  pointerDown,
  pointerUp,
  pointerEnter,
  pointerExit,
  pointerMove,
}

enum PointerHelperTargetKind { point, boundingBox }

class StateMachineListener {
  const StateMachineListener({
    required this.name,
    required this.kind,
    this.layer = '',
    this.fromState = '',
    this.toState = '',
    this.slot = '',
    this.targetKind = PointerHelperTargetKind.point,
    this.target = '',
    this.hitRadius,
    this.input = '',
    this.boolValue,
    this.numberValue,
  });
  final String name;
  final StateMachineListenerKind kind;
  final String layer;
  final String fromState;
  final String toState;
  final String slot;
  final PointerHelperTargetKind targetKind;
  final String target;
  final double? hitRadius;
  final String input;
  final bool? boolValue;
  final double? numberValue;
}

enum StateMachineStateKind { clip, blend1d }

class StateMachineBlendClip {
  const StateMachineBlendClip({
    required this.clipName,
    required this.value,
    this.loop = false,
  });
  final String clipName;
  final double value;
  final bool loop;
}

class StateMachineState {
  const StateMachineState({
    required this.name,
    required this.kind,
    this.clipName = '',
    this.loop = false,
    this.blendInput = '',
    this.blendClips = const [],
  });
  final String name;
  final StateMachineStateKind kind;
  final String clipName;
  final bool loop;
  final String blendInput;
  final List<StateMachineBlendClip> blendClips;
}

class StateMachineLayer {
  const StateMachineLayer({
    required this.name,
    required this.states,
    required this.initialState,
    this.transitions = const [],
  });
  final String name;
  final List<StateMachineState> states;
  final String initialState;
  final List<StateMachineTransition> transitions;
}

class StateMachineData {
  const StateMachineData({
    required this.name,
    required this.layers,
    this.inputs = const [],
    this.listeners = const [],
  });
  final String name;
  final List<StateMachineLayer> layers;
  final List<StateMachineInput> inputs;
  final List<StateMachineListener> listeners;
}
