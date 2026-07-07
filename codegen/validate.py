from __future__ import annotations

import base64
import binascii
import re
from typing import Any

from .schema_types import SourceError
from .yaml_subset import split_inline_list


def require_list(source: dict[str, Any], key: str) -> list[dict[str, Any]]:
    value = source.get(key)
    if not isinstance(value, list):
        raise SourceError(f"{key} must be a list")
    return value


def validate_sources(registry: dict[str, Any], defaults: dict[str, Any]) -> None:
    if registry.get("format") != "bony-wire-registry":
        raise SourceError("registry/wire.yml has unexpected format")
    if defaults.get("format") != "bony-default-table":
        raise SourceError("spec/defaults.yml has unexpected format")

    backing_types = {entry["id"] for entry in require_list(registry, "backingTypes")}
    equality_modes = equality_mode_map(defaults)
    key_ranges = key_range_map(registry)
    type_keys = require_list(registry, "typeKeys")
    property_keys = require_list(registry, "propertyKeys")
    objects = require_list(registry, "objects")
    ordinal_enums = require_list(registry, "ordinalEnums")

    seen_type_keys: set[int] = set()
    seen_type_ids: set[str] = set()
    for entry in type_keys:
        type_id = required(entry, "id", "typeKeys entry")
        key = required(entry, "key", f"typeKey {type_id}")
        if key == 0:
            raise SourceError(f"typeKey {type_id} uses reserved key 0")
        validate_key_range(
            "typeKey",
            type_id,
            key,
            required(entry, "milestone", f"typeKey {type_id}"),
            key_ranges,
        )
        if key in seen_type_keys or type_id in seen_type_ids:
            raise SourceError(f"duplicate typeKey entry: {type_id}/{key}")
        seen_type_keys.add(key)
        seen_type_ids.add(type_id)

    seen_property_keys: set[int] = set()
    property_by_id: dict[str, dict[str, Any]] = {}
    for entry in property_keys:
        property_id = required(entry, "id", "propertyKeys entry")
        key = required(entry, "key", f"propertyKey {property_id}")
        backing_type = required(entry, "backingType", f"propertyKey {property_id}")
        if key == 0:
            raise SourceError(f"propertyKey {property_id} uses reserved key 0")
        validate_key_range(
            "propertyKey",
            property_id,
            key,
            required(entry, "milestone", f"propertyKey {property_id}"),
            key_ranges,
        )
        if key in seen_property_keys or property_id in property_by_id:
            raise SourceError(f"duplicate propertyKey entry: {property_id}/{key}")
        if backing_type not in backing_types:
            raise SourceError(f"propertyKey {property_id} uses unknown backingType {backing_type}")
        seen_property_keys.add(key)
        property_by_id[property_id] = entry

    object_properties: dict[str, set[str]] = {}
    for entry in objects:
        object_id = required(entry, "type", "object entry")
        if object_id not in seen_type_ids:
            raise SourceError(f"object {object_id} is not declared in typeKeys")
        properties = entry.get("properties")
        if not isinstance(properties, list):
            raise SourceError(f"object {object_id} properties must be a list")
        for property_id in properties:
            if property_id not in property_by_id:
                raise SourceError(f"object {object_id} references unknown property {property_id}")
        object_properties[object_id] = set(properties)

    seen_ordinal_enum_ids: set[str] = set()
    for entry in ordinal_enums:
        enum_id = required(entry, "id", "ordinalEnums entry")
        values = entry.get("values")
        if not isinstance(enum_id, str) or not enum_id:
            raise SourceError("ordinalEnums id must be a non-empty string")
        if enum_id in seen_ordinal_enum_ids:
            raise SourceError(f"duplicate ordinalEnums entry: {enum_id}")
        if not isinstance(values, list) or not values:
            raise SourceError(f"ordinalEnums {enum_id} values must be a non-empty list")
        seen_values: set[str] = set()
        for value in values:
            if not isinstance(value, str) or not value:
                raise SourceError(f"ordinalEnums {enum_id} values must be non-empty strings")
            if value in seen_values:
                raise SourceError(f"ordinalEnums {enum_id} has duplicate value {value}")
            seen_values.add(value)
        seen_ordinal_enum_ids.add(enum_id)

    defaulted_by_object: dict[str, set[str]] = {}
    for entry in require_list(defaults, "objectDefaults"):
        object_id = required(entry, "object", "objectDefaults entry")
        if object_id not in object_properties:
            raise SourceError(f"objectDefaults {object_id} is not declared in registry objects")
        properties = entry.get("properties")
        if not isinstance(properties, dict):
            raise SourceError(f"objectDefaults {object_id} properties must be a map")
        defaulted_by_object[object_id] = set(properties)
        for property_id, default in properties.items():
            if property_id not in object_properties[object_id]:
                raise SourceError(f"default {object_id}.{property_id} is not valid for object")
            if not isinstance(default, dict):
                raise SourceError(f"default {object_id}.{property_id} must be a map")
            value = required(default, "value", f"default {object_id}.{property_id}")
            omit_when_default = required(default, "omitWhenDefault", f"default {object_id}.{property_id}")
            apply_on_load = required(default, "applyOnLoad", f"default {object_id}.{property_id}")
            if not isinstance(omit_when_default, bool):
                raise SourceError(f"default {object_id}.{property_id}.omitWhenDefault must be bool")
            if not isinstance(apply_on_load, bool):
                raise SourceError(f"default {object_id}.{property_id}.applyOnLoad must be bool")
            backing_type = property_by_id[property_id]["backingType"]
            validate_default_value(object_id, property_id, backing_type, value)
            validate_equality_mode(
                object_id,
                property_id,
                backing_type,
                default.get("equality"),
                equality_modes,
            )
    required_by_object: dict[str, set[str]] = {}
    for entry in require_list(defaults, "requiredProperties"):
        object_id = required(entry, "object", "requiredProperties entry")
        property_id = required(entry, "property", f"requiredProperties {object_id}")
        if object_id not in object_properties:
            raise SourceError(f"requiredProperties {object_id} is not declared in registry objects")
        if property_id not in object_properties[object_id]:
            raise SourceError(f"requiredProperties {object_id}.{property_id} is not valid for object")
        required_by_object.setdefault(object_id, set()).add(property_id)

    for object_id, registry_properties in object_properties.items():
        covered = defaulted_by_object.get(object_id, set()) | required_by_object.get(object_id, set())
        overlap = defaulted_by_object.get(object_id, set()) & required_by_object.get(object_id, set())
        if overlap:
            raise SourceError(f"{object_id} properties are both defaulted and required: {sorted(overlap)}")
        if covered != registry_properties:
            missing = sorted(registry_properties - covered)
            extra = sorted(covered - registry_properties)
            raise SourceError(f"{object_id} default coverage mismatch, missing={missing}, extra={extra}")


