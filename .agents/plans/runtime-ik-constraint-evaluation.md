# Big Change Planning with Beads

## Agent Instructions

You are an expert software architect creating a comprehensive task breakdown for a change to an existing codebase. This task graph will be executed by AI agents working in parallel, coordinated through MCP Agent Mail with file reservations to prevent conflicts.

<quality_expectations>
Create a thorough, production-ready task graph. Include all necessary analysis, preparation, implementation, testing, and documentation tasks. Go beyond the basics — consider edge cases, error handling, security considerations, backwards compatibility, and integration points. Each task should be specific enough for an agent to execute independently without ambiguity.
</quality_expectations>

<critical_constraint>
You must NOT implement any of the changes yourself. Your ONLY output is a bash shell script containing `bd create` and `bd dep add` commands. Do NOT use `bd add` — the correct command is `bd create`. Do not write code. Do not create files other than the shell script. Do not modify existing files. Read and analyze the codebase, then produce the script.

The script MUST create a single parent **epic** first (`bd create -t epic`) and parent **every** task bead to it via `--parent "$EPIC"`, so the whole change is one trackable rollup. The epic is an organizational rollup only — never make it a blocking dependency (do NOT `bd dep add` to or from the epic; `bd dep add` is for real ordering edges between task beads, and a blocking edge on an epic both excludes it wrongly and inverts `bd dep tree`). Membership is the `--parent` relationship, nothing else.
</critical_constraint>

## Change Information

