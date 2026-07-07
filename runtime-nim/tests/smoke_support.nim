{.push warning[UnusedImport]: off.}

# Topic split tests `include` this file instead of importing it so they can reuse
# the original smoke-test private fixture procs without exporting test-only API.
import std/[json, math, os, osproc, sequtils, strutils, tables]

import bddy
import bony
import pixie
import testutil

{.pop.}

let repoRoot = parentDir(parentDir(parentDir(absolutePath(currentSourcePath()))))


proc repoPath(parts: varargs[string]): string =
  result = repoRoot
  for part in parts:
    result = result / part

proc ikWorldRot(w: Affine2): float64 =
  ## World rotation (degrees) of an affine basis, for IK integration assertions.
  radToDeg(arctan2(w.b, w.a))
proc pointDistance(a, b: IkPoint): float64 =
  hypot(b.x - a.x, b.y - a.y)

proc transformFixture(childMode: TransformMode; parentScaleX = 2.0; parentScaleY = 3.0): SkeletonData =
  let (inheritRotation, inheritScale, inheritReflection) =
    case childMode
    of normal: (true, true, true)
    of onlyTranslation: (false, false, false)
    of noRotationOrReflection: (false, true, false)
    of noScale: (true, false, true)
    of noScaleOrReflection: (true, false, false)
  skeletonData(
    skeletonHeader("demo", "0.1.0"),
    @[
      boneData("root", "", localTransform(scaleX = parentScaleX, scaleY = parentScaleY)),
      boneData(
        "child",
        "root",
        localTransform(
          x = 1.0,
          inheritRotation = inheritRotation,
          inheritScale = inheritScale,
          inheritReflection = inheritReflection,
          transformMode = childMode,
        ),
      ),
    ],
  )

proc animationFixture(): SkeletonData =
  skeletonData(
    skeletonHeader("demo", "0.1.0"),
    @[boneData("root", "")],
    @[slotData("body", "root", "")],
    @[regionAttachment("idle", 1.0, 1.0), regionAttachment("wave", 1.0, 1.0)],
  )

# Completeness-guard scaffolding (bony-bna8): a skeleton + clip that drive ALL
# nine MixedPose channels at once, so a channel silently dropped by any pose
# aggregator (overlayPose / addWeightedPose / blendedPose) shows up as an empty
# field. `body` carries the slot channels (attachment swap + colors + sequence);
# `meshSlot` shows the `cloth` mesh a deform timeline animates; `root` carries the
# bone channels (scalar + vector + inherit).
proc allChannelFixture(): SkeletonData =
  let prelim = skeletonData(skeletonHeader("demo", "0.1.0"), @[boneData("root", "")])
  let cloth = unweightedMeshAttachment(
    prelim,
    "cloth",
    @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(1.0, 1.0)],
    @[0'u16, 1'u16, 2'u16],
    @[unweightedMeshVertex(0.0, 0.0), unweightedMeshVertex(1.0, 0.0), unweightedMeshVertex(1.0, 1.0)],
  )
  skeletonData(
    skeletonHeader("demo", "0.1.0"),
    @[boneData("root", "")],
    @[slotData("body", "root", ""), slotData("meshSlot", "root", "cloth")],
    @[regionAttachment("idle", 1.0, 1.0), regionAttachment("wave", 1.0, 1.0)],
    meshAttachments = @[cloth],
  )

proc allChannelClip(data: SkeletonData; name: string): AnimationClip =
  animationClip(
    data,
    name,
    @[
      boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 30.0)]),
      boneVectorTimeline("root", translateTimeline, @[vector2Keyframe(0.0, 4.0, 5.0)]),
      boneInheritTimeline("root", @[inheritKeyframe(0.0)]),
    ],
    @[
      slotAttachmentTimeline("body", @[attachmentKeyframe(0.0, "idle")]),
      slotColorTimeline("body", rgbaTimeline, @[colorKeyframe(0.0, colorRgba(0.5, 0.25, 0.75, 1.0))]),
      slotColor2Timeline("body", @[color2Keyframe(0.0, colorRgba2(colorRgba(1.0, 1.0, 1.0, 1.0), 0.1, 0.2, 0.3))]),
      slotSequenceTimeline("body", @[sequenceKeyframe(0.0, 2'u32, 0.1, sequenceLoop)]),
    ],
    drawOrderTimeline = drawOrderTimeline(@[
      drawOrderKeyframe(0.0, @[drawOrderOffset("body", 1), drawOrderOffset("meshSlot", -1)]),
    ]),
    deformTimelines = @[deformTimeline("default", "meshSlot", data.meshAttachments[0],
      @[deformKeyframe(0.0, 0'u32, @[meshDelta(2.0, 0.0)])])],
  )

# Names of any MixedPose seq channel that came back empty. Iterates via fieldPairs
# so a future channel #10 is covered automatically: if it is added to MixedPose but
# not threaded through an aggregator (or not driven by allChannelClip), it lands
# here and the guard tests fail loudly instead of silently rendering nothing.
proc droppedChannels(pose: MixedPose): seq[string] =
  for name, field in pose.fieldPairs:
    if field.len == 0:
      result.add name

proc triMeshFixture(name: string): MeshAttachment =
  ## A minimal valid unweighted triangle mesh (3 uvs, 3 vertices, one triangle),
  ## assembled with the raw ctor so it is validated only via validateSkeletonData.
  meshAttachmentData(
    name,
    @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(0.0, 1.0)],
    @[0'u16, 1'u16, 2'u16],
    @[unweightedMeshVertex(0.0, 0.0), unweightedMeshVertex(1.0, 0.0), unweightedMeshVertex(0.0, 1.0)],
    false,
  )

proc clipEvalRig(clipVertices, untilSlot: string): string =
  ## A rig on an identity-transform root bone: a clip slot (own slot), a covered
  ## region slot, and a region slot past `untilSlot`. Region "body" is a 2x2 quad
  ## centered at the origin (corners at +/-1).
  """
{
  "skeleton": {"name": "cliprig", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "regions": [{"name": "body", "width": 2, "height": 2}],
  "clippingAttachments": [
    {"name": "mask", "vertices": [""" & clipVertices & """], "untilSlot": """" & untilSlot & """"}
  ],
  "slots": [
    {"name": "clipSlot", "bone": "root", "attachment": "mask"},
    {"name": "coveredSlot", "bone": "root", "attachment": "body"},
    {"name": "afterSlot", "bone": "root", "attachment": "body"}
  ]
}
"""

proc batchFor(batches: seq[DrawBatch]; slotName: string): DrawBatch =
  for batch in batches:
    if batch.slot == slotName:
      return batch
  raise newException(ValueError, "no batch for slot " & slotName)

proc rotationRig(): SkeletonData =
  skeletonData(
    skeletonHeader("deform-api", "0.1.0"),
    @[boneData("root", "")],
    @[slotData("body", "root", "quad")],
    @[regionAttachment("quad", 2.0, 2.0)],
    deformers = @[
      DeformerRecord(
        deformer: rotationDeformerNode(
          "rot", rotationDeformer(0.0, 0.0, 90.0), order = 0'u32),
        keyformBlend: KeyformBlend(),
      ),
    ],
  )
