# registry

`registry/` is the append-only declarative source of truth for the `.bnb`
binary wire format. Codegen, binary readers/writers, JSON schema generation,
and registry/default-table sync checks must read this directory rather than
copying key tables into runtime code.

The canonical machine-readable registry file is `registry/wire.yml`.

## Key Spaces

The binary format has two independent `varuint` key spaces:

- `typeKeys`: object kinds in the flat object stream.
- `propertyKeys`: fields inside objects.

Key `0` is reserved forever in both spaces:

- Type key `0` is the object stream EOF marker.
- Property key `0` terminates an object's property list.

No object type or property may ever be assigned key `0`.

## Property Backing Types

Property keys are global because the `.bnb` table of contents maps
`propertyKey -> backingType` so old readers can skip unknown properties without
knowing the object type. A property key therefore has exactly one backing type
for the lifetime of the format.

If two object types expose a field with the same JSON spelling but different
wire backing requirements, they must use different property keys.

## Append-Only Rules

Allowed changes:

- Append a new type key with an unused positive key in the owning milestone's
  reserved range once `registry/key-ranges.md` exists.
- Append a new property key with an unused positive key in the owning
  milestone's reserved range once `registry/key-ranges.md` exists.
- Add a new object/property use that references an existing compatible property
  key.
- Add documentation, owner milestone, or references that do not change wire
  meaning.

Forbidden changes:

- Renumbering an existing key.
- Reusing a removed key.
- Changing an existing property's backing type.
- Changing an existing type or property identifier.
- Deleting a key that shipped in any committed format version.
- Reassigning a property key to an incompatible semantic.

Deprecated keys remain in `wire.yml` with `status: deprecated`. They are still
reserved and must remain decodable.

## Relationship To Schema And Defaults

`spec/bony.schema.json` is generated from, or cross-checked against, the
registry plus the default-table source. It is not an independent source of
truth for keys.

Default tables own default values and default-omission decisions. The registry
owns field identity, wire key, backing type, object membership, and stable
ordering for generated schema properties.

## Review Checklist

Any bead that edits `registry/**` must verify:

- New keys are positive and unused in their key space.
- New keys fall inside the owning milestone's reserved range once
  `registry/key-ranges.md` exists.
- Key `0` remains reserved.
- Property backing types are unchanged for existing keys.
- Object property lists reference declared property keys.
- New type/property entries cite the milestone or feature bead that owns them.
- Codegen and schema freshness checks are rerun once those tools exist.