### Change Type
NEW_FEATURE — wiring an already-frozen format (step-1 IK registry keys, JSON schema, and `IkConstraintData`) into the Nim reference runtime so IK constraints actually load and evaluate, plus Dart model-load parity. Carries a strong refactor/serialization-stability discipline (every bead must keep `.bnb` byte-stable and all conformance gates green under ralph's merge-to-main-per-bead model).

This is **step 2 of 3** of the M5 IK milestone (Beads epic `bony-dqo`, coarse step `bony-me5`). Step 1 (format freeze) is COMPLETE and merged to green main. Step 3 (conformance: `m5_ik_rig` asset + golden + `.bnb` + gate) is out of scope here and tracked separately (`bony-grr`).

### Description
Make IK constraints runtime-evaluable in the Nim reference runtime (load JSON + `.bnb`, integrate the existing solver into the pose pass) and load them in the Dart model for parity. Mirror exactly how **path** constraints are loaded and evaluated. No new format keys or schema fields beyond what step 1 froze — if step 2 reveals the step-1 format is insufficient, STOP and amend step 1's registry/schema rather than inventing keys here.

Concrete work surface (all line numbers verified against current `main` on 2026-06-29):

- **JSON load/emit** in `runtime-nim/src/bony/jsonio.nim`. IK is genuinely absent today. Add load + emit mirroring the path-constraint precedent, and add the IK root array key to `validateKnownKeys(root, [...])` at **jsonio.nim:311** (current list is `["skeleton","bones","slots","regions","pathAttachments","paths","parameters","deformers","animations","stateMachines"]` — IK assets are rejected as unknown-keys until `ikConstraints` is added). The root array key is `ikConstraints` to match `SkeletonData.ikConstraints`; confirm exact spelling against the canonical schema (`codegen/generate.py:579` and `runtime-nim/src/bony/generated/wire.nim:159` objectSpec) before coding. **Byte-stability (symmetric with the binary gating):** the JSON emitter must OMIT the `ikConstraints` key entirely when the list is empty — emitting `"ikConstraints": []` unconditionally would change every existing JSON golden and break `test_json_bnb_json_idempotency.nim` when this bead merges alone.

- **Binary encode/decode** in `runtime-nim/src/bony/binary/semantic.nim`. No IK type/property keys exist there yet. The frozen registry values live in generated `runtime-nim/src/bony/generated/wire.nim`: type `ikConstraint=4002` (wire.nim:47); properties `bones=4014` backingType `bytes` (wire.nim:100), `mix=4015` `f32` (wire.nim:101), `bendPositive=4016` `bool` (wire.nim:102); objectSpec properties `[name, bones, target, order, mix, bendPositive]` (wire.nim:159) where `target` and `order` REUSE the existing shared property keys (semantic.nim already has `targetKey=4000` line 51, `orderKey=4002` line 53 — note type-key `4002` and property-key `4002` are in SEPARATE namespaces, no collision, per `docs/ik-constraint-format-contract.md`). Add the IK constants to semantic.nim mirroring the path literals (`pathTypeKey=4000'u64` line 19), and an IK emit loop mirroring the path-constraint loop `for path in data.paths` at **semantic.nim:876** (NOT the sibling `pathAttachment` loop at line 863).
  - **`bones` packed-bytes layout is FROZEN (contract §2):** `varuint count, followed by count × (varuint STRING-TABLE index for the bone name)`, chain order root→tip — the SAME packing precedent as `blendAxes` (key 6041). These are string-table indices, NOT skeleton bone-order indices (the two are different namespaces; using bone-order indices would emit non-conformant bytes and fail round-trip). On encode, intern each bone name into the string table and write its table index; on decode, read indices and resolve back through the string table. Mirror the existing `blendAxes` pack/unpack helper rather than inventing index math.
  - **Emit placement (byte-stability):** emit the IK section ONLY when `ikConstraints` is non-empty, so existing fixtures stay byte-identical. PIN the IK section's position in the object stream and confirm it against `docs/binary-canonicalization.md` (the existing order is `pathAttachments` then `paths`, i.e. NOT typeKey-sorted) so the new `bnb→json→bnb` direction is itself stable. Note property emit order within the record is NOT load-bearing — `normalizedProperties` sorts records by key at encode — so do not assume the wire.nim objectSpec order (`bones` before `target`) carries through.

- **Combined deterministic ordered update-cache** in `runtime-nim/src/bony/constraints/update_cache.nim`. The generic `buildConstraintUpdateCache` (update_cache.nim:107) already sorts every `ConstraintKind` except `ckPhysics` (line 116) — including `ckIk` — by `docs/constraint-total-order.md` priority. **Do not build a second independent IK cache.** Today `transform.nim:136` calls `buildPathConstraintUpdateCache(data)`, which emits only path descriptors. Replace it with ONE builder that emits descriptors for BOTH path and IK constraints into a single `descriptors` seq and calls `buildConstraintUpdateCache(data.bones, descriptors)` once, so cross-kind ordering (ckIk priority before ckPath) is correct. For IK descriptors set `writes` = the constrained `bones` list and `reads` = `@[target]` ONLY — do NOT also list the bones' parents. `buildPathConstraintUpdateCache` (line 172) sets `reads = @[path.target]` and the parent lineage is walked automatically by `emitReadDependencies` (update_cache.nim:88–104); duplicating the lineage here would diverge from the path precedent. (For IK specifically, the constrained bones are mutually parent→child and are all in `writes`, so under `buildConstraintUpdateCache` none of them are emitted before the constraint — `applyRuntimeIk` must FK-compose the chain itself; see the write-back note below.)

- **Pose-pipeline integration** in `runtime-nim/src/bony/transform.nim`. TWO changes are required, both in the core bead:
  - **Extend the entry gate.** `computeWorldTransforms` only enters the constraint-applying branch when `hasRuntimePaths` is true (transform.nim:127–133, scanning `data.paths` only); a skeleton with IK constraints but no runtime-evaluable path constraint falls through to the plain branch (transform.nim:158–167) that ignores ALL constraints. Extend the precondition to ALSO fire when any IK constraint is `runtimeEvaluable`. Without this, a pure-IK rig compiles, passes existing tests, and silently never evaluates — the single easiest defect to ship here.
  - **Dispatch by kind.** The cache apply loop is at lines 142–156; today every `ccekConstraint` entry goes to `applyRuntimePathConstraint` (lines 251–324). Dispatch each `ccekConstraint` entry by `entry.constraint.kind` (`ConstraintKind` ∈ `ckIk, ckTransform, ckPath, ckPhysics`, model.nim:32–36) to either the existing path apply or a NEW `applyRuntimeIk` that calls the EXISTING solver in `runtime-nim/src/bony/constraints/ik.nim` (`solveOneBoneIk` 84–102, `solveTwoBoneIk` 105–152, `solveChainIk` 155–242). The dispatch + gate + `applyRuntimeIk` must land with the combined builder so the apply loop never hands IK entries to the path apply.

- **Solver I/O mapping and write-back (the part most likely to be gotten wrong — follow contract §3–§5 exactly, do not paraphrase from the path integration).**
  - **Geometry (contract §4).** `BoneData` stores only `name`/`parent`/`local` (model.nim:51–54) — no world position or length. FK-compose REST-pose world origins for the chain. `points` = each constrained bone's rest-pose world origin in chain order `++ [target bone's REST-pose world origin]` ⇒ `#points = #bones + 1`; `lengths` = distances between consecutive points ⇒ `#lengths = #bones`. The target bone's **REST** position closes the chain (supplies the leaf length); the target bone's **CURRENT** world position is the goal the solver reaches toward. `origin` = first bone's rest-pose world origin.
  - **Per-case feed (contract §4).** Select by `bones.len`: **1** → `solveOneBoneIk(origin, length, currentRotation, target, mix)` with `length = |target_rest − bone0_rest|`; **2** → `solveTwoBoneIk(origin, parentLength, childLength, parentRotation, childRotation, target, bendSign, mix)` with `parentLength = |bone1_rest − bone0_rest|`, `childLength = |target_rest − bone1_rest|`, `bendSign = if bendPositive: 1.0 else: -1.0`; **≥3** → `solveChainIk(points, lengths, target, mix)`. The `currentRotation`/`parentRotation`/`childRotation` inputs are the bones' CURRENT WORLD rotations (derive from the `worlds` array), not locals.
  - **`mix` is applied ONCE — inside the solver.** All three solvers already lerp by `mix` internally (`storedMix` at ik.nim:97, 140–141, 234–238). Pass `mix` to the solver and write the solver's already-mixed result directly. Do NOT additionally blend current-vs-solved in `applyRuntimeIk` — that applies mix² and fails the `mix=0.5` success criterion.
  - **Output convention differs per solver — do NOT use one uniform absolute→local conversion.** `solveOneBoneIk.rotation` and `solveChainIk.rotations` are ABSOLUTE world angles in degrees (ik.nim:29); `solveTwoBoneIk` returns `parentRotation` absolute but `childRotation` RELATIVE to the parent (ik.nim:144 composes `parentRotation + childRotation`). Convert each solved angle to the target bone's LOCAL rotation using the parent-inverse machinery the path integration uses (`parentWorld` transform.nim:270, `inverseAffine(parentWorld)` :279, local write :308–320, re-world via `worldForBone` :323) — but handle the two-bone child as relative-to-parent, not absolute.
  - **Chain write-back is sequential FK, not the one-bone path.** `applyRuntimePathConstraint` writes exactly one bone against a single already-computed `parentWorld`. For an IK chain the constrained bones are mutually parent→child and ALL are in the descriptor `writes`, so none are pre-computed by the cache. `applyRuntimeIk` must: FK-compose each chain bone's world from `bone[0]`'s EXTERNAL parent forward, capture all origins BEFORE mutating, then write each bone's local rotation in chain order, re-worlding each bone before it serves as the next bone's `parentWorld`. This sequential handling is the hardest part of the bead.
  - **Degenerate cases stay NON-FATAL** (unreachable target, zero-length segment) by relying on the solver's existing fallbacks (ik.nim:175–200). Do NOT add new error paths.

