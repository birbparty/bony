## M4 flipbook sequence attachment frame resolution.

import std/strutils

import bony/anim/timelines
import bony/model

type
  AttachmentSequence* = object
    count*: uint32
    start*: uint32
    digits*: uint32
    setupIndex*: uint32


proc attachmentSequence*(count: uint32; start = 0'u32; digits = 0'u32; setupIndex = 0'u32): AttachmentSequence =
  if count == 0:
    raise newBonyLoadError(schemaViolation, "sequence count must be positive")
  if setupIndex >= count:
    raise newBonyLoadError(schemaViolation, "sequence setupIndex must be within count")
  AttachmentSequence(count: count, start: start, digits: digits, setupIndex: setupIndex)


proc validateAttachmentSequence(sequence: AttachmentSequence) =
  if sequence.count == 0:
    raise newBonyLoadError(schemaViolation, "sequence count must be positive")
  if sequence.setupIndex >= sequence.count:
    raise newBonyLoadError(schemaViolation, "sequence setupIndex must be within count")


proc sequenceFrameName*(basePath: string; sequence: AttachmentSequence; index: uint32): string =
  validateAttachmentSequence(sequence)
  if basePath.len == 0:
    raise newBonyLoadError(schemaViolation, "sequence base path must not be empty")
  if index >= sequence.count:
    raise newBonyLoadError(schemaViolation, "sequence frame index must be within count")
  let frame = sequence.start + index
  let suffix =
    if sequence.digits == 0:
      $frame
    else:
      align($frame, int(sequence.digits), '0')
  basePath & suffix


proc setupSequenceFrameName*(basePath: string; sequence: AttachmentSequence): string =
  sequenceFrameName(basePath, sequence, sequence.setupIndex)


proc sampledSequenceFrameName*(basePath: string; sequence: AttachmentSequence; sample: SampledSequence): string =
  sequenceFrameName(basePath, sequence, sample.index)
