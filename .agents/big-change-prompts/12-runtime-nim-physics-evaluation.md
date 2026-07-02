# /big-change prompt - runtime evaluation (M5 physics constraint, Nim reference)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 2 of 4** of the M5 physics milestone. Depends on
> `11-contract-nim-physics-constraint-format.md` (the loadable
> `PhysicsConstraintData` record). Must land before
> `13-conformance-nim-physics-gate.md` (the golden needs a working evaluator).
> **Candidate category:** frontier.

---

/big-change Evaluate physics constraints at runtime in the Nim reference: wire the existing fixed-substep integrator into a stateful, time-stepped physics stage of the pose pipeline that runs after the world-transform/constraint pass.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

After prompt 11, a `physicsConstraint` is a loadable/validated format record but
is never evaluated. This prompt makes physics constraints affect the pose.

**Physics is bony's first stateful, time-dependent constraint.** IK, path, and
transform are pure functions of the setup/animated pose and are computed by
`computeWorldTransforms*(data: SkeletonData)`
(runtime-nim/src/bony/transform.nim:153), which today takes no time and no
mutable state. Physics needs BOTH a frame `dt` and per-instance mutable state
(`PhysicsConstraintState` per constraint, carried across frames). The central
design decision of this prompt is therefore the **stateful evaluation seam**;
the integrator math itself is already written and must not be reimplemented.

Already in place:
- The integrator: `runtime-nim/src/bony/constraints/physics_constraints.nim`
  (`updatePhysicsConstraint`, `integrateChannel`, `seedPhysicsChannel`,
  `PhysicsConstraintState`, `PhysicsChannel`, `PhysicsParams`,
  `physicsFixedDt/physicsMaxFrameDt/physicsMaxSubsteps`). This is the binding
  numeric implementation of `docs/physics-integrator-contract.md`.
- Ordering: `buildPhysicsConstraintOrder`
  (runtime-nim/src/bony/constraints/update_cache.nim:161) already returns
  physics constraints in the deterministic total order for the physics stage;
  the world-transform cache already excludes physics (update_cache.nim:116).
- The world-transform/constraint pass already ends its constraint-cache loop
  with an `else: discard` for `ckPhysics` at
  runtime-nim/src/bony/transform.nim:201 — that is correct: physics is a
  SEPARATE stage, not another entry in that loop.
- `PhysicsConstraintData` on `SkeletonData` (from prompt 11).

Build exactly this:
1. **Stateful evaluation seam.** Introduce a live-instance abstraction that owns
   the animated `SkeletonData`, the current local poses, and one
   `PhysicsConstraintState` per physics constraint (default all `accumulator=0`,
   `active`, channels un-`initialized` for lazy seeding per the contract's
   "Initialization"). Provide an advance entry point that takes a non-negative
   frame `dt` and: (a) runs the existing pure world-transform/constraint pass to
   produce the target pose; (b) runs the physics stage. Keep the existing pure
   `computeWorldTransforms*` working unchanged for setup-pose (`t=0`,
   effectively `dt=0`) callers — do not break M1-M9 goldens. Name and shape the
   seam to fit the current runtime (e.g. a `SkeletonInstance`-style object or an
   explicit state parameter threaded into an overload); confirm the exact shape
   against how the state-machine story runtime already advances a skeleton over
   time (see `runtime-nim/src/bony/statemachine/core.nim` — `StateMachineRuntime`
   is defined at core.nim:104 and advanced by `update*(runtime: var
   StateMachineRuntime; dt: float64)` at core.nim:676 — and the CLI story path in
   `cli/bony_cli.nim`, which already carries a `StateMachineRuntime` across
   samples) so the physics state lives on the same instance the story runner
   drives.
2. **Physics stage.** For each physics constraint in `buildPhysicsConstraintOrder`
   order: read the animated target value for each enabled `PhysicsChannel` from
   the current pose (decompose the constrained bone's animated local/world per
   `docs/transform-composition-contract.md`), call `updatePhysicsConstraint`
   with the frame `dt` and the constraint's `PhysicsConstraintState`, then fold
   each `PhysicsChannelOutput` back onto the bone's channel. Writeback and
   inherit/decomposition rules are owned by
   `docs/transform-composition-contract.md` and the channel-mapping section of
   `docs/physics-integrator-contract.md` (translation in world units, rotate/
   shearX in radians, scaleX unitless). Honor the reset/inactive-state rules in
   the contract ("Reset Semantics", "Determinism Requirements": preserve state
   but do not advance the accumulator while inactive; reset on reactivation).
   If multiple physics constraints affect the same channel, each reads the value
   left by earlier physics constraints and writes before later ones (contract
   "Constraint Ordering").