- **`runtimeEvaluable*(ik: IkConstraintData): bool`** in `runtime-nim/src/bony/model.nim` (sibling of `runtimeEvaluable*(path: PathConstraintData)` at model.nim:405 — the IK overload does NOT exist yet). NOTE the path precedent takes ONLY the constraint and checks flags (`hasPosition or hasTranslateMix or hasRotateMix`); it has no skeleton access. Bone/target name resolution therefore CANNOT live in a constraint-only predicate. Resolve this explicitly in the plan-to-bead step by choosing ONE: (a) `runtimeEvaluable*(ik): bool` checks only the constraint-local condition `mix > 0` (and `bones.len >= 1`), with the bone/target-resolution guard moved to the apply path (where `boneIndexes()`/`readBoneIndexes` already raise/skip on unknown bones); OR (b) a differently-signed `runtimeEvaluable*(ik, boneIndex: Table[string,int]): bool` that also checks resolution, accepting divergence from the path signature. Prefer (a) — it mirrors the path predicate's purity and keeps the entry-gate scan cheap. Whichever is chosen, keep degenerate IK non-fatal per the solver fallbacks above.

- **Dart model-load parity** spans TWO Dart files, not just the model. The Dart runtime currently PARSES M5 constraints but defers evaluation (`runtime-dart/test/m5_constraint_test.dart` header note). Match that posture:
  - `runtime-dart/lib/src/model.dart`: add an `IkConstraintData` class (sibling of `PathConstraintData` at model.dart:65) and a `SkeletonData.ikConstraints` field (sibling of `SkeletonData.paths` at model.dart:132).
  - `runtime-dart/lib/src/loader.dart`: this is where round-trip actually happens (`_parsePath` at loader.dart:57 parses JSON `PathConstraintData`; paths are re-emitted at loader.dart:~592). Add: JSON `ikConstraints`-array parse, `.bnb` `ikConstraint` (typeKey 4002) decode INCLUDING the varuint string-table `bones` bytes, allow `ikConstraints` through any Dart known-keys validation, and re-emit on save. A `model.dart`-only change leaves the loader rejecting or dropping IK and CANNOT satisfy the "round-trip through the Dart loader without error" criterion.
  - Dart EVALUATION parity is explicitly OUT OF SCOPE and tracked separately; record that in a `m5_constraint_test.dart` comment matching the existing path-constraint deferral note.

