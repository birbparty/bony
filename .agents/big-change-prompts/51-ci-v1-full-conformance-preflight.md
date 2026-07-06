# /big-change prompt - CI (v1 full conformance preflight)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 4 of 4**. Depends on steps 1-3 if they are accepted
> as v1 follow-ups; otherwise update the dependency set before running.
> **Candidate category:** useful.

---

/big-change Promote the repo-level verification path into a non-vacuous v1 full conformance preflight gate across generated code, Nim, conformance scripts, and Dart.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

The repository has several quality gates, but they are split across `make test`,
`scripts/ci/suite_run.py`, and `cd runtime-dart && dart test`. M10 is explicitly
about conformance suite and second-language runtime validation, so the repo
needs one documented preflight path that cannot pass vacuously and that future
agents can run before shipping.

Create or update the v1 full preflight gate so it runs, in a deterministic
order:

- generated-code freshness and Python codegen tests;
- Nim compile and runtime unit tests from `Makefile`;
- numeric, image, input-script, and round-trip conformance via
  `scripts/ci/suite_run.py`;
- Dart runtime tests via `cd runtime-dart && dart test`;
- license/provenance check if it is already wired and locally runnable.

Keep optional dependency behavior explicit. If image checks require Pillow or
input-script schema checks require jsonschema, the gate may provide a documented
skip flag for local development, but the default v1 preflight must fail on
vacuous coverage and must make skipped dependency-gated checks visible.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Local binding spec roadmap: /Users/punk1290/Downloads/bony-2d-skeletal-format-spec.md
- Repo gate: Makefile
- Conformance runners: scripts/ci/suite_run.py,
  scripts/ci/conformance_run.py, scripts/ci/image_diff_check.py,
  scripts/ci/input_script_run.py, scripts/ci/round_trip_run.py,
  scripts/ci/schema_validate_assets.py
- Runtime tests: runtime-nim/tests/, runtime-dart/test/
- Docs to update: README.md, docs/README.md, conformance/README.md
- Beads: bony-dqsn; dependencies bony-ohs0, bony-2j7z, bony-0vu9

**Success Criteria**
- A single documented command or small script exists for the full v1 preflight.
  It may be a `Makefile` target or a script under `scripts/ci/`, but it must be
  discoverable from `README.md` or `docs/README.md`.
- The full preflight runs generated-code checks, Python codegen tests, Nim
  tests, suite conformance gates, and Dart tests.
- The gate fails if no numeric goldens, no image goldens, no input scripts, or
  no Dart tests are actually checked.
- Dependency-gated skips are explicit in output and documented; CI/default
  profile should not silently skip the image or schema gates.
- Existing faster developer gates remain available; this prompt should not make
  every edit require the full preflight unless the docs say so explicitly.
- `conformance/README.md` documents which command is the v1 full conformance
  gate and which command is the fast local gate.
- Verification passes by running the new full preflight, or by running the
  command with documented local skip flags and recording exactly which external
  dependencies were unavailable.

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not add new format/runtime features in this preflight slice.
- Do not remove existing fast gates; add or document the full gate alongside
  them.
- Keep the gate Linux-friendly and non-interactive.
