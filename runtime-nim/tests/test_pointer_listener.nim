import bony
import testutil


proc pointerFixture(): SkeletonData =
  skeletonData(
    skeletonHeader("pointer-test", "1.0.0"),
    @[
      boneData("root", "", localTransform(x = 10.0, y = 20.0, rotation = 90.0)),
      boneData("ui", ""),
    ],
    slots = @[
      slotData("locator_slot", "root", "tip"),
      slotData("button_slot", "ui", "button_hit"),
      slotData("point_slot", "ui", "tip"),
    ],
    pointAttachments = @[
      pointAttachmentData("tip", 5.0, 0.0, 15.0),
    ],
    boundingBoxAttachments = @[
      boundingBoxAttachmentData("button_hit", @[-10.0, -5.0, 10.0, -5.0, 10.0, 5.0, -10.0, 5.0]),
    ],
  )


proc pointerMachine(data: SkeletonData): StateMachine =
  let idle = animationClip(data, "idle")
  let active = animationClip(
    data,
    "active",
    @[boneScalarTimeline("ui", rotateTimeline, @[scalarKeyframe(0.0, 30.0)])],
  )
  stateMachine(
    "ui_machine",
    @[
      stateMachineLayer(
        "main",
        @[
          stateMachineState("idle", idle),
          stateMachineState("active", active),
        ],
        initialState = "idle",
        transitions = @[
          stateMachineTransition("idle", "active", @[stateMachineBoolCondition("pressed", true)]),
        ],
      ),
    ],
    inputs = @[
      stateMachineBoolInput("pressed"),
      stateMachineNumberInput("level"),
      stateMachineTriggerInput("pulse"),
    ],
    listeners = @[
      stateMachinePointerListener(
        "button_down",
        pointerDownListener,
        "button_slot",
        boundingBoxHelperTarget,
        "button_hit",
        "pressed",
        boolValue = true,
        hasBoolValue = true,
      ),
      stateMachinePointerListener(
        "point_move",
        pointerMoveListener,
        "point_slot",
        pointHelperTarget,
        "tip",
        "level",
        hitRadius = 2.0,
        hasHitRadius = true,
        numberValue = 7.0,
        hasNumberValue = true,
      ),
      stateMachinePointerListener(
        "point_up",
        pointerUpListener,
        "point_slot",
        pointHelperTarget,
        "tip",
        "pulse",
        hitRadius = 2.0,
        hasHitRadius = true,
      ),
      stateMachineStateExitListener("idle_exit", "main", "idle"),
      stateMachineTransitionListener("idle_to_active", "main", "idle", "active"),
      stateMachineStateEnterListener("active_enter", "main", "active"),
    ],
  )


block helperQueries:
  let data = pointerFixture()
  let worlds = computeWorldTransforms(data)
  let pose = worldPointAttachmentPose(data, worlds, "locator_slot", "tip")
  doAssert closeWithin(pose.x, 10.0, 1e-9)
  doAssert closeWithin(pose.y, 25.0, 1e-9)
  doAssert closeWithin(pose.rotation, 105.0, 1e-9)

  let polygon = worldBoundingBoxAttachmentPolygon(data, worlds, "button_slot", "button_hit")
  doAssert polygon.len == 4
  doAssert pointInHelperPolygon(helperPoint(0.0, 0.0), polygon)
  doAssert pointInHelperPolygon(helperPoint(10.00005, 0.0), polygon)
  doAssert not pointInHelperPolygon(helperPoint(10.01, 0.0), polygon)

block pointerDispatchMutatesInputsAndOrdersEvents:
  let data = pointerFixture()
  let machine = pointerMachine(data)
  validatePointerListenerTargets(data, machine)
  let worlds = computeWorldTransforms(data)
  var runtime = initStateMachineRuntime(machine)

  runtime.clearEvents()
  runtime.dispatchPointerListeners(data, worlds, "default", pointerMoveListener, 6.0, 0.0)
  doAssert closeWithin(runtime.getNumberInput("level"), 7.0, 1e-9)
  doAssert runtime.events.len == 1
  doAssert runtime.events[0].listener == "point_move"
  doAssert runtime.events[0].input == "level"
  doAssert runtime.events[0].hasNumberValue
  doAssert closeWithin(runtime.events[0].pointerX, 6.0, 1e-9)

  runtime.clearEvents()
  runtime.dispatchPointerListeners(data, worlds, "default", pointerUpListener, 6.0, 0.0)
  doAssert runtime.isTriggerSet("pulse")
  doAssert runtime.events.len == 1
  doAssert runtime.events[0].listener == "point_up"
  doAssert runtime.events[0].triggerValue

  runtime.clearEvents()
  runtime.dispatchPointerListeners(data, worlds, "default", pointerDownListener, 0.0, 0.0)
  runtime.update(0.0, preserveEvents = true)
  doAssert runtime.getBoolInput("pressed")
  doAssert runtime.layers[0].currentState == "active"
  doAssert runtime.events.len == 4
  doAssert runtime.events[0].listener == "button_down"
  doAssert runtime.events[1].listener == "idle_exit"
  doAssert runtime.events[2].listener == "idle_to_active"
  doAssert runtime.events[3].listener == "active_enter"


block directPointerListenerRejectsMismatchedInputKind:
  let data = pointerFixture()
  let idle = animationClip(data, "idle")
  let layer = stateMachineLayer("main", @[stateMachineState("idle", idle)])
  doAssert raisesBonyLoadError(
    proc() =
      discard stateMachine(
        "ui_machine",
        @[layer],
        inputs = @[stateMachineBoolInput("pressed")],
        listeners = @[
          StateMachineListener(
            name: "bad_move",
            kind: pointerMoveListener,
            slot: "point_slot",
            targetKind: pointHelperTarget,
            hitRadius: 2.0,
            target: "tip",
            input: "pressed",
            inputKind: numberInput,
            numberValue: 7.0,
          ),
        ],
      ),
    schemaViolation,
  )

echo "pointer helper listener tests passed"