### Links to Relevant Documentation
- Step-1 freeze (source of truth for keys/schema): `.agents/notes/ik-format-freeze.md`, `docs/ik-constraint-format-contract.md`
- Frozen registry constants (generated): `runtime-nim/src/bony/generated/wire.nim` (ikConstraint=4002, bones=4014/bytes, mix=4015/f32, bendPositive=4016/bool)
- IK solver (already implemented — integrate, do NOT rewrite the math): `runtime-nim/src/bony/constraints/ik.nim`
- Path-constraint runtime precedent: `runtime-nim/src/bony/transform.nim`, `runtime-nim/src/bony/constraints/path_constraints.nim`, `runtime-nim/src/bony/constraints/update_cache.nim`
- JSON loader/emitter: `runtime-nim/src/bony/jsonio.nim`; Binary loader/emitter: `runtime-nim/src/bony/binary/semantic.nim`
- Dart model: `runtime-dart/lib/src/model.dart`
- Contracts: `docs/constraint-total-order.md`, `docs/transform-composition-contract.md`, `docs/float-math-contract.md` (cross-runtime tolerance `1e-4`), `docs/binary-canonicalization.md`, `docs/binary-toc-skip-semantics.md`
- Clean-room posture: `docs/CLEANROOM.md`, `docs/PROVENANCE.md`; capability categories only: `docs/comparable-feature-set.md`
- Original step-2 prompt: `.agents/big-change-prompts/06-runtime-ik-constraint-evaluation.md`

### Affected Areas
All paths verified to exist on `main` 2026-06-29. Reservation surfaces for parallel agents are noted.

- `runtime-nim/src/bony/model.nim` — foundation bead, and it is NOT just one proc. `IkConstraintData` (:90–98) and `SkeletonData.ikConstraints` (:199) exist but their fields are UNEXPORTED and there is NO `ikConstraints*` collection accessor (contrast `proc paths*` at :437) and no field accessors (`name`/`bones`/`target`/`order`/`mix`/`bendPositive`/`hasMix`/`hasBendPositive`). Per `docs/ik-constraint-format-contract.md` §7, step-2 code reads these via accessors. The foundation bead MUST add: the chosen `runtimeEvaluable*(ik...)` overload (see Description for the signature decision), `proc ikConstraints*(data: SkeletonData)`, and the per-field accessors. Every downstream bead that reads `data.ikConstraints[...]` or IK fields (jsonio, semantic, transform, round-trip) DEPENDS on this bead — without the accessors they cannot compile alone.
- `runtime-nim/src/bony/jsonio.nim` — ADD IK load + emit; ADD `ikConstraints` to `validateKnownKeys` list at :311. High-value seam; reserve whole file.
- `runtime-nim/src/bony/binary/semantic.nim` — ADD IK type/property key constants (from wire.nim) + encode loop (mirror :876) + decode; gate emit on non-empty `ikConstraints` for byte-stability. Reserve whole file.
- `runtime-nim/src/bony/constraints/update_cache.nim` — ADD combined path+IK descriptor builder feeding `buildConstraintUpdateCache` (:107). Do not duplicate the generic sort.
- `runtime-nim/src/bony/transform.nim` — SWAP :136 to the combined builder; ADD kind-dispatch in the apply loop (:142–156) + new `applyRuntimeIk` reusing parent-inverse write-back (:270–323). Highest-risk file (path constraints must stay green). Reserve whole file; couple with the update_cache change in one bead.
- `runtime-nim/src/bony/constraints/ik.nim` — READ-ONLY. Integrate; do NOT modify solver math/constants (`fabrikIterations=8`, `fabrikTolerance=1e-4`, `quantizeF32`). File a separate bead if a genuine solver bug is found.
- `runtime-nim/tests/` — ADD focused IK eval tests (new `test_ik_eval.nim` or extend `test_smoke.nim`) and a temporary local round-trip fixture (NOT committed as a conformance fixture — those arrive in step 3). Existing tests: `test_smoke.nim`, `test_bnb_byte_stability.nim`, `test_bnb_fuzz.nim`, `test_json_bnb_json_idempotency.nim`.
- `runtime-dart/lib/src/model.dart` — ADD `IkConstraintData` class (sibling :65) + `SkeletonData.ikConstraints` (sibling :132). Independent of Nim work (parallelizable). `runtime-dart/test/m5_constraint_test.dart` — ADD a deferral note comment.
- `runtime-dart/lib/src/loader.dart` — ADD JSON `ikConstraints` parse (sibling of `_parsePath` :57), `.bnb` `ikConstraint` decode (typeKey 4002, string-table `bones` bytes), known-keys allowance, and re-emit on save (sibling of path emit ~:592). REQUIRED for the Dart round-trip criterion — do this in the SAME bead as the model.dart change.
- `cli/bony_cli.nim` — READ-ONLY for this slice EXCEPT a tracked follow-up: `applySequencePose` reconstructs `SkeletonData` via `skeletonData(...)` OMITTING `ikConstraints` (~:1431–1439), so the `play`/pose CLI path silently DROPS IK. This is out of scope for round-trip (which uses `toBonyBnb`/`toBonyJson` directly) but is a real latent data-loss → file a FOLLOW-UP bead, do not fold into this slice. The `json-to-bnb`/`bnb-to-json` subcommands (used for round-trip verification) are unaffected.
- CI gates (READ-ONLY, must stay green): `scripts/ci/round_trip_run.py` (covers only committed `conformance/assets/*` — see Success Criteria), `scripts/ci/conformance_run.py`, `scripts/ci/suite_run.py`; repo gate `make test` (codegen `--check`, codegen unit tests, `nim check`).
- NOT touched: `codegen/`, `spec/` (registry + defaults landed in step 1; `validate_sources()` already satisfied). Touching them would re-open the frozen format — out of scope.

