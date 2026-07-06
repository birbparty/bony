# Registry Key Ranges

This file documents the positive `varuint` key bands reserved by the
machine-readable `keyRanges` map in `registry/wire.yml`. Key `0` remains
reserved forever in both key spaces.

The ranges below apply independently to `typeKeys` and `propertyKeys`. For
example, M1 may use type key `1` and property key `1`; those are different key
spaces and do not collide.

Every bead that appends entries to `registry/wire.yml` must choose keys only
from its owning milestone band and cite the bead that introduced the entry.
Use uppercase milestone tokens `M1` through `M10` in registry entries. Changing
these bands after registry entries exist is a format-governance change and must
be done by a dedicated registry bead.

| Milestone | Inclusive Key Range | Intended Scope |
| --- | ---: | --- |
| M1 | `1..999` | SkeletonData model, `.bony` JSON I/O, default tables |
| M2 | `1000..1999` | World transforms, region attachments, draw order |
| M3 | `2000..2999` | Animations, timelines, curves, mixing |
| M4 | `3000..3999` | Meshes, weights, skins, deform timelines, clipping |
| M5 | `4000..4999` | IK, transform, path, and physics constraints |
| M6 | `5000..5999` | `.bnb` binary containers, ToC-backed objects, atlas embedding |
| M7 | `6000..6999` | Warp and rotation deformers, keyforms, parameter blending |
| M8 | `7000..7999` | State machines, layers, transitions, listeners |
| M9 | `8000..8999` | Tooling/importer metadata that becomes first-class format data |
| M10 | `9000..9999` | Consolidation, compatibility fixtures, reserved v1 completion hooks |

## Parallel Registry Edits

Milestone implementation beads may edit the registry in parallel once they use
disjoint bands from this table, but disjoint key bands are not a replacement
for coordination on shared files. Before editing `registry/**`, a bead must
reserve the shared registry surface with the active coordination mechanism, keep
that reservation through regeneration and rebase, and release it only after the
branch is merged or abandoned. There is still no bead dependency edge that
serializes disjoint milestone registry edits.

A bead that needs keys from more than one milestone must either split the
registry edit or explicitly document the cross-band exception in both the bead
description and the affected registry entry `doc` fields.

Documented exception: bead `bony-i4x6.1` uses M5 property keys `4027..4032`
for the `skinRequired` activation surface even when those properties are valid
on `bone` and `skin` records. The keys belong to M5 because the surface gates
M5 constraint families as one atomic format/load slice; the registry entry docs
and provenance records describe the cross-band use.

Downstream registry-editing beads should include this exact instruction in
their description:

```text
Use only your allocated range from registry/key-ranges.md.
```

## Future Ranges

Keys `10000..19999` are reserved for post-v1 extensions that are still governed
by this repository. Keys `20000+` are intentionally unassigned until a future
versioning contract defines extension and vendor allocation policy.