def required(entry: dict[str, Any], key: str, where: str) -> Any:
    if key not in entry:
        raise SourceError(f"{where} missing required field {key}")
    return entry[key]


def key_range_map(registry: dict[str, Any]) -> dict[str, tuple[int, int]]:
    key_ranges = registry.get("keyRanges")
    if not isinstance(key_ranges, dict):
        raise SourceError("registry/wire.yml missing keyRanges map")
    tokens = key_ranges.get("canonicalMilestoneTokens")
    if not isinstance(tokens, list):
        raise SourceError("keyRanges.canonicalMilestoneTokens must be a list")
    ranges: dict[str, tuple[int, int]] = {}
    for band in require_list(key_ranges, "bands"):
        milestone = required(band, "milestone", "keyRanges band")
        first = required(band, "first", f"keyRanges {milestone}")
        last = required(band, "last", f"keyRanges {milestone}")
        if milestone not in tokens:
            raise SourceError(f"keyRanges band uses unknown milestone token {milestone}")
        if not isinstance(first, int) or not isinstance(last, int) or first <= 0 or last < first:
            raise SourceError(f"keyRanges {milestone} must have a positive inclusive range")
        ranges[milestone] = (first, last)
    missing = sorted(set(tokens) - set(ranges))
    if missing:
        raise SourceError(f"keyRanges missing bands for {missing}")
    return ranges