### Success Criteria
- Nim loads IK constraints from `.bony` JSON AND from `.bnb`, evaluates them in the world-transform pass via the existing `ik.nim` solver, and writes results through the SAME path the path-constraint integration uses.
- New Nim unit tests in `runtime-nim/tests/` cover: one-bone reach, two-bone bend (BOTH `bendSign`), an N-bone chain, `mix` interpolation at `0` / `0.5` / `1`, and a degenerate unreachable target. Assert deterministic output within `1e-4`.
- IK constraints survive `json → bnb → json` AND `bnb → json → bnb` byte-stable round-trips. NOTE: `scripts/ci/round_trip_run.py` only operates on committed `conformance/assets/*.bony` + `conformance/assets/bnb/*_rig.bnb` and will NOT exercise IK in step 2 (those fixtures arrive in step 3) — it only proves pre-existing fixtures still pass. The step-2 IK round-trip MUST be proven by a TEMPORARY local fixture run directly through the CLI subcommands (`bony json-to-bnb` then `bony bnb-to-json` then back, diffing bytes), not via `round_trip_run.py`. State this explicitly in the round-trip bead so coverage is not falsely implied.
- `runtime-dart/lib/src/model.dart` loads `IkConstraintData` and existing Dart tests still pass; Dart evaluation parity is explicitly deferred and noted in a test comment, matching the existing path-constraint deferral note.
- No new format keys or schema fields beyond what step 1 froze.
- Per-bead invariant (ralph merge-to-main model): EVERY merged bead independently keeps `make test` green AND keeps `.bnb` byte-stable for all existing fixtures (no IK fixtures exist yet). Verification block that must pass at completion:

```bash
nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim
cd runtime-nim && nimble test && cd ..
nim c --path:runtime-nim/src -o:/tmp/bony_bin cli/bony_cli.nim
python3 scripts/ci/round_trip_run.py --bony-bin /tmp/bony_bin
python3 scripts/ci/conformance_run.py --bony-bin /tmp/bony_bin
python3 scripts/ci/suite_run.py --bony-bin /tmp/bony_bin
cd runtime-dart && dart test && cd ..
```

### Constraints
- Preserve clean-room posture: do NOT inspect or derive from DragonBones, Spine, Rive, Live2D, or Lottie runtime/importer source, generated definitions, wire layouts, type/property keys, or copied docs prose. Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope. Keep Spine importer work blocked for human/legal review.
- Do NOT modify the IK solver math in `ik.nim`; integrate it. If a genuine solver bug is found, file a separate bead rather than expanding this slice.
- IK ONLY — do not wire transform or physics constraints.
- Dart scope is model loading/parity only; NO Dart IK evaluation.
- Keep `.bnb` byte-stability and all existing conformance gates green at every merge.
- No new format keys/schema beyond step-1 freeze. If the format proves insufficient, STOP and amend step 1, do not invent keys here.
- Keep the slice small enough for one meaningful implementation session; each bead ≤ ~750 LOC changed.

---

## Your Task

Analyze this codebase change and create a comprehensive **Beads task graph** using the `bd` CLI. Beads provides dependency-aware, conflict-free task management for multi-agent execution.

Before creating the task graph, you MUST first analyze the affected areas of the codebase:

