## Supported runtime path for applying deformers to built draw batches.
##
## `transform.buildDrawBatches` intentionally returns **undeformed** draw
## batches (skinning/region build only); deformer application is a separate,
## explicit stage so callers that thread physics-adjusted worlds or state-machine
## slot states can order the pipeline themselves. Historically that stage lived
## only inside the CLI (`cli/bony_cli.nim`), so a downstream **library** consumer
## calling `buildDrawBatches` directly got silently undeformed geometry with no
## exported helper to finish the job.
##
## This module exports that stage so both the CLI and any library consumer share
## one implementation:
##
## - `effectiveDeformers` resolves each `DeformerRecord` into a concrete
##   `Deformer` for the given parameter samples (sampling keyform-blended warp
##   control points where present; passing other deformers through unchanged).
## - `applyDeformersToDrawBatches` applies a resolved deformer list to a
##   draw-batch list, mutating only vertex x/y (u/v and color are preserved) and
##   preserving vertex counts.
## - `deformDrawBatches` is the one-call convenience: resolve then apply.
##
## `buildDrawBatches` is deliberately **not** changed, so the CLI golden path
## (build → deform) applies deformers exactly once.

import bony/model
import bony/deform/deformers
import bony/deform/keyforms
import bony/deform/parameters
import bony/mesh/skinning

export deformers, keyforms

proc effectiveDeformers*(data: SkeletonData;
                         samples: openArray[ParameterSample]): seq[Deformer] =
  ## Resolve `data.deformers` (records) into concrete `Deformer`s for `samples`.
  ## A warp deformer carrying a keyform blend has its control points sampled from
  ## the blend at `samples`; every other deformer passes through unchanged.
  for rec in data.deformers:
    if rec.keyformBlend.axes.len > 0 and rec.keyformBlend.keyforms.len > 0 and
        rec.deformer.kind == warpDeformerKind:
      let pts = sampleKeyformPoints(rec.keyformBlend, samples)
      result.add warpDeformer(
        rec.deformer.id,
        warpLattice(
          rec.deformer.warp.rows, rec.deformer.warp.cols,
          rec.deformer.warp.minX, rec.deformer.warp.minY,
          rec.deformer.warp.maxX, rec.deformer.warp.maxY,
          pts,
        ),
        rec.deformer.parent,
        rec.deformer.order,
      )
    else:
      result.add rec.deformer


proc defaultParameterSamples*(data: SkeletonData): seq[ParameterSample] =
  ## The setup-pose parameter samples (each axis at its default), matching the
  ## samples the CLI uses for a `--t 0` render.
  for param in data.parameters:
    result.add defaultParameterSample(param)


proc applyDeformersToDrawBatches*(batches: seq[DrawBatch];
                                  deformers: openArray[Deformer]): seq[DrawBatch] =
  ## Apply a resolved deformer list to `batches`, returning new batches whose
  ## vertex positions are deformed. Only x/y are updated (u/v and r/g/b/a are
  ## preserved), and the vertex count of every batch is preserved. An empty
  ## `deformers` list returns `batches` unchanged.
  if deformers.len == 0:
    return batches
  result = batches
  for batchIndex, batch in batches:
    var skinned: seq[SkinnedMeshVertex]
    for v in batch.vertices:
      skinned.add SkinnedMeshVertex(x: v.x, y: v.y, u: v.u, v: v.v)
    let deformed = applyDeformers(skinned, deformers)
    doAssert deformed.len == batch.vertices.len,
      "applyDeformers must preserve vertex count"
    for vertIndex, dv in deformed:
      result[batchIndex].vertices[vertIndex].x = dv.x
      result[batchIndex].vertices[vertIndex].y = dv.y


proc deformDrawBatches*(data: SkeletonData; batches: seq[DrawBatch];
                        samples: openArray[ParameterSample]): seq[DrawBatch] =
  ## One-call supported path for library consumers: resolve `data`'s deformers at
  ## `samples` and apply them to `batches`. Equivalent to
  ## `applyDeformersToDrawBatches(batches, effectiveDeformers(data, samples))`.
  applyDeformersToDrawBatches(batches, effectiveDeformers(data, samples))


proc deformDrawBatches*(data: SkeletonData;
                        batches: seq[DrawBatch]): seq[DrawBatch] =
  ## Convenience overload using the setup-pose (default) parameter samples.
  deformDrawBatches(data, batches, defaultParameterSamples(data))
