# Versioning

This document records the versioning relationship between the four independently
versionable artifacts in this monorepo:

1. **On-disk binary format** (`.bnb` header `major.minor`)
2. **Nim runtime package** (`runtime-nim/bony.nimble`)
3. **Dart runtime package** (`runtime-dart/pubspec.yaml`)
4. **Spec document** (this spec + JSON Schema in `spec/`)

## Version axes

### Binary format (major.minor)

The `.bnb` header encodes the format version as a single varuint packed as
`(major << 16) | minor`. Current constants: `bnbMajorVersion = 0`, `bnbMinorVersion = 1`.

Compatibility contract:
- **Same major** — a reader MUST accept and load the file. Unknown object types
  and unknown property keys are skipped via the ToC (see
  `docs/binary-toc-skip-semantics.md`). This enables non-breaking extension
  within a major version.
- **Different major** — a reader MUST reject the file with `schemaViolation`.
  A major-version bump signals a breaking change that invalidates the skip-safe
  assumption.

Minor increments within a major version are forward-compatible: a 0.2 reader can
load a 0.1 file, and a 0.1 reader can load a 0.2 file (skipping the new content).

### Nim and Dart package versions (semver)

Both package versions track the binary format version: `major.minor.patch` where
`major` and `minor` match the binary format, and `patch` is reserved for
runtime-only bug fixes that don't touch the wire format.

Current: `0.1.0` in both packages.

Pre-1.0 package APIs may still remove unsupported experimental helpers when they
are not part of the serialized format contract. In particular,
`runtime-nim/src/bony/mesh/sequences.nim` and its root-exported
`AttachmentSequence` frame-name helpers were removed during the 0.1.x line
because the wire/schema surface only defines slot sequence timeline keyframes;
there is no attachment-sequence `count`/`start`/`digits`/`setupIndex` feature to
preserve.

### Generated registry metadata (`bonyRegistryVersion`)

Both runtimes expose `bonyRegistryVersion`, generated from
`registry/wire.yml`'s top-level `registryVersion`. This is a compact signal for
the generated registry/default metadata compiled into a runtime:

- stable type and property keys;
- object-to-property ordering;
- backing types;
- required-property metadata;
- default and omit-when-default metadata used by loaders and canonical writers;
- ordinal enum contracts.

Increment `registry/wire.yml:registryVersion` in the same commit as any source
metadata change that can alter generated runtime metadata or canonical emission,
including:

- adding, deprecating, or changing a `registry/wire.yml` type key, property key,
  object property list, backing type, or ordinal enum;
- changing `spec/defaults.yml` defaults, equality modes, `omitWhenDefault`,
  `applyOnLoad`, or required-property rows;
- changing codegen in a way that changes the generated registry metadata
  contract exposed to consumers.

Do not increment it for changes that leave the generated registry metadata
contract unchanged, such as:

- runtime algorithm bug fixes;
- docs, tests, examples, or conformance fixture additions;
- adding package APIs that only consume existing metadata, such as a canonical
  JSON writer over the current model;
- regenerating files with byte-identical generated metadata.

Downstream consumers should treat `bonyRegistryVersion` as a schema/metadata
compatibility signal, not as a package version. A consumer may record the
registry version it was built and tested against; if a newly pinned runtime has
a different value, rerun import/export and persistence compatibility tests
before adopting it. A higher registry version usually means the consumer may
need to understand new fields or new default/omission behavior. The same
registry version does not guarantee identical runtime behavior or API surface:
use the package version and, for path/git dependencies during the pre-1.0 line,
the exact commit SHA to track bug fixes and API additions.

### Spec document version

The spec document version is a human-facing label that tracks the format version.
It is recorded as `major.minor` (no patch suffix). The JSON Schema headers
(`spec/bony.schema.json` and `spec/bony-wire.schema.json`) say they are
generated from `registry/wire.yml` and `spec/defaults.yml`; neither schema has an
independent version, and both are always regenerated fresh from those sources.

## What v1.0 ships as

| Artifact | v1.0 value |
|---|---|
| Binary format | major=1, minor=0 → packed integer `0x10000` (65536), wire bytes `[0x80, 0x80, 0x04]` |
| Nim package | `1.0.0` |
| Dart package | `1.0.0` |
| Spec document | `1.0` |

The binary format bump from 0.x to 1.0 is a **breaking change**: 0.x readers
will reject 1.0 files (major mismatch), and 1.0 readers will reject 0.x files.
The cut to 1.0 is gated on the format being stable enough to commit to backwards
compatibility within the 1.x major.

## Key registry rules

The property key registry (`registry/wire.yml`) is **append-only**:

- Key 0 is the reserved object-stream terminator. It MUST NOT be assigned to any
  object type or property.
- Retired keys (removed features) MUST NOT be reused. They remain in `wire.yml`
  with `status: deprecated` so future authors know to skip those key numbers.
- New keys are allocated from the milestone's pre-reserved band (see
  `registry/key-ranges.md`). Keys within a band need not be contiguous, but
  MUST NOT cross into another milestone's band.

These rules ensure that a reader encountering an unknown key can safely skip it
via the ToC payload-length record without misinterpreting retired data as a new
extension.
