## File-level Bony asset aggregate.

import bony/anim/timelines
import bony/model
import bony/statemachine/core

type
  BonyAsset* = object
    skeleton*: SkeletonData
    animations*: seq[AnimationClip]
    stateMachines*: seq[StateMachine]


proc bonyAsset*(
  skeleton: SkeletonData;
  animations: openArray[AnimationClip] = [];
  stateMachines: openArray[StateMachine] = [];
): BonyAsset =
  BonyAsset(skeleton: skeleton, animations: @animations, stateMachines: @stateMachines)