1. Check `docs/specs/` and `docs/adr/` for existing architectural decisions (none present; contracts live in `docs/*.md` — see Links).
2. Examine the directory/module structure of the affected areas listed above.
3. Identify key interfaces, APIs, and integration points that must be preserved (the path-constraint precedent; the frozen registry in `generated/wire.nim`; `ik.nim` solver signatures).
4. Note existing test patterns and coverage in the affected areas (`runtime-nim/tests/test_*.nim`, `runtime-dart/test/m5_constraint_test.dart`).
5. Assess risk areas where changes could break existing functionality (`transform.nim` apply loop; `.bnb` byte-stability; `validateKnownKeys`).

Use your analysis to make each bead specific — reference actual file paths, module names, and patterns observed above.

Then generate a shell script that creates the complete task graph.

**IMPORTANT: Your ONLY deliverable is a bash shell script with `bd create` commands. Not an implementation plan. Not a design document. Not a code review. A runnable `.sh` script.**

### Sequencing guidance for the bead graph (honor under ralph's merge-to-main-per-bead model)

Each bead, when merged alone to main, must keep `make test` green and `.bnb`/JSON goldens byte-stable. A safe ordering:

1. **Analysis/grounding** (p0, `analysis`): confirm frozen keys in `generated/wire.nim`, the `bones` string-table packing + per-case solver feed in `docs/ik-constraint-format-contract.md` §2–§5, the path precedent in `transform.nim`/`update_cache.nim`, and the `ik.nim` solver output conventions (1-bone/chain absolute vs 2-bone child relative). No code. (Optional but cheap.)
2. **Model foundation: accessors + `runtimeEvaluable*(ik)`** in `model.nim` (p0, `impl`): export the IK field accessors + `ikConstraints*(data)` collection accessor AND the chosen `runtimeEvaluable` overload (prefer the constraint-only `mix>0` form — see Description). Standalone, compiles green. EVERY downstream Nim reader depends on this. Depends on (1).
3. **JSON load/emit + `validateKnownKeys` + empty-key omission** in `jsonio.nim` (p0, `impl`): green because no existing fixture carries `ikConstraints` AND the emitter omits the key when empty. Depends on (2).
4. **Binary encode/decode + key constants** in `semantic.nim` (p0, `impl`): `bones` packed as varuint string-table indices (mirror `blendAxes`); emit gated on non-empty `ikConstraints` with a PINNED stream position (confirm vs `binary-canonicalization`) ⇒ existing fixtures byte-identical. Depends on (2). Parallel with (3) (different file).
5. **Core eval** (p0, `impl`): the combined update-cache builder + transform entry-gate extension (`hasRuntimePaths` → also fire on runtime-evaluable IK) + kind-dispatch + `applyRuntimeIk` (per-case solver feed, mix-applied-once, two-bone-relative + sequential chain FK write-back). Depends on (2). Parallel with (3)/(4) (in-memory eval needs neither serializer). **MAY be split** into 5a (combined builder in `update_cache.nim`, green standalone since existing rigs emit no IK descriptors) → 5b (`transform.nim` gate+dispatch+`applyRuntimeIk`, depends on 5a) if the single bead exceeds ~750 LOC; both halves stay green.
6. **Nim IK eval unit tests** (p0, `testing`): 1-bone reach / 2-bone bend BOTH `bendSign` / N-bone chain / mix 0,0.5,1 / degenerate unreachable, within `1e-4`. Construct skeletons in-memory via `ikConstraintData(...)` + bone ctors (no committed fixtures needed). Depends on (5)/(5b).
7. **Round-trip validation via CLI on a temporary local fixture** (p1, `testing`): build a temp IK `.bony`, run `bony json-to-bnb`→`bnb-to-json`→`json-to-bnb` and diff bytes both directions. Explicitly NOT covered by `round_trip_run.py` until step 3 — state that. Depends on (3) and (4).
8. **Dart model-load + loader parity + deferral note** (p1, `impl`): `IkConstraintData` in `model.dart` AND JSON+`.bnb` parse/emit + known-keys in `loader.dart` (the round-trip seam). Independent of Nim; depends on (1) only. Parallel with all Nim work.
9. **Follow-up: IK dropped on the `play`/pose CLI path** (p2, `impl`, FILED but may be deferred): `applySequencePose` reconstructs `SkeletonData` without `ikConstraints` (`bony_cli.nim:~1431`). Separate from this slice's round-trip scope; file so it is not lost.
10. **Full verification gate** (p0, `testing`): run the Success-Criteria command block; conformance/suite/round-trip green. Depends on (5)/(5b),(3),(4),(6),(7),(8).
11. **Docs/handoff note** (p2, `docs`): note runtime IK eval is live and Dart eval is deferred to a later slice. Depends on (10).

