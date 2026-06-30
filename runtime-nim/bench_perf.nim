## Non-gating perf harness for the bony Nim reference runtime.
##
## Measures wall-clock time for the key SkeletonData/SkeletonInstance
## operations defined in §7.1 of the bony spec.  Budgets are DEFERRED —
## this binary always exits 0 and never blocks CI.
##
## Deferred budget targets (not enforced — record actuals, set budgets at M10):
##   loadBonyJson (m5 rig):        < 10 ms
##   loadKnownBonyBnb (m5 rig):    < 2 ms
##   newSkeletonInstance:          < 200 µs
##   computeWorldTransforms:       < 100 µs
##   buildConstraintUpdateCache:   < 50 µs
##   buildRuntimeConstraintUpdateCache: < 50 µs
##   buildDrawBatches:             < 200 µs
##
## Usage (from runtime-nim/ directory):
##   nim c -r --path:src bench_perf.nim [-- <conformance-assets-dir>]

import std/[algorithm, monotimes, os, strformat, strutils, times]

import bony


const
  WARMUP_ROUNDS = 50
  MEASURE_ROUNDS = 500

type
  TimingSample = seq[int64]

proc percentile(s: TimingSample; pct: float): int64 =
  let idx = int(float(s.len - 1) * pct / 100.0 + 0.5)
  s[min(idx, s.high)]

proc measureNs(body: proc()): TimingSample =
  for _ in 0 ..< WARMUP_ROUNDS:
    body()
  result = newSeq[int64](MEASURE_ROUNDS)
  for i in 0 ..< MEASURE_ROUNDS:
    let t0 = getMonoTime()
    body()
    let t1 = getMonoTime()
    result[i] = (t1 - t0).inNanoseconds
  result.sort()

proc fmtNs(ns: int64): string =
  if ns < 1_000:
    &"{ns} ns"
  elif ns < 1_000_000:
    let us = float64(ns) / 1_000.0
    &"{us:.1f} µs"
  else:
    let ms = float64(ns) / 1_000_000.0
    &"{ms:.2f} ms"

proc printRow(label, rig: string; s: TimingSample) =
  let p50 = fmtNs(percentile(s, 50))
  let p95 = fmtNs(percentile(s, 95))
  let p99 = fmtNs(percentile(s, 99))
  let mn  = fmtNs(s[0])
  let mx  = fmtNs(s[s.high])
  echo &"  {label:<40} {rig:<8} {p50:>10} {p95:>10} {p99:>10} {mn:>10} {mx:>10}"

proc printHeader() =
  let h1 = "operation"
  let h2 = "rig"
  let h3 = "p50"; let h4 = "p95"; let h5 = "p99"
  let h6 = "min"; let h7 = "max"
  echo &"  {h1:<40} {h2:<8} {h3:>10} {h4:>10} {h5:>10} {h6:>10} {h7:>10}"
  echo "  " & "-".repeat(98)

type
  RigAsset = object
    name: string
    jsonText: string
    bnbBytes: seq[byte]


proc main() =
  let assetsDir =
    if paramCount() > 0: paramStr(1)
    else: parentDir(currentSourcePath()) / ".." / "conformance" / "assets"

  echo "bony perf harness (non-gating)"
  echo &"  assets: {assetsDir}"
  echo &"  warmup: {WARMUP_ROUNDS}  measure: {MEASURE_ROUNDS}"
  echo ""

  var rigs: seq[RigAsset]
  for name in ["m1_rig", "m2_rig", "m3_rig", "m4_rig", "m5_rig"]:
    let jsonPath = assetsDir / name & ".bony"
    let bnbPath  = assetsDir / "bnb" / name & ".bnb"
    if not fileExists(jsonPath) or not fileExists(bnbPath):
      echo &"  [skip] {name}: asset pair not found"
      continue
    rigs.add RigAsset(
      name:     name,
      jsonText: readFile(jsonPath),
      bnbBytes: cast[seq[byte]](readFile(bnbPath)),
    )

  if rigs.len == 0:
    echo "no conformance assets found — nothing to measure"
    return

  echo "=== load timings ==="
  printHeader()
  for i in 0 ..< rigs.len:
    let jsonText = rigs[i].jsonText
    let t = measureNs(proc() = discard loadBonyJson(jsonText))
    printRow("loadBonyJson", rigs[i].name, t)
  for i in 0 ..< rigs.len:
    let bnbBytes = rigs[i].bnbBytes
    let t = measureNs(proc() = discard loadKnownBonyBnb(bnbBytes))
    printRow("loadKnownBonyBnb", rigs[i].name, t)
  for i in 0 ..< rigs.len:
    let dataRef = new SkeletonData
    dataRef[] = loadBonyJson(rigs[i].jsonText)
    let t = measureNs(proc() = discard newSkeletonInstance(dataRef))
    printRow("newSkeletonInstance", rigs[i].name, t)

  echo ""
  echo "=== per-frame pipeline timings (using pre-loaded SkeletonData) ==="
  printHeader()

  for i in 0 ..< rigs.len:
    let data = loadBonyJson(rigs[i].jsonText)
    let rigName = rigs[i].name

    let t1 = measureNs(proc() = discard computeWorldTransforms(data))
    printRow("computeWorldTransforms", rigName, t1)

    # Core cache algorithm only — descriptors pre-built so only O(bones+constraints)
    # ordering logic is measured.  For rigs without path constraints pathDescs is
    # empty; the row still confirms the zero-constraint baseline.
    var pathDescs: seq[ConstraintCacheDescriptor]
    for pcIndex, pc in data.paths:
      pathDescs.add constraintCacheDescriptor(ckPath, pc.order, pcIndex, [pc.bone])
    let t2 = measureNs(proc() = discard buildConstraintUpdateCache(data.bones, pathDescs))
    printRow("buildConstraintUpdateCache", rigName, t2)

    # Full path including descriptor construction — measures end-to-end cost.
    # When path constraints are the only constraint type (pre-M10), this row and
    # the one above use an identical descriptor set; the delta reveals descriptor
    # build overhead.
    let t3 = measureNs(proc() = discard buildRuntimeConstraintUpdateCache(data))
    printRow("buildRuntimeConstraintUpdateCache", rigName, t3)

    let t4 = measureNs(proc() = discard buildDrawBatches(data))
    printRow("buildDrawBatches", rigName, t4)

  echo ""
  echo "note: budgets DEFERRED — no gate, no enforcement"


main()
