# Unit tests for CLI-private pose procs (bony-me5.10). Included with
# -d:bonyExcludeMain so the CLI's main() entry point does not run.
#
# Regression guard: applySequencePose reconstructs SkeletonData when a sequence
# attachment is applied on the play/pose path. It previously rebuilt the skeleton
# via skeletonData(...) while omitting ikConstraints, silently dropping IK. This
# proves IK survives both the reconstruction path and the empty-sequence
# early-return path.

include "../../cli/bony_cli.nim"

proc ikRigWithSequenceSlot(): SkeletonData =
  ## root -> b0 (IK bone) and root -> goal (IK target); slot s0 carries a
  ## sequence-able "frame0" attachment backed by a matching region.
  skeletonData(
    skeletonHeader("ikseq", "0.2.0"),
    @[
      boneData("root", ""),
      boneData("b0", "root"),
      boneData("goal", "root"),
    ],
    slots = @[slotData("s0", "b0", "frame0")],
    regions = @[regionAttachment("frame0", 1.0, 1.0)],
    ikConstraints = @[ikConstraintData("ik", "goal", @["b0"])],
  )

block preservesIkThroughSequenceReconstruction:
  let data = ikRigWithSequenceSlot()
  # A non-empty sequence forces the reconstruction branch (not the early return).
  let pose = MixedPose(
    sequences: @[MixedSequence(target: "s0", value: SampledSequence(index: 0'u32))])
  doAssert pose.sequences.len == 1
  let posed = applySequencePose(data, pose)
  doAssert posed.ikConstraints.len == 1, "applySequencePose dropped ikConstraints"
  doAssert posed.ikConstraints[0].name == "ik"
  doAssert posed.ikConstraints[0].target == "goal"
  doAssert posed.ikConstraints[0].bones == @["b0"]

block preservesIkOnEmptySequenceEarlyReturn:
  let data = ikRigWithSequenceSlot()
  let posed = applySequencePose(data, MixedPose())
  doAssert posed.ikConstraints.len == 1

block preservesIkThroughRenderablePose:
  # applyRenderablePose = applyPose then applySequencePose; IK must survive both.
  let data = ikRigWithSequenceSlot()
  let pose = MixedPose(
    sequences: @[MixedSequence(target: "s0", value: SampledSequence(index: 0'u32))])
  let posed = data.applyRenderablePose(pose)
  doAssert posed.ikConstraints.len == 1, "applyRenderablePose dropped ikConstraints"

echo "cli pose IK-preservation tests passed"
