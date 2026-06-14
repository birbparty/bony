## bony Nim reference runtime package root.

import bony/generated/wire
import bony/anim/mixer
import bony/anim/timelines
import bony/binary/framing
import bony/binary/semantic
import bony/constraints/ik
import bony/constraints/transform_constraints
import bony/deform/deformers
import bony/deform/keyforms
import bony/deform/parameter_timelines
import bony/deform/parameters
import bony/mesh/attachments
import bony/mesh/clipping
import bony/mesh/deform
import bony/mesh/sequences
import bony/mesh/skinning
import bony/model
import bony/jsonio
import bony/statemachine/core
import bony/transform

export attachments
export framing
export semantic
export ik
export transform_constraints
export clipping
export deformers
export keyforms
export parameter_timelines
export parameters
export deform
export sequences
export skinning
export mixer
export timelines
export jsonio
export model
export core
export transform
export wire

const bonyVersion* = "0.1.0"
