# /big-change prompt - Dart parity (pointer helper listeners)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 3 of 3**. Depends on step 2
> (`37-runtime-nim-pointer-helper-listeners.md`) because Dart must match the
> Nim reference M21 goldens.
> **Candidate category:** frontier.

---

/big-change Port pointer helper listener dispatch to Dart and match the M21 conformance goldens.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

After the Nim reference implementation and M21 conformance assets land, port
pointer helper listener behavior to the Dart runtime. Match the project-owned
contract and Nim goldens; do not add new serialized listener semantics.

Build exactly this milestone:

1. Update Dart model, loader, and state-machine runtime code as needed to match
   `docs/pointer-helper-listener-contract.md` and the Nim behavior:
   - `runtime-dart/lib/src/model.dart`
   - `runtime-dart/lib/src/loader.dart`
   - `runtime-dart/lib/src/statemachine.dart`
   - `runtime-dart/lib/src/transform.dart` if helper world transforms belong
     there by existing local patterns.
2. Implement Dart helper hit testing for point and bounding-box attachments with
   the same tolerance and event ordering as Nim.
3. Add Dart tests for:
   - pointer listener JSON and `.bnb` loading;
   - malformed pointer listener validation;
   - point-radius and bounding-box hit tests;
   - pointer listener input mutation before transition evaluation;
   - M21 `.bony` and `.bnb` conformance goldens.
4. Extend the existing Dart conformance pattern in
   `runtime-dart/test/m10_conformance_test.dart` or add a focused
   `runtime-dart/test/m21_pointer_listener_test.dart`, matching the structure of
   `runtime-dart/test/m5_ik_story_test.dart`,
   `runtime-dart/test/m5_physics_story_test.dart`,
   `runtime-dart/test/m18_deform_story_test.dart`, and
   `runtime-dart/test/m19_event_story_test.dart`.
5. Keep the serialized contract stable. If a defect in the contract is found,
   stop and update step 1's contract/docs/registry/defaults/generated surfaces
   rather than creating Dart-only behavior.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Pointer listener contract: docs/pointer-helper-listener-contract.md
- Helper geometry contract: docs/helper-geometry-attachment-contract.md
- Float math/tolerance: docs/float-math-contract.md
- M21 conformance docs/assets from step 2:
  conformance/README.md,
  conformance/assets/m21_pointer_listener_rig.bony,
  conformance/assets/bnb/m21_pointer_listener_rig.bnb,
  conformance/scripts/m21_pointer_listener_story.json,
  conformance/goldens/
- Dart seams: runtime-dart/lib/src/model.dart,
  runtime-dart/lib/src/loader.dart,
  runtime-dart/lib/src/statemachine.dart,
  runtime-dart/lib/src/transform.dart,
  runtime-dart/test/m10_conformance_test.dart,
  runtime-dart/test/m5_ik_story_test.dart,
  runtime-dart/test/m5_physics_story_test.dart,
  runtime-dart/test/m18_deform_story_test.dart,
  runtime-dart/test/m19_event_story_test.dart
- Beads: parent bony-1umq; child bony-lrfz; depends on bony-3moo

**Success Criteria**
- Dart loads the same pointer listener JSON/BNB surface as Nim and rejects the
  same malformed contract cases where Dart has matching validation coverage.
- Dart pointer listener runtime dispatch mutates inputs before transition
  evaluation and emits listener events matching Nim semantics.
- Dart helper hit tests match Nim within `docs/float-math-contract.md`
  tolerance.
- Dart matches every M21 `.bony` and `.bnb` golden within `1e-4`.
- Verification passes:
  - `python3 codegen/generate.py --check`
  - `python3 -m unittest discover -s codegen -p 'test_*.py'`
  - `make test`
  - `cd runtime-dart && dart test`

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not add new pointer listener kinds, fields, registry keys, or input-script
  semantics beyond the contract from step 1 and Nim reference from step 2.
- Do not add visible debug rendering for helper attachments.
- Keep the slice small enough for one meaningful implementation session.