3. **Determinism.** All live state and substep arithmetic in f64; f32 rounding
   only at public output boundaries. `fixedDt` never varies by runtime/frame
   rate/host. No wall-clock time — only the supplied `dt`.
4. **Unit tests.** Add Nim tests (extend `runtime-nim/tests/test_smoke.nim` or a
   new `runtime-nim/tests/test_physics_eval.nim`) that drive the seam over a
   sequence of fixed `dt` frames and assert: (a) at `dt=0`/setup pose the
   physics stage is a no-op (offsets stay 0, pose equals the unconstrained
   pose); (b) over several `1/60`s frames a spring with non-zero `strength`
   produces a monotonic, settling offset that matches values computed directly
   from `updatePhysicsConstraint` (the stage and the raw integrator agree); (c)
   the accumulator/max-substep drop rule fires for a large `dt` exactly as
   `docs/physics-integrator-contract.md` specifies. If a test binary is emitted
   under `runtime-nim/tests/`, add it to `.gitignore` per repo Nim conventions.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Physics runtime contract (binding — integrator, substeps, reset, channel
  mapping, determinism): docs/physics-integrator-contract.md
- Writeback/inherit/decomposition contract: docs/transform-composition-contract.md
- Constraint order contract: docs/constraint-total-order.md
- Float math contract: docs/float-math-contract.md
- Nim integrator (do not reimplement): runtime-nim/src/bony/constraints/physics_constraints.nim
- Nim physics order: runtime-nim/src/bony/constraints/update_cache.nim
  (buildPhysicsConstraintOrder line 161; world-transform pass excludes physics
  at line 116)
- Nim world pass + pure entry point: runtime-nim/src/bony/transform.nim
  (computeWorldTransforms line 153; ckPhysics separate-stage note at the
  `else: discard` line 201; applyRuntimeTransformConstraint line 569 as the
  closest constrained-bone writeback template)
- State-machine story runtime (the existing across-samples time driver):
  runtime-nim/src/bony/statemachine/core.nim (StateMachineRuntime line 104,
  update* line 676); cli/bony_cli.nim (StateMachineRuntime
  carried across samples; note `requireSetupPoseTime` ~cli line 174: plain `--t`
  is setup-pose only —
  time-driven output goes through the state-machine story path)
- Repo gate: Makefile `test` target
- Beads: file under the physics milestone parent before implementing

**Success Criteria**
- A stateful advance seam exists that threads frame `dt` and per-instance
  `PhysicsConstraintState` through a physics stage running AFTER the
  world-transform/constraint pass, without changing the numeric output of the
  existing pure `computeWorldTransforms*` for any current M1-M9 golden.
- The physics stage evaluates constraints in `buildPhysicsConstraintOrder`
  order, calls `updatePhysicsConstraint` (not a reimplementation), and folds
  outputs back per the channel-mapping and transform-composition contracts.
- `nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim` is
  clean; all Nim unit tests pass, including the new physics-eval tests.
- The new tests demonstrate a **non-vacuous** spring response over time (settling
  offset) AND a `dt=0`/setup-pose no-op, and confirm the stage agrees with the
  raw integrator within `1e-4`.
- `make test` passes; every existing conformance golden (M1-M9) is unchanged.

**Constraints**
- Preserve clean-room posture (no third-party runtime/importer source, wire
  layouts, keys, or docs prose). Physics math and writeback are governed by the
  two project-owned contracts named above.
- Do **NOT** reimplement or algebraically rewrite the integrator — call
  `updatePhysicsConstraint`. Operation order in the per-substep loop is binding.
- Do **NOT** author the conformance rig/golden or the Dart runtime here — those
  are prompts 13 and 14.
- Do **NOT** add a new time source; time enters only as the supplied frame `dt`.
- Keep the slice to one meaningful implementation session: the stateful seam +
  physics stage + Nim unit tests. No format changes (done in prompt 11), no new
  conformance assets.
- Coverage note: `docs/physics-integrator-contract.md` lists a normative
  "Conformance Scenarios" set (dt=0 no-op, reset+dt=0, single-step,
  fractional-dt carry, max-substep clamp, excess-step drop, reset+nonzero-dt,
  reset-key crossing, independent channel state, two-constraints-same-channel,
  inactive-`skinRequired`). This prompt's three required unit tests cover the
  no-op, a settling spring, and the max-substep drop rule. That is intentionally
  a subset for this slice — `skinRequired` and reset-timeline authoring do not
  exist in the model yet (not physics-specific). File a follow-up bead to
  broaden physics unit coverage toward the full scenario list rather than
  silently dropping it.