Do NOT add codegen/spec/registry beads — the format is frozen in step 1 and `validate_sources()` is already satisfied; editing them re-opens the freeze.

---

## Output Format

Generate a shell script that creates the full task graph. The script should:

1. **Initialize Beads** (if not already initialized)
2. **Create one parent epic** (`bd create -t epic`) representing the whole change, capturing its ID into `$EPIC`
3. **Create all task beads** with appropriate priorities, each parented to the epic via `--parent "$EPIC"`
4. **Establish dependencies** between task beads (ordering edges only — never to or from the epic)
5. **Add labels** for phase grouping (child beads inherit the epic's labels unless `--no-inherit-labels`)

### Example Output

```bash
#!/bin/bash
# Project: bony
# Change: Runtime IK constraint evaluation (Nim eval + Dart parity) — step 2 of 3
# Generated: 2026-06-29

set -e

# Initialize beads if needed
if [ ! -d ".beads" ]; then
    bd init
fi

echo "Creating change beads..."

# ========================================
# Parent epic — every task below is parented to it (--parent "$EPIC").
# The epic is an organizational rollup: it is NEVER given a blocking dep
# (no `bd dep add` to or from it) and is never dispatched as work itself.
# ========================================

EPIC=$(bd create "Epic: Refactor auth middleware for compliance" -t epic -p 0 --label epic --silent)
bd update "$EPIC" --status in_progress   # rollup, not dispatchable work — keep it out of `bd ready`

# ========================================
# Phase 1: Analysis & Preparation
# ========================================

ANALYZE_CURRENT=$(bd create "Analyze current auth middleware implementation in src/auth/ — document all session token storage patterns and consumer dependencies" -p 0 --label analysis --parent "$EPIC" --silent)

IDENTIFY_DEPS=$(bd create "Map all modules importing from src/auth/ and catalog their usage patterns" -p 0 --label analysis --parent "$EPIC" --silent)

CHAR_TESTS=$(bd create "Add characterization tests capturing current auth middleware behavior before refactoring" -p 0 --label prep --parent "$EPIC" --silent)
bd dep add $CHAR_TESTS $ANALYZE_CURRENT

# ========================================
# Phase 2: Core Implementation
# ========================================

IMPL_NEW_STORAGE=$(bd create "Implement compliant session token storage in src/auth/session.ts replacing in-memory store" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $IMPL_NEW_STORAGE $CHAR_TESTS
bd dep add $IMPL_NEW_STORAGE $IDENTIFY_DEPS

IMPL_MIGRATION=$(bd create "Create migration script for existing session data to new storage format" -p 1 --label impl --parent "$EPIC" --silent)
bd dep add $IMPL_MIGRATION $IMPL_NEW_STORAGE

UPDATE_CONSUMERS=$(bd create "Update all consumer modules to use new auth middleware API surface" -p 1 --label impl --parent "$EPIC" --silent)
bd dep add $UPDATE_CONSUMERS $IMPL_NEW_STORAGE

# ========================================
# Phase 3: Testing & Validation
# ========================================

UNIT_TESTS=$(bd create "Add unit tests for new session storage implementation" -p 1 --label testing --parent "$EPIC" --silent)
bd dep add $UNIT_TESTS $IMPL_NEW_STORAGE

INTEGRATION_TESTS=$(bd create "Add integration tests for auth flow end-to-end with new middleware" -p 1 --label testing --parent "$EPIC" --silent)
bd dep add $INTEGRATION_TESTS $UPDATE_CONSUMERS

REGRESSION_CHECK=$(bd create "Run full regression suite and verify characterization tests still pass" -p 0 --label testing --parent "$EPIC" --silent)
bd dep add $REGRESSION_CHECK $INTEGRATION_TESTS
bd dep add $REGRESSION_CHECK $UNIT_TESTS

# ========================================
# Phase 4: Cleanup & Documentation
# ========================================

UPDATE_DOCS=$(bd create "Update auth middleware documentation and API reference" -p 2 --label docs --parent "$EPIC" --silent)
bd dep add $UPDATE_DOCS $REGRESSION_CHECK

CLEANUP=$(bd create "Remove deprecated session storage code and update changelog" -p 3 --label cleanup --parent "$EPIC" --silent)
bd dep add $CLEANUP $REGRESSION_CHECK

echo ""
echo "Bead graph created! View with:"
echo "  bd show $EPIC          # The parent epic and its rollup"
echo "  bd children $EPIC      # All task beads under the epic"
echo "  bd ready              # List unblocked tasks (the epic itself is not work)"
```

---

## Bead Creation Guidelines

### Epic / Hierarchy (REQUIRED)
- Create exactly **one parent epic** for the whole change: `EPIC=$(bd create "Epic: <change summary>" -t epic -p 0 --label epic --silent)`.
- Parent **every** task bead to it: add `--parent "$EPIC"` to every `bd create` (children inherit the epic's labels unless you pass `--no-inherit-labels`).
- The epic is a **rollup, not work**: never `bd dep add` to or from it. Membership is `--parent`; `bd dep add` is reserved for real ordering edges *between task beads*.
- **Keep the epic out of `bd ready`** by marking it active right after creation: `bd update "$EPIC" --status in_progress`.
- An epic must have **≥ 2 children** to be meaningful.
- A single top-level epic is the default and is sufficient for this change.

### Priority Levels
- `-p 0` = Critical (blocking other work, or high-risk changes needing early validation)
- `-p 1` = High (important implementation work)
- `-p 2` = Medium (standard work)
- `-p 3` = Low (cleanup, nice-to-haves)

### Labels (Phase Grouping)
`analysis`, `prep`, `impl`, `testing`, `migration`, `docs`, `cleanup`.

### Dependency Rules
1. Never create cycles
2. Analysis tasks should complete before implementation begins
3. Use `bd dep add CHILD PARENT` (child depends on parent completing first)
4. Parallel work should share a common ancestor, not depend on each other
5. `bd dep add` is for ordering edges **between task beads only** — never attach a task to the epic (that is `--parent`), and never add a blocking edge to or from the epic

### Task Granularity
- Each bead ≤ **750 lines of code changed**
- Tasks should be atomic enough for one agent to complete without coordination
- If a task requires multiple file areas, consider splitting by file area (EXCEPT the update-cache + transform dispatch, which must land together to stay green)

---

## File Reservation Planning

```bash
# Reservation notes (add as bead descriptions):
# model.nim    — FOUNDATION: field accessors + ikConstraints* + runtimeEvaluable overload; everything depends on it
# jsonio.nim   — whole file; load/emit (omit empty key) + validateKnownKeys:311 (high-value seam)
# semantic.nim — whole file; IK key constants + string-table bones pack + encode loop (mirror :876) + decode (byte-stability critical)
# transform.nim + update_cache.nim — core eval; couple (or 5a builder → 5b transform); entry-gate + dispatch + sequential chain FK
# ik.nim       — READ-ONLY, do not edit (solver math frozen; mix applied inside, outputs differ per solver)
# model.dart + loader.dart — Dart parity in ONE bead; loader.dart is the round-trip seam; parallelizable with Nim work
# bony_cli.nim — READ-ONLY except a FILED follow-up (applySequencePose drops ikConstraints ~:1431)
```

---

## Verification Steps

After generating the script:

1. **Run it**: `chmod +x setup-beads.sh && ./setup-beads.sh`
2. **Check the rollup**: `bd children "$EPIC"` lists every task; `bd dep tree` shows them under the epic with no orphan tasks
3. **Check ready work**: `bd ready` shows the analysis/grounding task(s) and NOT the epic
4. **Check no cycles**: `bd dep cycles` reports none

---

## Completeness Checklist

- [ ] Single parent epic (`-t epic`); every task parented via `--parent "$EPIC"`; no orphans; no blocking dep to/from the epic
- [ ] Analysis/grounding of frozen keys + string-table `bones` packing + per-case solver feed + solver output conventions
- [ ] Model foundation bead: field accessors + `ikConstraints*` + chosen `runtimeEvaluable*(ik)` overload (every Nim reader depends on it)
- [ ] JSON load/emit + `validateKnownKeys` + empty-key omission bead
- [ ] Binary encode/decode + key constants bead (string-table `bones`, byte-stability gated + pinned stream position)
- [ ] Core eval bead: combined builder + entry-gate extension + dispatch + `applyRuntimeIk` (mix-once, two-bone-relative, sequential chain FK) — optionally 5a builder → 5b transform
- [ ] Nim IK eval unit tests bead (1/2± /N bone, mix 0/0.5/1, degenerate, 1e-4, in-memory skeletons)
- [ ] Round-trip validation bead via CLI on temp fixture (NOT round_trip_run.py; note step-3 coverage)
- [ ] Dart bead: `IkConstraintData` in model.dart + IK parse/emit in loader.dart + deferral note
- [ ] Follow-up bead filed: IK dropped on `play`/pose CLI path (`applySequencePose`)
- [ ] Full verification gate bead (Success-Criteria command block)
- [ ] Docs/handoff note bead
- [ ] Clear dependency chains, no cycles, no codegen/spec/registry beads
