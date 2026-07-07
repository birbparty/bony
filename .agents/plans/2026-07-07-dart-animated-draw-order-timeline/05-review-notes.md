# Review Notes

Two independent review passes are required before this plan is final.

## Reviewer A

Concerns:

1. Cross-runtime scope was contradictory: the plan declared format/schema/
   registry/conformance success while allowing Dart-only implementation with a
   Nim follow-up.
2. `.bnb` canonicalization needed explicit Nim writer/object-order support or a
   ban on `.bnb` fixtures until that lands.
3. Dynamic clipping invariants were underspecified after sampled slot
   reordering.
4. Zero-offset behavior was undecided.
5. Schema/codegen needed to call out the singular nested JSON shape so
   `drawOrderTimeline` does not become an unintended root collection.

## Reviewer B

Concerns:

1. Visual direction was underspecified: index `0` needed to be defined as
   drawn first/backmost, with larger indices later/frontmost.
2. Zero-offset handling needed one binding rule.
3. `.bnb` decoder work depended on shared validation from JSON/model work.
4. Before-first-key semantics conflicted with setup/rest fixture expectations.

## Applied Revisions

- Made Nim model/load/write/eval and CLI conversion preservation required
  before format/conformance completion; `.bnb` fixtures are forbidden until
  Nim canonical conversion is green.
- Defined visual index direction.
- Changed before-first-key sampling to setup order.
- Chose reader-tolerant zero-offset normalization with canonical omission.
- Added dynamic clipping validity requirements.
- Added `BNB_LOAD` dependency on `JSON_LOAD` and explicit Nim reference beads.
- Added schema/codegen acceptance for singular nested `drawOrderTimeline`.