def validate_key_range(
    space: str,
    entry_id: str,
    key: int,
    milestone: Any,
    ranges: dict[str, tuple[int, int]],
) -> None:
    if not isinstance(milestone, str) or milestone not in ranges:
        raise SourceError(f"{space} {entry_id} uses unknown milestone {milestone}")
    first, last = ranges[milestone]
    if key < first or key > last:
        raise SourceError(f"{space} {entry_id} key {key} is outside {milestone} range {first}..{last}")


def equality_mode_map(defaults: dict[str, Any]) -> dict[str, set[str]]:
    modes: dict[str, set[str]] = {}
    for entry in require_list(defaults, "equalityModes"):
        mode_id = required(entry, "id", "equalityModes entry")
        applies_to = required(entry, "appliesTo", f"equalityMode {mode_id}")
        if mode_id in modes:
            raise SourceError(f"duplicate equality mode: {mode_id}")
        if not isinstance(applies_to, list):
            raise SourceError(f"equalityMode {mode_id}.appliesTo must be a list")
        modes[mode_id] = set(applies_to)
    return modes


def inferred_equality_mode(backing_type: str) -> str:
    return {
        "varuint": "exactInteger",
        "varint": "exactInteger",
        "f32": "storedF32",
        "f64": "exactFloat",
        "bool": "exactBool",
        "string": "exactString",
        "color": "exactColor",
        "bytes": "exactBytes",
    }[backing_type]


def validate_equality_mode(
    object_id: str,
    property_id: str,
    backing_type: str,
    equality: Any,
    modes: dict[str, set[str]],
) -> None:
    mode_id = equality if equality is not None else inferred_equality_mode(backing_type)
    if not isinstance(mode_id, str) or mode_id not in modes:
        raise SourceError(f"default {object_id}.{property_id} uses unknown equality mode {mode_id}")
    applies_to = modes[mode_id]
    if backing_type not in applies_to and "composite" not in applies_to:
        raise SourceError(
            f"default {object_id}.{property_id} equality {mode_id} does not apply to {backing_type}"
        )


def validate_default_value(object_id: str, property_id: str, backing_type: str, value: Any) -> None:
    where = f"default {object_id}.{property_id}"
    if backing_type == "varuint":
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            raise SourceError(f"{where} must be a non-negative integer")
    elif backing_type == "varint":
        if not isinstance(value, int) or isinstance(value, bool):
            raise SourceError(f"{where} must be an integer")
    elif backing_type == "f32":
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            raise SourceError(f"{where} must be numeric")
    elif backing_type == "f64":
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            raise SourceError(f"{where} must be numeric")
    elif backing_type == "bool":
        if not isinstance(value, bool):
            raise SourceError(f"{where} must be bool")
    elif backing_type == "string":
        if not isinstance(value, str):
            raise SourceError(f"{where} must be string")
    elif backing_type == "color":
        if (
            not isinstance(value, list)
            or len(value) != 4
            or any(
                not isinstance(channel, int)
                or isinstance(channel, bool)
                or channel < 0
                or channel > 255
                for channel in value
            )
        ):
            raise SourceError(f"{where} must be four rgba8 integer channels")
    elif backing_type == "bytes":
        if not isinstance(value, str):
            raise SourceError(f"{where} must be a base64 string")
        try:
            base64.b64decode(value, validate=True)
        except (ValueError, binascii.Error) as exc:
            raise SourceError(f"{where} must be a base64 string") from exc
    else:
        raise SourceError(f"{where} has unsupported backing type {backing_type}")
