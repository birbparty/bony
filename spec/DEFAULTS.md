# Default Table Source

`spec/defaults.yml` is the canonical default-table source consumed by codegen,
schema generation, JSON loaders, and binary loaders.

The registry owns keys and backing types. The default table owns default values
and default-omission behavior. Runtime code must not hand-maintain a second
copy of defaults once codegen exists.

## Responsibilities

Default tables define:

- The value synthesized when a known field is absent.
- Whether canonical JSON and binary writers omit the field when it equals the
  default. Omission is controlled by `omitWhenDefault`; default-valued fields
  with `omitWhenDefault: false` are still emitted.
- The equality rule used for default comparison when the backing type needs a
  special rule.

Default tables do not define:

- Property keys or backing types.
- Object membership.
- Schema property order.
- Runtime behavior beyond absent-field application.

## Cross-Checks

Codegen and CI freshness checks must validate:

- Every default object id exists in `registry/wire.yml`.
- Every default property id exists in `registry/wire.yml`.
- Every default property belongs to the object it is listed under.
- Every default value is valid for the property's backing type and generated
  JSON schema type.
- `omitWhenDefault: true` is paired with `applyOnLoad: true`.
- Every registered object property appears exactly once in either
  `objectDefaults.properties` or object-scoped `requiredProperties`.
- Every equality override is one of the closed `equalityModes` ids in
  `spec/defaults.yml`.

## Mutation Rules

Allowed changes:

- Add defaults for a newly registered object/property in the same feature bead.
- Add documentation to an existing default without changing behavior.
- Change a default only when the same bead updates dependent conformance
  fixtures and migration notes.

Forbidden changes:

- Changing defaults as a drive-by edit in an unrelated bead.
- Defining defaults for properties not declared in the registry.
- Defining a default whose value cannot be represented by the property's backing
  type.
- Omitting a field on serialize without applying the same default on load.
- Leaving a registered object property out of both the default table and the
  object-scoped required/no-default table.

## Canonicalization Relationship

`docs/json-canonicalization.md` and `docs/binary-canonicalization.md` both rely
on this source:

- Loaders apply defaults before semantic validation that depends on field
  values.
- Canonical writers omit fields whose loaded semantic value equals the default
  only when the default entry sets `omitWhenDefault: true`.
- F32-backed defaults compare after f32 quantization at the file boundary.

Because the current registry has no concrete object/property entries yet,
`spec/defaults.yml` starts with an empty `objectDefaults` list. Later registry
feature beads must append defaults in the same change that introduces the
corresponding properties.
