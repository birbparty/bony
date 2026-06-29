---
name: next-milestone
description: Plan the next tangible bony milestone. Use when asked what to build next, to choose the next milestone, to compare bony against DragonBones/Spine/Rive capability gaps, or to generate grounded /big-change prompts for a clean-room bony increment.
---

# /next-milestone - Plan the next bony increment

`bony` is a clean-room 2D skeletal and deform animation format with a Nim
reference runtime, Dart runtime, CLI tooling, registry-backed `.bony`/`.bnb`
formats, and shared conformance assets. This skill surveys the current
implementation frontier, compares it to capability-level comparable research,
then writes source-grounded `/big-change` prompts for the chosen milestone.

## Project Facts

- Binding implementation sources are `docs/`, `spec/`, `registry/`,
  generated code from `codegen/`, conformance assets, and the local spec at
  `/Users/punk1290/Downloads/bony-2d-skeletal-format-spec.md`.
- Clean-room policy is binding. Read `docs/CLEANROOM.md`,
  `docs/PROVENANCE.md`, and `docs/comparable-feature-set.md` before using any
  DragonBones, Spine, or Rive comparison.
- Comparable research is capability context only. Do not fetch or inspect
  runtime source, importer source, generated definitions, exact wire layouts,
  type/property keys, schema structure, copied docs prose, or source snippets
  from DragonBones, Spine, Rive, Live2D, or Lottie.
- Rive importer work is out of scope. Spine importer work is blocked for
  human/legal review. DragonBones and Lottie importer work must follow their
  existing design notes and importer-boundary rules.
- Beads (`bd`) is the task tracker. Use it for issue state; do not create
  markdown task lists for tracking.

## Procedure

### 1. Assess The Frontier

Read the current local state before deciding anything:

```bash
bd ready
bd list --status=open
sed -n '1,220p' README.md
sed -n '1,260p' docs/README.md
sed -n '1,260p' conformance/README.md
sed -n '1,220p' registry/README.md
find spec registry codegen runtime-nim runtime-dart cli conformance docs -maxdepth 2 -type f | sort
```

Then inspect any files directly relevant to active/open beads and recent review
history under `.agents/reviews/`. Classify the frontier with evidence:

- `Implementation frontier`: the next unfinished runtime, conformance, CLI,
  schema/registry, importer, docs, or validation increment already implied by
  local state.
- `Comparable gap`: a capability category in `docs/comparable-feature-set.md`
  that `bony` lacks, under-specifies, or has not declared as a non-goal.
- `Useful independent work`: a leverage point such as conformance hardening,
  docs clarity, test coverage, importer safety, validation, performance
  scaffolding, or developer workflow that is not just cleanup.

State the current frontier in one sentence. If no implementation frontier
exists, say that explicitly and still present the comparable-gap and useful
recommendations.

### 2. Present Exactly Three Candidates

While `bony` has a current implementation frontier, present exactly three
candidate recommendations:

1. **Frontier recommendation** - the best next increment from current code,
   docs, conformance, and beads state.
2. **Comparable-gap recommendation** - the best next increment suggested by
   clean-room DragonBones/Spine/Rive capability comparison.
3. **Useful recommendation** - whatever seems most important or useful even if
   it is not the strict frontier or comparable gap.

For each candidate include:

- Name.
- Category: `frontier`, `comparable-gap`, or `useful`.
- Why now.
- Affected areas or owning directories.
- Clean-room risk: `low`, `medium`, `blocked`, or `out-of-scope`.
- Scope guard: what is intentionally not included.

Mark one overall default recommendation. If the user asks you to proceed
without choosing, pick that default and say why. If the candidate touches
blocked or out-of-scope work, recommend a design/legal/research bead instead of
implementation.

### 3. Map The Chosen Milestone

For the chosen milestone, map the concrete artifacts before writing prompts:

- Contracts: `docs/`, `spec/`, `registry/`, generated code, or versioning.
- Implementations: `runtime-nim/`, `runtime-dart/`, `cli/`, `codegen/`.
- Conformance: `conformance/assets/`, `conformance/goldens/`,
  `conformance/scripts/`, and `scripts/ci/`.
- Importers: only under an existing project-owned design note and clean-room
  provenance entry.
- Beads: parent issue, child issues, and dependency order.

Ground every path, symbol, command, and acceptance criterion by reading source
before naming it in a prompt. If a path does not exist, say the prompt should
create it. If a symbol cannot be confirmed, do not name it.

### 4. Write `/big-change` Prompt Files

Create prompt files under:

```text
.agents/big-change-prompts/
```

Name them in run order:

```text
NN-<area>-<slug>.md
```

Most milestones should be one prompt. Split only when there is a real order
such as contract first, implementation second, conformance third.

Use this template:

```markdown
# /big-change prompt - <area> (<milestone>)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step N of M**. <dependency note, or "Can run independently.">
> **Candidate category:** <frontier|comparable-gap|useful>.

---

/big-change <one concise sentence describing the milestone>

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Local source/artifacts: <exact paths confirmed in the repo>
- Beads: <exact bead ids, if already filed>

**Success Criteria**
- <measurable bullets tied to exact docs, source files, generated files,
  fixtures, tests, or CI gates>
- <include verification commands, or "docs/plan only; no code verification required">

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Keep the slice small enough for one meaningful implementation session.
- <milestone-specific scope guards>
```

### 5. Review The Prompts

For substantial milestones, run two independent read-only reviews when
subagents are available and user/tool policy permits delegation. Give each
reviewer:

- Prompt file paths.
- `docs/CLEANROOM.md`.
- `docs/PROVENANCE.md`.
- `docs/comparable-feature-set.md`.
- The local files cited by the prompt.

Ask reviewers to verify path/symbol accuracy, clean-room compliance,
technical soundness, scope size, dependency order, and whether an implementer
would have to guess. Require verdicts: `APPROVE`, `APPROVE-WITH-FIXES`, or
`NEEDS-WORK`.

Verify every reviewer claim locally before changing prompts. If subagents are
not available or delegation is not permitted, run a direct self-review and
state that the independent review step was skipped.

### 6. File Beads Issues

If Beads is initialized, file:

- One parent issue for the chosen milestone.
- Child issues for ordered prompt slices when there is more than one prompt.
- Dependencies matching the prompt run order.

Run `bd` commands serially because the embedded Dolt backend can lock under
concurrent access. If Beads is not initialized, do not initialize it silently.

### 7. Report Back

End with:

- Current frontier sentence.
- Chosen milestone.
- Prompt file paths.
- Review verdicts and fixes applied, or why review was skipped.
- Beads IDs.
- Run order and the clean-room seams that force it.

## Guardrails

- Do not use comparable docs as implementation source. They justify categories,
  not algorithms, identifiers, or wire shapes.
- Do not refresh third-party docs unless the user asks for current research or
  the plan depends on current vendor capabilities. If refreshing is necessary,
  use official docs only and update `docs/comparable-feature-set.md` plus
  `docs/PROVENANCE.md`.
- Do not add node/format/runtime features outside the chosen milestone.
- Do not plan Rive importer implementation. Treat it as out of scope.
- Do not plan Spine importer implementation except as a human/legal review
  follow-up.
