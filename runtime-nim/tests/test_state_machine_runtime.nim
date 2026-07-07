include smoke_support

spec "state machine runtime smoke coverage":
  it "evaluates state-machine layers through current animation states":
    let data = animationFixture()
    var dataRef = new SkeletonData
    dataRef[] = data
    let idle = animationClip(
      data,
      "idle",
      @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 0.0), scalarKeyframe(1.0, 10.0)])],
    )
    let blink = animationClip(
      data,
      "blink",
      @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 90.0)])],
      slotTimelines = @[slotColorTimeline("body", alphaTimeline, @[colorKeyframe(0.0, colorRgba(1.0, 1.0, 1.0, 0.25))])],
    )
    let machine = stateMachine(
      "face",
      @[
        stateMachineLayer("base", @[stateMachineState("idle", idle, loop = true)]),
        stateMachineLayer("eyes", @[stateMachineState("blink", blink)]),
      ],
    )
    var runtime = initStateMachineRuntime(machine)
    runtime.update(0.5)
    let evaluated = runtime.evaluate(dataRef)

    then:
      evaluated.layers.len == 2
      evaluated.layers[0].layer == "base"
      evaluated.layers[0].state == "idle"
      closeTo(evaluated.layers[0].time, 0.5)
      closeTo(evaluated.layers[0].pose.scalars[0].value, 5.0)
      evaluated.layers[1].layer == "eyes"
      evaluated.layers[1].state == "blink"
      closeTo(evaluated.layers[1].pose.colors[0].color.a, 0.25)
      evaluated.pose.scalars.len == 1
      closeTo(evaluated.pose.scalars[0].value, 90.0)
      evaluated.pose.colors.len == 1
      closeTo(evaluated.pose.colors[0].color.a, 0.25)

  it "switches state-machine layer states and clamps non-looping time":
    let data = animationFixture()
    let idle = animationClip(
      data,
      "idle",
      @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 0.0), scalarKeyframe(1.0, 10.0)])],
    )
    let wave = animationClip(
      data,
      "wave",
      @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 100.0), scalarKeyframe(1.0, 120.0)])],
    )
    let machine = stateMachine(
      "gesture",
      @[stateMachineLayer("base", @[stateMachineState("idle", idle), stateMachineState("wave", wave)], initialState = "idle")],
    )
    var runtime = initStateMachineRuntime(machine)
    runtime.setState("base", "wave")
    runtime.update(2.0)
    let evaluated = runtime.evaluate()

    then:
      runtime.layers[0].currentState == "wave"
      closeTo(evaluated.layers[0].time, 1.0)
      closeTo(evaluated.layers[0].pose.scalars[0].value, 120.0)

  it "evaluates one-dimensional state-machine blend states":
    let data = animationFixture()
    let idle = animationClip(
      data,
      "idle",
      @[
        boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 0.0), scalarKeyframe(1.0, 10.0)]),
        boneVectorTimeline("root", translateTimeline, @[vector2Keyframe(0.0, 0.0, 0.0), vector2Keyframe(1.0, 10.0, 20.0)]),
      ],
    )
    let run = animationClip(
      data,
      "run",
      @[
        boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 100.0), scalarKeyframe(1.0, 120.0)]),
        boneVectorTimeline("root", translateTimeline, @[vector2Keyframe(0.0, 20.0, 40.0), vector2Keyframe(1.0, 30.0, 60.0)]),
      ],
    )
    let machine = stateMachine(
      "locomotion",
      @[
        stateMachineLayer(
          "base",
          @[
            stateMachineBlendState(
              "move",
              "speed",
              @[stateMachineBlendClip(run, 1.0), stateMachineBlendClip(idle, 0.0)],
            ),
          ],
        ),
      ],
      @[stateMachineNumberInput("speed", 0.25)],
    )
    var runtime = initStateMachineRuntime(machine)
    runtime.update(0.5)
    var evaluated = runtime.evaluate()

    then:
      evaluated.layers[0].state == "move"
      closeTo(evaluated.layers[0].time, 0.5)
      closeTo(evaluated.layers[0].pose.scalars[0].value, 31.25)
      closeTo(evaluated.layers[0].pose.vectors[0].x, 10.0)
      closeTo(evaluated.layers[0].pose.vectors[0].y, 20.0)

    runtime.setNumberInput("speed", 2.0)
    evaluated = runtime.evaluate()

    then:
      closeTo(evaluated.pose.scalars[0].value, 110.0)

  it "uses state-machine blend states with transitions":
    let data = animationFixture()
    let idle = animationClip(data, "idle", @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 0.0)])])
    let walk = animationClip(data, "walk", @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 40.0)])])
    let run = animationClip(data, "run", @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 100.0)])])
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer(
          "base",
          @[
            stateMachineState("idle", idle),
            stateMachineBlendState(
              "move",
              "speed",
              @[stateMachineBlendClip(walk, 0.0), stateMachineBlendClip(run, 1.0)],
            ),
          ],
          transitions = @[stateMachineTransition("idle", "move", @[stateMachineBoolCondition("moving")])],
        ),
      ],
      @[stateMachineBoolInput("moving"), stateMachineNumberInput("speed", 0.5)],
      listeners = @[stateMachineStateEnterListener("move-enter", "base", "move")],
    )
    var runtime = initStateMachineRuntime(machine)
    runtime.setBoolInput("moving", true)
    runtime.update(0.0)
    let evaluated = runtime.evaluate()

    then:
      runtime.layers[0].currentState == "move"
      runtime.events.len == 1
      runtime.events[0].listener == "move-enter"
      closeTo(evaluated.pose.scalars[0].value, 70.0)

  it "blends missing state-machine blend channels from setup pose":
    var dataValue = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[boneData("root", "", localTransform(rotation = 30.0, scaleX = 1.0, scaleY = 1.0))],
    )
    let data = new SkeletonData
    data[] = dataValue
    let keyed = animationClip(
      data[],
      "keyed",
      @[
        boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 10.0)]),
        boneVectorTimeline("root", scaleTimeline, @[vector2Keyframe(0.0, 2.0, 2.0)]),
      ],
    )
    let sparse = animationClip(data[], "sparse")
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer(
          "base",
          @[stateMachineBlendState("move", "blend", @[stateMachineBlendClip(keyed, 0.0), stateMachineBlendClip(sparse, 1.0)])],
        ),
      ],
      @[stateMachineNumberInput("blend", 0.5)],
    )
    let evaluated = initStateMachineRuntime(machine).evaluate(data)

    then:
      evaluated.pose.scalars.len == 1
      closeTo(evaluated.pose.scalars[0].value, 20.0)
      evaluated.pose.vectors.len == 1
      closeTo(evaluated.pose.vectors[0].x, 1.5)
      closeTo(evaluated.pose.vectors[0].y, 1.5)

  it "evaluates state-machine transitions and typed conditions":
    let data = animationFixture()
    let idle = animationClip(data, "idle", @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 0.0)])])
    let wave = animationClip(data, "wave", @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 90.0)])])
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer(
          "base",
          @[stateMachineState("idle", idle), stateMachineState("wave", wave)],
          transitions = @[
            stateMachineTransition(
              "idle",
              "wave",
              @[
                stateMachineBoolCondition("armed"),
                stateMachineNumberCondition("speed", numberGreaterOrEqualCondition, 1.0),
                stateMachineTriggerCondition("go"),
              ],
            ),
            stateMachineTransition("wave", "idle", @[stateMachineBoolCondition("armed", false)]),
          ],
        ),
      ],
      @[stateMachineBoolInput("armed"), stateMachineNumberInput("speed"), stateMachineTriggerInput("go")],
    )
    var runtime = initStateMachineRuntime(machine)
    runtime.fireTrigger("go")
    runtime.update(0.25)

    then:
      runtime.layers[0].currentState == "idle"
      closeTo(runtime.layers[0].time, 0.25)
      runtime.isTriggerSet("go")

    runtime.setBoolInput("armed", true)
    runtime.setNumberInput("speed", 1.0)
    runtime.update(0.5)
    let evaluated = runtime.evaluate()

    then:
      runtime.layers[0].currentState == "wave"
      closeTo(runtime.layers[0].time, 0.0)
      not runtime.isTriggerSet("go")
      evaluated.layers[0].state == "wave"
      closeTo(evaluated.pose.scalars[0].value, 90.0)

    runtime.update(0.25)
    runtime.setBoolInput("armed", false)
    runtime.update(0.0)

    then:
      runtime.layers[0].currentState == "idle"
      closeTo(runtime.layers[0].time, 0.0)

  it "uses first matching transition per state-machine layer":
    let data = animationFixture()
    let idle = animationClip(data, "idle")
    let first = animationClip(data, "first")
    let second = animationClip(data, "second")
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer(
          "base",
          @[stateMachineState("idle", idle), stateMachineState("first", first), stateMachineState("second", second)],
          transitions = @[
            stateMachineTransition("idle", "first", @[stateMachineBoolCondition("armed")]),
            stateMachineTransition("idle", "second", @[stateMachineBoolCondition("armed")]),
          ],
        ),
      ],
      @[stateMachineBoolInput("armed")],
    )
    var runtime = initStateMachineRuntime(machine)
    runtime.setBoolInput("armed", true)
    runtime.update(0.0)

    then:
      runtime.layers[0].currentState == "first"

  it "lets one trigger drive transitions across multiple state-machine layers":
    let data = animationFixture()
    let idle = animationClip(data, "idle")
    let wave = animationClip(data, "wave")
    let open = animationClip(data, "open")
    let blink = animationClip(data, "blink")
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer(
          "base",
          @[stateMachineState("idle", idle), stateMachineState("wave", wave)],
          transitions = @[stateMachineTransition("idle", "wave", @[stateMachineTriggerCondition("go")])],
        ),
        stateMachineLayer(
          "eyes",
          @[stateMachineState("open", open), stateMachineState("blink", blink)],
          transitions = @[stateMachineTransition("open", "blink", @[stateMachineTriggerCondition("go")])],
        ),
      ],
      @[stateMachineTriggerInput("go")],
    )
    var runtime = initStateMachineRuntime(machine)
    runtime.fireTrigger("go")
    runtime.update(0.0)

    then:
      runtime.layers[0].currentState == "wave"
      runtime.layers[1].currentState == "blink"
      not runtime.isTriggerSet("go")

  it "emits state-machine listener events for matching transitions":
    let data = animationFixture()
    let idle = animationClip(data, "idle")
    let wave = animationClip(data, "wave")
    let open = animationClip(data, "open")
    let blink = animationClip(data, "blink")
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer(
          "base",
          @[stateMachineState("idle", idle), stateMachineState("wave", wave)],
          transitions = @[stateMachineTransition("idle", "wave", @[stateMachineBoolCondition("armed")])],
        ),
        stateMachineLayer(
          "eyes",
          @[stateMachineState("open", open), stateMachineState("blink", blink)],
          transitions = @[stateMachineTransition("open", "blink", @[stateMachineBoolCondition("armed")])],
        ),
      ],
      @[stateMachineBoolInput("armed")],
      listeners = @[
        stateMachineStateExitListener("base-idle-exit", "base", "idle"),
        stateMachineTransitionListener("base-idle-wave", "base", "idle", "wave"),
        stateMachineStateEnterListener("base-wave-enter", "base", "wave"),
        stateMachineStateEnterListener("eyes-blink-enter", "eyes", "blink"),
      ],
    )
    var runtime = initStateMachineRuntime(machine)
    runtime.update(0.0)

    then:
      runtime.layers[0].currentState == "idle"
      runtime.events.len == 0

    runtime.setBoolInput("armed", true)
    runtime.update(0.0)

    then:
      runtime.layers[0].currentState == "wave"
      runtime.layers[1].currentState == "blink"
      runtime.events.len == 4
      runtime.events[0].listener == "base-idle-exit"
      runtime.events[0].kind == stateExitListener
      runtime.events[0].layer == "base"
      runtime.events[0].fromState == "idle"
      runtime.events[0].toState == "wave"
      runtime.events[1].listener == "base-idle-wave"
      runtime.events[1].kind == transitionListener
      runtime.events[2].listener == "base-wave-enter"
      runtime.events[2].kind == stateEnterListener
      runtime.events[3].listener == "eyes-blink-enter"
      runtime.events[3].layer == "eyes"
      runtime.events[3].fromState == "open"
      runtime.events[3].toState == "blink"

    runtime.update(0.0)

    then:
      runtime.events.len == 0

  it "loads M8 animations from JSON":
    let data = loadBonyJson("""
      {
        "skeleton": {"name": "anim-test"},
        "bones": [{"name": "root"}],
        "slots": [],
        "animations": [
          {
            "name": "idle",
            "boneTimelines": [
              {
                "bone": "root",
                "property": "rotate",
                "keyframes": [
                  {"t": 0.0, "value": 0.0},
                  {"t": 1.0, "value": 10.0}
                ]
              }
            ]
          }
        ]
      }
    """)
    then:
      data.header.name == "anim-test"
      data.bones.len == 1

  it "loads M8 state machine from JSON":
    let machines = loadBonyJsonStateMachines("""
      {
        "skeleton": {"name": "sm-test"},
        "bones": [{"name": "root"}],
        "slots": [],
        "animations": [
          {"name": "idle", "boneTimelines": [{"bone": "root", "property": "rotate", "keyframes": [{"t": 0.0, "value": 0.0}]}]},
          {"name": "wave", "boneTimelines": [{"bone": "root", "property": "rotate", "keyframes": [{"t": 0.0, "value": 90.0}]}]}
        ],
        "stateMachines": [
          {
            "name": "gesture",
            "inputs": [
              {"name": "wave", "kind": "bool"},
              {"name": "speed", "kind": "number", "default": 0.5},
              {"name": "jump", "kind": "trigger"}
            ],
            "layers": [
              {
                "name": "body",
                "states": [
                  {"name": "idle", "kind": "clip", "clip": "idle", "loop": true},
                  {"name": "wave", "kind": "clip", "clip": "wave"}
                ],
                "initialState": "idle",
                "transitions": [
                  {
                    "fromState": "idle",
                    "toState": "wave",
                    "conditions": [{"input": "wave", "kind": "boolEquals", "value": true}]
                  }
                ]
              }
            ],
            "listeners": [
              {"name": "wave_enter", "kind": "stateEnter", "layer": "body", "toState": "wave"},
              {"name": "idle_exit", "kind": "stateExit", "layer": "body", "fromState": "idle"},
              {"name": "idle_to_wave", "kind": "transition", "layer": "body", "fromState": "idle", "toState": "wave"}
            ]
          }
        ]
      }
    """)
    then:
      machines.len == 1
      machines[0].name == "gesture"
      machines[0].inputs.len == 3
      machines[0].inputs[0].name == "wave"
      machines[0].inputs[0].kind == boolInput
      machines[0].inputs[1].name == "speed"
      machines[0].inputs[1].kind == numberInput
      machines[0].inputs[2].name == "jump"
      machines[0].inputs[2].kind == triggerInput
      machines[0].layers.len == 1
      machines[0].layers[0].name == "body"
      machines[0].layers[0].states.len == 2
      machines[0].layers[0].initialState == "idle"
      machines[0].layers[0].transitions.len == 1
      machines[0].listeners.len == 3

  it "loads M8 blend1d state from JSON":
    let machines = loadBonyJsonStateMachines("""
      {
        "skeleton": {"name": "blend-test"},
        "bones": [{"name": "root"}],
        "slots": [],
        "animations": [
          {"name": "walk", "boneTimelines": [{"bone": "root", "property": "rotate", "keyframes": [{"t": 0.0, "value": 5.0}]}]},
          {"name": "run",  "boneTimelines": [{"bone": "root", "property": "rotate", "keyframes": [{"t": 0.0, "value": 15.0}]}]}
        ],
        "stateMachines": [
          {
            "name": "move",
            "inputs": [{"name": "speed", "kind": "number", "default": 0.0}],
            "layers": [
              {
                "name": "body",
                "states": [
                  {
                    "name": "locomotion",
                    "kind": "blend1d",
                    "blendInput": "speed",
                    "blendClips": [
                      {"clip": "walk", "value": 0.5, "loop": true},
                      {"clip": "run",  "value": 1.0, "loop": true}
                    ]
                  }
                ]
              }
            ]
          }
        ]
      }
    """)
    then:
      machines.len == 1
      machines[0].layers[0].states[0].kind == blend1DState
      machines[0].layers[0].states[0].blendClips.len == 2
