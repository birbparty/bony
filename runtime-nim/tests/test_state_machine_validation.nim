include smoke_support

spec "state machine validation smoke coverage":
  it "rejects invalid state-machine core data":
    let data = animationFixture()
    let idle = animationClip(data, "idle")
    let layer = stateMachineLayer("base", @[stateMachineState("idle", idle)])
    let machine = stateMachine("machine", @[layer])

    then:
      raisesBonyLoadError(proc() = discard stateMachineState("", idle), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineLayer("", @[stateMachineState("idle", idle)]), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineLayer("base", @[]), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineLayer("base", @[stateMachineState("idle", idle), stateMachineState("idle", idle)]), duplicateKey)
      raisesBonyLoadError(proc() = discard stateMachineLayer("base", @[stateMachineState("idle", idle)], initialState = "missing"), unknownRequiredReference)
      raisesBonyLoadError(proc() = discard stateMachine("", @[layer]), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachine("machine", @[]), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachine("machine", @[layer, layer]), duplicateKey)
      raisesBonyLoadError(
        proc() =
          var invalidRuntime = StateMachineRuntime(machine: machine, layers: @[])
          invalidRuntime.update(0.0),
        schemaViolation,
      )
      raisesBonyLoadError(proc() = discard StateMachineRuntime(machine: machine, layers: @[]).evaluate(), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineBlendClip(animationClip(data, ""), 0.0), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineBlendClip(idle, Inf), numericOutOfRange)
      raisesBonyLoadError(proc() = discard stateMachineBlendState("", "speed", @[stateMachineBlendClip(idle, 0.0)]), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineBlendState("move", "", @[stateMachineBlendClip(idle, 0.0)]), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineBlendState("move", "speed", @[]), schemaViolation)
      raisesBonyLoadError(proc() =
        discard stateMachineBlendState("move", "speed", @[
          stateMachineBlendClip(idle, 0.0),
          stateMachineBlendClip(idle, 0.0),
        ]),
        duplicateKey,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine(
          "machine",
          @[stateMachineLayer("base", @[stateMachineBlendState("move", "missing", @[stateMachineBlendClip(idle, 0.0)])])],
        ),
        unknownRequiredReference,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine(
          "machine",
          @[stateMachineLayer("base", @[stateMachineBlendState("move", "armed", @[stateMachineBlendClip(idle, 0.0)])])],
          @[stateMachineBoolInput("armed")],
        ),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        discard stateMachineLayer(
          "base",
          @[StateMachineState(name: "move", kind: blend1DState, clip: idle, blendInput: "speed", blendClips: @[stateMachineBlendClip(idle, 0.0)])],
        ),
        schemaViolation,
      )

    var runtime = initStateMachineRuntime(machine)
    let extraLayer = stateMachineLayer("base", @[stateMachineState("idle", idle), stateMachineState("wave", animationClip(data, "wave"))])

    then:
      raisesBonyLoadError(proc() = runtime.setState("missing", "idle"), unknownRequiredReference)
      raisesBonyLoadError(proc() = runtime.setState("base", "missing"), unknownRequiredReference)
      raisesBonyLoadError(proc() = runtime.update(-0.1), schemaViolation)
      raisesBonyLoadError(proc() =
        var direct = StateMachineRuntime(
          machine: machine,
          layers: @[StateMachineLayerRuntime(layer: extraLayer, currentState: "idle")],
        )
        direct.setState("base", "wave"),
        unknownRequiredReference,
      )

  it "stores typed state-machine inputs at runtime":
    let data = animationFixture()
    let idle = animationClip(data, "idle")
    let machine = stateMachine(
      "machine",
      @[stateMachineLayer("base", @[stateMachineState("idle", idle)])],
      @[
        stateMachineBoolInput("armed", defaultValue = true),
        stateMachineNumberInput("speed", defaultValue = 0.25),
        stateMachineTriggerInput("jump"),
      ],
    )
    var runtime = initStateMachineRuntime(machine)

    then:
      runtime.machine.inputs.len == 3
      runtime.inputs.len == 3
      runtime.getBoolInput("armed")
      closeTo(runtime.getNumberInput("speed"), quantizeF32(0.25))
      not runtime.isTriggerSet("jump")

    runtime.setBoolInput("armed", false)
    runtime.setNumberInput("speed", 2.5)
    runtime.fireTrigger("jump")

    then:
      not runtime.getBoolInput("armed")
      closeTo(runtime.getNumberInput("speed"), 2.5)
      runtime.isTriggerSet("jump")

    runtime.clearTrigger("jump")

    then:
      not runtime.isTriggerSet("jump")

    runtime.setNumberInput("speed", 0.1)
    runtime.fireTrigger("jump")

    then:
      closeTo(runtime.getNumberInput("speed"), quantizeF32(0.1))
      runtime.consumeTrigger("jump")
      not runtime.isTriggerSet("jump")

    runtime.fireTrigger("jump")
    runtime.resetInputs()

    then:
      runtime.getBoolInput("armed")
      closeTo(runtime.getNumberInput("speed"), quantizeF32(0.25))
      not runtime.isTriggerSet("jump")

  it "rejects invalid state-machine typed inputs":
    let data = animationFixture()
    let idle = animationClip(data, "idle")
    let layer = stateMachineLayer("base", @[stateMachineState("idle", idle)])
    let machine = stateMachine(
      "machine",
      @[layer],
      @[stateMachineBoolInput("armed"), stateMachineNumberInput("speed"), stateMachineTriggerInput("jump")],
    )

    then:
      raisesBonyLoadError(proc() = discard stateMachineBoolInput(""), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineNumberInput("bad", defaultValue = Inf), numericOutOfRange)
      raisesBonyLoadError(
        proc() = discard stateMachine(
          "machine",
          @[layer],
          @[StateMachineInput(name: "armed", kind: boolInput, defaultNumber: 1.0)],
        ),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = discard stateMachine(
          "machine",
          @[layer],
          @[StateMachineInput(name: "armed", kind: boolInput, defaultNumber: Inf)],
        ),
        numericOutOfRange,
      )
      raisesBonyLoadError(
        proc() = discard stateMachine(
          "machine",
          @[layer],
          @[StateMachineInput(name: "speed", kind: numberInput, defaultBool: true)],
        ),
        schemaViolation,
      )

    then:
      raisesBonyLoadError(proc() =
        discard stateMachine(
          "machine",
          @[layer],
          @[stateMachineBoolInput("dup"), stateMachineTriggerInput("dup")],
        ),
        duplicateKey,
      )
      raisesBonyLoadError(
        proc() = discard stateMachine(
          "machine",
          @[layer],
          @[StateMachineInput(name: "jump", kind: triggerInput, defaultBool: true)],
        ),
        schemaViolation,
      )

    var runtime = initStateMachineRuntime(machine)

    then:
      raisesBonyLoadError(proc() = discard runtime.getBoolInput("missing"), unknownRequiredReference)
      raisesBonyLoadError(proc() = discard runtime.getBoolInput("speed"), schemaViolation)
      raisesBonyLoadError(proc() =
        let malformedRuntime = StateMachineRuntime(
          machine: machine,
          layers: runtime.layers,
          inputs: @[
            StateMachineInputValue(name: "speed", kind: numberInput),
            StateMachineInputValue(name: "jump", kind: triggerInput),
          ],
        )
        discard malformedRuntime.getBoolInput("armed"),
        unknownRequiredReference,
      )
      raisesBonyLoadError(proc() =
        let malformedRuntime = StateMachineRuntime(
          machine: machine,
          layers: runtime.layers,
          inputs: @[
            StateMachineInputValue(name: "armed", kind: numberInput),
            StateMachineInputValue(name: "speed", kind: numberInput),
            StateMachineInputValue(name: "jump", kind: triggerInput),
          ],
        )
        discard malformedRuntime.getBoolInput("armed"),
        schemaViolation,
      )
      raisesBonyLoadError(proc() = runtime.setNumberInput("speed", Inf), numericOutOfRange)
      raisesBonyLoadError(proc() = runtime.fireTrigger("armed"), schemaViolation)
      raisesBonyLoadError(proc() =
        var invalidRuntime = StateMachineRuntime(
          machine: machine,
          layers: runtime.layers,
          inputs: @[
            StateMachineInputValue(name: "armed", kind: boolInput),
            StateMachineInputValue(name: "speed", kind: numberInput, numberValue: Inf),
            StateMachineInputValue(name: "jump", kind: triggerInput),
          ],
        )
        invalidRuntime.update(0.0),
        numericOutOfRange,
      )
      raisesBonyLoadError(proc() =
        discard StateMachineRuntime(
          machine: machine,
          layers: runtime.layers,
          inputs: @[
            StateMachineInputValue(name: "armed", kind: boolInput),
            StateMachineInputValue(name: "speed", kind: numberInput, numberValue: Inf),
            StateMachineInputValue(name: "jump", kind: triggerInput),
          ],
        ).evaluate(),
        numericOutOfRange,
      )
      raisesBonyLoadError(proc() =
        var invalidRuntime = StateMachineRuntime(
          machine: machine,
          layers: runtime.layers,
          inputs: @[StateMachineInputValue(name: "armed", kind: boolInput)],
        )
        invalidRuntime.update(0.0),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        discard StateMachineRuntime(
          machine: machine,
          layers: runtime.layers,
          inputs: @[StateMachineInputValue(name: "armed", kind: boolInput)],
        ).evaluate(),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        var invalidRuntime = StateMachineRuntime(
          machine: machine,
          layers: runtime.layers,
          inputs: @[StateMachineInputValue(name: "armed", kind: boolInput)],
        )
        discard invalidRuntime.consumeTrigger("jump"),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        var invalidRuntime = StateMachineRuntime(
          machine: machine,
          layers: runtime.layers,
          inputs: @[
            StateMachineInputValue(name: "armed", kind: boolInput),
            StateMachineInputValue(name: "speed", kind: boolInput),
            StateMachineInputValue(name: "jump", kind: triggerInput),
          ],
        )
        invalidRuntime.update(0.0),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        discard StateMachineRuntime(
          machine: machine,
          layers: runtime.layers,
          inputs: @[
            StateMachineInputValue(name: "armed", kind: boolInput),
            StateMachineInputValue(name: "speed", kind: boolInput),
            StateMachineInputValue(name: "jump", kind: triggerInput),
          ],
        ).evaluate(),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        var invalidRuntime = StateMachineRuntime(
          machine: machine,
          layers: runtime.layers,
          inputs: @[
            StateMachineInputValue(name: "armed", kind: boolInput),
            StateMachineInputValue(name: "speed", kind: numberInput),
            StateMachineInputValue(name: "speed", kind: numberInput),
          ],
        )
        invalidRuntime.update(0.0),
        duplicateKey,
      )
      raisesBonyLoadError(proc() =
        discard StateMachineRuntime(
          machine: machine,
          layers: runtime.layers,
          inputs: @[
            StateMachineInputValue(name: "armed", kind: boolInput),
            StateMachineInputValue(name: "speed", kind: numberInput),
            StateMachineInputValue(name: "speed", kind: numberInput),
          ],
        ).evaluate(),
        duplicateKey,
      )

  it "rejects invalid state-machine listeners":
    let data = animationFixture()
    let idle = animationClip(data, "idle")
    let wave = animationClip(data, "wave")
    let states = @[stateMachineState("idle", idle), stateMachineState("wave", wave)]
    let layer = stateMachineLayer(
      "base",
      states,
      transitions = @[stateMachineTransition("idle", "wave", @[stateMachineBoolCondition("armed")])],
    )

    then:
      raisesBonyLoadError(proc() = discard stateMachineStateEnterListener("", "base", "wave"), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineTransitionListener("changed", "base", "idle", ""), schemaViolation)
      raisesBonyLoadError(proc() =
        discard stateMachine("machine", @[layer], @[stateMachineBoolInput("armed")], listeners = @[
          stateMachineStateEnterListener("changed", "missing", "wave"),
        ]),
        unknownRequiredReference,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine("machine", @[layer], @[stateMachineBoolInput("armed")], listeners = @[
          stateMachineStateEnterListener("changed", "base", "missing"),
        ]),
        unknownRequiredReference,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine("machine", @[layer], @[stateMachineBoolInput("armed")], listeners = @[
          stateMachineStateEnterListener("changed", "base", "wave"),
          stateMachineStateExitListener("changed", "base", "idle"),
        ]),
        duplicateKey,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine("machine", @[layer], @[stateMachineBoolInput("armed")], listeners = @[
          stateMachineTransitionListener("changed", "base", "wave", "idle"),
        ]),
        unknownRequiredReference,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine("machine", @[layer], @[stateMachineBoolInput("armed")], listeners = @[
          StateMachineListener(
            name: "changed",
            kind: stateEnterListener,
            layer: "base",
            fromState: "idle",
            toState: "wave",
          ),
        ]),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine("machine", @[layer], @[stateMachineBoolInput("armed")], listeners = @[
          StateMachineListener(
            name: "changed",
            kind: stateExitListener,
            layer: "base",
            fromState: "idle",
            toState: "wave",
          ),
        ]),
        schemaViolation,
      )

  it "rejects invalid state-machine transitions and conditions":
    let data = animationFixture()
    let idle = animationClip(data, "idle")
    let wave = animationClip(data, "wave")
    let states = @[stateMachineState("idle", idle), stateMachineState("wave", wave)]

    then:
      raisesBonyLoadError(proc() = discard stateMachineTransition("", "wave", @[stateMachineBoolCondition("armed")]), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineTransition("idle", "wave", @[]), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineNumberCondition("speed", boolEqualsCondition, 1.0), schemaViolation)
      raisesBonyLoadError(proc() =
        discard stateMachineLayer(
          "base",
          states,
          transitions = @[stateMachineTransition("missing", "wave", @[stateMachineBoolCondition("armed")])],
        ),
        unknownRequiredReference,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine(
          "machine",
          @[stateMachineLayer("base", states, transitions = @[stateMachineTransition("idle", "wave", @[stateMachineBoolCondition("missing")])])],
        ),
        unknownRequiredReference,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine(
          "machine",
          @[stateMachineLayer("base", states, transitions = @[stateMachineTransition("idle", "wave", @[stateMachineBoolCondition("speed")])])],
          @[stateMachineNumberInput("speed")],
        ),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine(
          "machine",
          @[stateMachineLayer("base", states, transitions = @[stateMachineTransition("idle", "wave", @[stateMachineNumberCondition("armed", numberGreaterCondition, 0.0)])])],
          @[stateMachineBoolInput("armed")],
        ),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine(
          "machine",
          @[stateMachineLayer("base", states, transitions = @[stateMachineTransition("idle", "wave", @[stateMachineTriggerCondition("armed")])])],
          @[stateMachineBoolInput("armed")],
        ),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        discard stateMachineTransition(
          "idle",
          "wave",
          @[StateMachineCondition(input: "armed", kind: boolEqualsCondition, numberValue: 1.0)],
        ),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        discard stateMachineTransition(
          "idle",
          "wave",
          @[StateMachineCondition(input: "go", kind: triggerSetCondition, boolValue: true)],
        ),
        schemaViolation,
      )

  it "loads m8_rig.bony conformance asset":
    let data = loadBonyJson(readFile(repoPath("conformance", "assets", "m8_rig.bony")))
    let machines = loadBonyJsonStateMachines(readFile(repoPath("conformance", "assets", "m8_rig.bony")))
    then:
      data.header.name == "m8-rig"
      data.bones.len == 2
      data.slots.len == 1
      data.regions.len == 2
      machines.len == 1
      machines[0].name == "gesture"
      machines[0].inputs.len == 3
      machines[0].layers.len == 2
      machines[0].layers[0].name == "body"
      machines[0].layers[0].states.len == 2
      machines[0].layers[1].name == "face"
      machines[0].listeners.len == 3

  it "loads m9_non_scalar_rig.bony conformance asset":
    let data = loadBonyJson(readFile(repoPath("conformance", "assets", "m9_non_scalar_rig.bony")))
    let clips = loadBonyJsonAnimations(readFile(repoPath("conformance", "assets", "m9_non_scalar_rig.bony")))
    let clipCount = clips.len
    let slideKind = clips["slide"].boneTimelines[0].kind
    let slideVectorLen = clips["slide"].boneTimelines[0].vectorKeys.len
    let growKind = clips["grow"].boneTimelines[0].kind
    let leanKind = clips["lean"].boneTimelines[0].kind
    let inheritKind = clips["inherit_switch"].boneTimelines[0].kind
    let inheritKeyLen = clips["inherit_switch"].boneTimelines[0].inheritKeys.len
    let inheritMode = clips["inherit_switch"].boneTimelines[0].inheritKeys[1].transformMode
    let blinkSlotLen = clips["blink"].slotTimelines.len
    let blinkKind = clips["blink"].slotTimelines[0].kind
    let blinkAttLen = clips["blink"].slotTimelines[0].attachmentKeys.len
    let fadeKind = clips["fade"].slotTimelines[0].kind
    let tintKind = clips["tint"].slotTimelines[0].kind
    let alphaKind = clips["alpha_pulse"].slotTimelines[0].kind
    let rgba2Kind = clips["two_color"].slotTimelines[0].kind
    let color2Len = clips["two_color"].slotTimelines[0].color2Keys.len
    let seqKind = clips["fx_sequence"].slotTimelines[0].kind
    let seqKeyLen = clips["fx_sequence"].slotTimelines[0].sequenceKeys.len
    let comboBoneLen = clips["combo"].boneTimelines.len
    let comboSlotLen = clips["combo"].slotTimelines.len
    then:
      data.header.name == "m9-non-scalar-rig"
      data.bones.len == 3
      data.slots.len == 3
      data.regions.len == 6
      clipCount == 11
      clips.hasKey("slide")
      clips.hasKey("grow")
      clips.hasKey("lean")
      clips.hasKey("inherit_switch")
      clips.hasKey("blink")
      clips.hasKey("fade")
      clips.hasKey("tint")
      clips.hasKey("alpha_pulse")
      clips.hasKey("two_color")
      clips.hasKey("fx_sequence")
      clips.hasKey("combo")
      slideKind == translateTimeline
      slideVectorLen == 2
      growKind == scaleTimeline
      leanKind == shearTimeline
      inheritKind == inheritTimeline
      inheritKeyLen == 2
      inheritMode == noScale
      blinkSlotLen == 1
      blinkKind == attachmentTimeline
      blinkAttLen == 3
      fadeKind == rgbaTimeline
      tintKind == rgbTimeline
      alphaKind == alphaTimeline
      rgba2Kind == rgba2Timeline
      color2Len == 2
      seqKind == sequenceTimeline
      seqKeyLen == 2
      comboBoneLen == 3
      comboSlotLen == 2

  it "rejects M8 state machine with unknown clip reference":
    const badClipJson = """
      {
        "skeleton": {"name": "bad-clip"},
        "bones": [{"name": "root"}],
        "slots": [],
        "animations": [],
        "stateMachines": [
          {
            "name": "test",
            "layers": [
              {
                "name": "body",
                "states": [
                  {"name": "idle", "kind": "clip", "clip": "nonexistent"}
                ]
              }
            ]
          }
        ]
      }
    """
    then:
      raisesBonyLoadError(proc() =
        discard loadBonyJsonStateMachines(badClipJson)
      , unknownRequiredReference)

  it "rejects M8 animation with unknown bone reference":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-bone"},
          "bones": [{"name": "root"}],
          "slots": [],
          "animations": [
            {
              "name": "anim",
              "boneTimelines": [
                {
                  "bone": "nonexistent_bone",
                  "property": "rotate",
                  "keyframes": [{"t": 0.0, "value": 0.0}]
                }
              ]
            }
          ]
        }
      """, unknownRequiredReference)

  it "rejects M8 state machine kind with invalid value":
    const badKindJson = """
      {
        "skeleton": {"name": "bad-kind"},
        "bones": [{"name": "root"}],
        "slots": [],
        "animations": [
          {"name": "idle", "boneTimelines": [{"bone": "root", "property": "rotate", "keyframes": [{"t": 0.0, "value": 0.0}]}]}
        ],
        "stateMachines": [
          {
            "name": "test",
            "layers": [
              {
                "name": "body",
                "states": [
                  {"name": "idle", "kind": "badkind", "clip": "idle"}
                ]
              }
            ]
          }
        ]
      }
    """
    then:
      raisesBonyLoadError(proc() =
        discard loadBonyJsonStateMachines(badKindJson)
      , schemaViolation)

  it "rejects M8 animation keyframe curve with non-string type":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-curve"},
          "bones": [{"name": "root"}],
          "slots": [],
          "animations": [
            {
              "name": "anim",
              "boneTimelines": [
                {
                  "bone": "root",
                  "property": "rotate",
                  "keyframes": [{"t": 0.0, "value": 0.0, "curve": 42}]
                }
              ]
            }
          ]
        }
      """, schemaViolation)

  it "rejects duplicate M8 state machine names":
    const dupMachineJson = """
      {
        "skeleton": {"name": "dup-machine"},
        "bones": [{"name": "root"}],
        "slots": [],
        "animations": [
          {"name": "idle", "boneTimelines": [{"bone": "root", "property": "rotate", "keyframes": [{"t": 0.0, "value": 0.0}]}]}
        ],
        "stateMachines": [
          {
            "name": "gesture",
            "layers": [
              {
                "name": "body",
                "states": [{"name": "idle", "kind": "clip", "clip": "idle"}]
              }
            ]
          },
          {
            "name": "gesture",
            "layers": [
              {
                "name": "body",
                "states": [{"name": "idle", "kind": "clip", "clip": "idle"}]
              }
            ]
          }
        ]
      }
    """
    then:
      raisesBonyLoadError(proc() =
        discard loadBonyJsonStateMachines(dupMachineJson)
      , duplicateKey)

  it "loads a bezier keyframe from JSON":
    const bezierJson = """
      {
        "skeleton": {"name": "bezier-test"},
        "bones": [{"name": "root"}],
        "slots": [],
        "animations": [
          {
            "name": "anim",
            "boneTimelines": [
              {
                "bone": "root",
                "property": "rotate",
                "keyframes": [
                  {"t": 0.0, "value": 0.0},
                  {"t": 1.0, "value": 90.0, "curve": "bezier",
                   "c1x": 0.25, "c1y": 0.0, "c2x": 0.75, "c2y": 1.0}
                ]
              }
            ]
          }
        ]
      }
    """
    let data = loadBonyJson(bezierJson)
    then:
      data.header.name == "bezier-test"
      data.bones.len == 1

  it "rejects bezier keyframe with missing c1x":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-bezier"},
          "bones": [{"name": "root"}],
          "slots": [],
          "animations": [
            {
              "name": "anim",
              "boneTimelines": [
                {
                  "bone": "root",
                  "property": "rotate",
                  "keyframes": [{"t": 0.0, "value": 0.0},
                    {"t": 1.0, "value": 90.0, "curve": "bezier",
                     "c1y": 0.0, "c2x": 0.75, "c2y": 1.0}]
                }
              ]
            }
          ]
        }
      """, schemaViolation)

  it "rejects bezier keyframe with c1x out of range":
    then:
      raisesBonyLoadError(proc() =
        discard loadBonyJson("""
          {
            "skeleton": {"name": "bad-bezier"},
            "bones": [{"name": "root"}],
            "slots": [],
            "animations": [
              {
                "name": "anim",
                "boneTimelines": [
                  {
                    "bone": "root",
                    "property": "rotate",
                    "keyframes": [{"t": 0.0, "value": 0.0},
                      {"t": 1.0, "value": 90.0, "curve": "bezier",
                       "c1x": -0.1, "c1y": 0.0, "c2x": 0.75, "c2y": 1.0}]
                  }
                ]
              }
            ]
          }
        """)
      , schemaViolation)

  it "rejects M8 blend1d state with unknown blendInput":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-blendinput"},
          "bones": [{"name": "root"}],
          "animations": [{"name": "idle", "boneTimelines": []}],
          "stateMachines": [{
            "name": "m",
            "inputs": [],
            "layers": [{
              "name": "body",
              "states": [
                {"name": "idle", "kind": "blend1d",
                 "blendInput": "nonexistent",
                 "blendClips": [{"clip": "idle", "value": 0.0}]}
              ]
            }]
          }]
        }
      """, unknownRequiredReference)

  it "rejects M8 transition with unknown fromState":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-fromstate"},
          "bones": [{"name": "root"}],
          "animations": [{"name": "idle", "boneTimelines": []}],
          "stateMachines": [{
            "name": "m",
            "inputs": [{"name": "wave", "kind": "bool"}],
            "layers": [{
              "name": "body",
              "states": [{"name": "idle", "kind": "clip", "clip": "idle"}],
              "transitions": [
                {"fromState": "nonexistent", "toState": "idle",
                 "conditions": [{"input": "wave", "kind": "boolEquals", "value": true}]}
              ]
            }]
          }]
        }
      """, unknownRequiredReference)

  it "rejects M8 transition with unknown toState":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-tostate"},
          "bones": [{"name": "root"}],
          "animations": [{"name": "idle", "boneTimelines": []}],
          "stateMachines": [{
            "name": "m",
            "inputs": [{"name": "wave", "kind": "bool"}],
            "layers": [{
              "name": "body",
              "states": [{"name": "idle", "kind": "clip", "clip": "idle"}],
              "transitions": [
                {"fromState": "idle", "toState": "nonexistent",
                 "conditions": [{"input": "wave", "kind": "boolEquals", "value": true}]}
              ]
            }]
          }]
        }
      """, unknownRequiredReference)

  it "rejects M8 condition with unknown input":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-condinput"},
          "bones": [{"name": "root"}],
          "animations": [{"name": "idle", "boneTimelines": []}, {"name": "walk", "boneTimelines": []}],
          "stateMachines": [{
            "name": "m",
            "inputs": [{"name": "wave", "kind": "bool"}],
            "layers": [{
              "name": "body",
              "states": [
                {"name": "idle", "kind": "clip", "clip": "idle"},
                {"name": "walk", "kind": "clip", "clip": "walk"}
              ],
              "transitions": [
                {"fromState": "idle", "toState": "walk",
                 "conditions": [{"input": "nonexistent", "kind": "boolEquals", "value": true}]}
              ]
            }]
          }]
        }
      """, unknownRequiredReference)

  it "rejects M8 listener with unknown layer":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-lstlayer"},
          "bones": [{"name": "root"}],
          "animations": [{"name": "idle", "boneTimelines": []}],
          "stateMachines": [{
            "name": "m",
            "inputs": [],
            "layers": [{
              "name": "body",
              "states": [{"name": "idle", "kind": "clip", "clip": "idle"}]
            }],
            "listeners": [
              {"name": "ev", "kind": "stateEnter", "layer": "nonexistent", "toState": "idle"}
            ]
          }]
        }
      """, unknownRequiredReference)

  it "rejects M8 stateEnter listener with unknown toState":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-enter-tostate"},
          "bones": [{"name": "root"}],
          "animations": [{"name": "idle", "boneTimelines": []}],
          "stateMachines": [{
            "name": "m",
            "inputs": [],
            "layers": [{
              "name": "body",
              "states": [{"name": "idle", "kind": "clip", "clip": "idle"}]
            }],
            "listeners": [
              {"name": "ev", "kind": "stateEnter", "layer": "body", "toState": "nonexistent"}
            ]
          }]
        }
      """, unknownRequiredReference)

  it "rejects M8 stateExit listener with unknown fromState":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-exit-fromstate"},
          "bones": [{"name": "root"}],
          "animations": [{"name": "idle", "boneTimelines": []}],
          "stateMachines": [{
            "name": "m",
            "inputs": [],
            "layers": [{
              "name": "body",
              "states": [{"name": "idle", "kind": "clip", "clip": "idle"}]
            }],
            "listeners": [
              {"name": "ev", "kind": "stateExit", "layer": "body", "fromState": "nonexistent"}
            ]
          }]
        }
      """, unknownRequiredReference)

  it "rejects M8 transition listener with unknown fromState":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-tr-fromstate"},
          "bones": [{"name": "root"}],
          "animations": [{"name": "idle", "boneTimelines": []}],
          "stateMachines": [{
            "name": "m",
            "inputs": [],
            "layers": [{
              "name": "body",
              "states": [
                {"name": "idle", "kind": "clip", "clip": "idle"},
                {"name": "move", "kind": "clip", "clip": "idle"}
              ]
            }],
            "listeners": [
              {"name": "ev", "kind": "transition", "layer": "body",
               "fromState": "nonexistent", "toState": "move"}
            ]
          }]
        }
      """, unknownRequiredReference)

  it "rejects M8 transition listener with unknown toState":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-tr-tostate"},
          "bones": [{"name": "root"}],
          "animations": [{"name": "idle", "boneTimelines": []}],
          "stateMachines": [{
            "name": "m",
            "inputs": [],
            "layers": [{
              "name": "body",
              "states": [
                {"name": "idle", "kind": "clip", "clip": "idle"},
                {"name": "move", "kind": "clip", "clip": "idle"}
              ]
            }],
            "listeners": [
              {"name": "ev", "kind": "transition", "layer": "body",
               "fromState": "idle", "toState": "nonexistent"}
            ]
          }]
        }
      """, unknownRequiredReference)
