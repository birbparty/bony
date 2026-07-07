#!/usr/bin/env python3
"""Generate bony runtime metadata and schema from registry/default sources."""

from __future__ import annotations

import argparse
import ast
import base64
import binascii
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "registry" / "wire.yml"
DEFAULTS_PATH = ROOT / "spec" / "defaults.yml"
SCHEMA_PATH = ROOT / "spec" / "bony.schema.json"
WIRE_SCHEMA_PATH = ROOT / "spec" / "bony-wire.schema.json"
NIM_WIRE_PATH = ROOT / "runtime-nim" / "src" / "bony" / "generated" / "wire.nim"
DART_WIRE_PATH = ROOT / "runtime-dart" / "lib" / "src" / "generated" / "wire.dart"

PACKED_BYTES_METADATA: dict[str, dict[str, Any]] = {
    "timelineKeys": {
        "payload": "animationTimelineKeys",
        "layout": "docs/binary-animation-state-machine-object-families.md#keyframe-payloads",
        "structuralSchema": "base64Only",
        "validatedBy": "loader",
    },
    "bones": {
        "payload": "ikConstraintBones",
        "layout": ".agents/notes/ik-format-freeze.md#3-bones-wire-encoding",
        "structuralSchema": "base64Only",
        "validatedBy": "loader",
    },
    "vertices": {
        "payload": "polygonVertices",
        "layout": "docs/helper-geometry-attachment-contract.md#packed-vertices-byte-layout-bnb",
        "structuralSchema": "base64Only",
        "validatedBy": "loader",
    },
    "meshVertices": {
        "payload": "meshAttachmentVertices",
        "layout": "docs/mesh-attachment-contract.md#packed-meshvertices-byte-layout-bnb",
        "structuralSchema": "base64Only",
        "validatedBy": "loader",
    },
    "meshUvs": {
        "payload": "meshAttachmentUvs",
        "layout": "docs/mesh-attachment-contract.md#packed-meshuvs-byte-layout-bnb",
        "structuralSchema": "base64Only",
        "validatedBy": "loader",
    },
    "meshTriangles": {
        "payload": "meshAttachmentTriangles",
        "layout": "docs/mesh-attachment-contract.md#packed-meshtriangles-byte-layout-bnb",
        "structuralSchema": "base64Only",
        "validatedBy": "loader",
    },
    "deformKeys": {
        "payload": "deformTimelineKeys",
        "layout": "docs/deform-timeline-contract.md#packed-deformtimeline-byte-layout-bnb",
        "structuralSchema": "base64Only",
        "validatedBy": "loader",
    },
    "eventKeys": {
        "payload": "eventTimelineKeys",
        "layout": "docs/event-timeline-contract.md#packed-eventtimeline-byte-layout-bnb",
        "structuralSchema": "base64Only",
        "validatedBy": "loader",
    },
    "skinBones": {
        "payload": "skinRequiredBoneMembership",
        "layout": "docs/skin-required-activation-contract.md#serialized-surface",
        "structuralSchema": "base64Only",
        "validatedBy": "loader",
    },
    "skinIkConstraints": {
        "payload": "skinRequiredIkConstraintMembership",
        "layout": "docs/skin-required-activation-contract.md#serialized-surface",
        "structuralSchema": "base64Only",
        "validatedBy": "loader",
    },
    "skinTransformConstraints": {
        "payload": "skinRequiredTransformConstraintMembership",
        "layout": "docs/skin-required-activation-contract.md#serialized-surface",
        "structuralSchema": "base64Only",
        "validatedBy": "loader",
    },
    "skinPathConstraints": {
        "payload": "skinRequiredPathConstraintMembership",
        "layout": "docs/skin-required-activation-contract.md#serialized-surface",
        "structuralSchema": "base64Only",
        "validatedBy": "loader",
    },
    "skinPhysicsConstraints": {
        "payload": "skinRequiredPhysicsConstraintMembership",
        "layout": "docs/skin-required-activation-contract.md#serialized-surface",
        "structuralSchema": "base64Only",
        "validatedBy": "loader",
    },
}

NIM_SCALAR_BACKINGS = {
    "string": "bskString",
    "f32": "bskF32",
    "f64": "bskF64",
    "bool": "bskBool",
    "varint": "bskVarint",
    "varuint": "bskVaruint",
}


class SourceError(ValueError):
    pass


@dataclass
class Line:
    indent: int
    text: str


@dataclass(frozen=True)
class TargetLangSpec:
    comment_prefix: str
    declarations: tuple[str, ...]
    registry_version_line: Callable[[int], str]
    backing_types_start: str
    backing_types_end: str
    type_key_prefix_lines: Callable[[list[dict[str, Any]]], list[str]]
    type_keys_start: str
    type_keys_end: str
    property_key_prefix_lines: Callable[[list[dict[str, Any]]], list[str]]
    property_keys_start: str
    property_keys_end: str
    object_specs_start: str
    object_specs_end: str
    property_defaults_start: str
    property_defaults_end: str
    required_properties_start: str
    required_properties_end: str
    object_properties_literal: Callable[[list[str]], str]
    json_text_literal: Callable[[Any], str]
    string_literal: Callable[[str], str]
    bool_literal: Callable[[bool], str]
    backing_type_record: Callable[[dict[str, Any]], str]
    type_key_record: Callable[[dict[str, Any]], str]
    property_key_record: Callable[[dict[str, Any]], str]
    object_spec_record: Callable[[dict[str, Any], str], str]
    property_default_record: Callable[[str, str, str, str, str, str], str]
    required_property_record: Callable[[dict[str, Any], str], str]
    trailer: tuple[str, ...]


def load_yaml_subset(path: Path) -> Any:
    """Parse the small YAML subset used by the checked-in source files."""
    lines: list[Line] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        text = strip_yaml_comment(raw).rstrip()
        if not text:
            continue
        lines.append(Line(len(text) - len(text.lstrip(" ")), text.lstrip(" ")))
    if not lines:
        return None
    value, index = parse_block(lines, 0, lines[0].indent)
    if index != len(lines):
        raise SourceError(f"{path}: could not parse line: {lines[index].text}")
    return value


def parse_block(lines: list[Line], index: int, indent: int) -> tuple[Any, int]:
    if index >= len(lines) or lines[index].indent < indent:
        return None, index
    if lines[index].text.startswith("- "):
        return parse_list(lines, index, indent)
    return parse_map(lines, index, indent)


def parse_list(lines: list[Line], index: int, indent: int) -> tuple[list[Any], int]:
    items: list[Any] = []
    while index < len(lines) and lines[index].indent == indent and lines[index].text.startswith("- "):
        item_text = lines[index].text[2:].strip()
        index += 1
        if item_text == "":
            item, index = parse_block(lines, index, indent + 2)
            items.append(item)
            continue
        if ":" in item_text and not item_text.startswith(("'", '"')):
            key, rest = split_key_value(item_text)
            item: dict[str, Any] = {}
            if rest == "":
                item[key] = None
            else:
                item[key] = parse_scalar(rest)
            if index < len(lines) and lines[index].indent > indent:
                child, index = parse_map(lines, index, indent + 2)
                item.update(child)
            items.append(item)
            continue
        items.append(parse_scalar(item_text))
    return items, index


def parse_map(lines: list[Line], index: int, indent: int) -> tuple[dict[str, Any], int]:
    mapping: dict[str, Any] = {}
    while index < len(lines) and lines[index].indent == indent and not lines[index].text.startswith("- "):
        key, rest = split_key_value(lines[index].text)
        if key in mapping:
            raise SourceError(f"duplicate mapping key: {key}")
        index += 1
        if rest in ("", ">"):
            if rest == ">":
                parts: list[str] = []
                while index < len(lines) and lines[index].indent > indent:
                    parts.append(lines[index].text)
                    index += 1
                mapping[key] = " ".join(parts)
            elif index < len(lines) and lines[index].indent > indent:
                mapping[key], index = parse_block(lines, index, lines[index].indent)
            else:
                mapping[key] = None
        else:
            mapping[key] = parse_scalar(rest)
    return mapping, index


def split_key_value(text: str) -> tuple[str, str]:
    if ":" not in text:
        raise SourceError(f"expected key/value entry, got: {text}")
    key, value = text.split(":", 1)
    return key.strip(), value.strip()


def parse_scalar(text: str) -> Any:
    if text == "[]":
        return []
    if text == "{}":
        return {}
    if text.startswith("[") and text.endswith("]"):
        return [parse_scalar(part.strip()) for part in split_inline_list(text[1:-1]) if part.strip()]
    if text in ("true", "false"):
        return text == "true"
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if re.fullmatch(r"-?\d+\.\d+", text):
        return float(text)
    if (text.startswith('"') and text.endswith('"')) or (text.startswith("'") and text.endswith("'")):
        return ast.literal_eval(text)
    return text


def strip_yaml_comment(text: str) -> str:
    quote: str | None = None
    escaped = False
    for index, char in enumerate(text):
        if quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char in ("'", '"'):
            quote = char
            continue
        if char == "#":
            return text[:index]
    return text


def split_inline_list(text: str) -> list[str]:
    parts: list[str] = []
    start = 0
    quote: str | None = None
    escaped = False
    for index, char in enumerate(text):
        if quote is not None:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue
        if char in ("'", '"'):
            quote = char
            continue
        if char == ",":
            parts.append(text[start:index])
            start = index + 1
    parts.append(text[start:])
    return parts


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


def build_root_properties(
    type_keys: list[dict[str, Any]],
    *,
    hidden: set[str] | None = None,
    collection_overrides: dict[str, str] | None = None,
) -> tuple[dict[str, Any], list[str]]:
    hidden_ids = hidden or set()
    overrides = collection_overrides or {}
    root_properties: dict[str, Any] = {}
    required_root: list[str] = []
    for entry in type_keys:
        object_id = entry["id"]
        if object_id in hidden_ids:
            continue
        if object_id == "skeleton":
            root_properties["skeleton"] = {"$ref": "#/$defs/skeleton"}
            required_root.append("skeleton")
            continue
        collection_id = overrides.get(object_id, object_id + "s")
        root_properties[collection_id] = {
            "type": "array",
            "items": {"$ref": f"#/$defs/{object_id}"},
        }
        if object_id == "bone":
            required_root.append(collection_id)
    return root_properties, required_root


def generate_schema(registry: dict[str, Any], defaults: dict[str, Any]) -> str:
    schema = json.loads(generate_wire_schema(registry, defaults))
    schema["$id"] = "https://bony.local/spec/bony.schema.json"
    schema["title"] = "bony JSON"
    schema["description"] = (
        "Generated canonical .bony JSON schema from registry/wire.yml and spec/defaults.yml."
    )
    schema["$defs"].update(canonical_json_overrides())

    hidden_binary_children = {
        "boneTimeline",
        "slotTimeline",
        "stateMachineInput",
        "stateMachineLayer",
        "stateMachineState",
        "stateMachineBlendClip",
        "stateMachineTransition",
        "stateMachineCondition",
        "stateMachineListener",
        "skinEntry",
        "warpLattice",
        "rotationDeformer",
        "keyformBlend",
        "keyform",
    }
    root_collection_overrides = {
        "animationClip": "animations",
        "stateMachine": "stateMachines",
    }
    root_properties, required_root = build_root_properties(
        require_list(registry, "typeKeys"),
        hidden=hidden_binary_children,
        collection_overrides=root_collection_overrides,
    )

    if "skins" in root_properties:
        root_properties["skins"]["minItems"] = 1
        root_properties["skins"]["contains"] = {
            "type": "object",
            "properties": {"name": {"const": "default"}},
            "required": ["name"],
        }

    schema["properties"] = root_properties
    schema["required"] = required_root
    return json.dumps(schema, indent=2) + "\n"


def generate_wire_schema(registry: dict[str, Any], defaults: dict[str, Any]) -> str:
    type_keys = require_list(registry, "typeKeys")
    property_keys = require_list(registry, "propertyKeys")
    objects = require_list(registry, "objects")
    property_backing = {entry["id"]: entry["backingType"] for entry in property_keys}
    default_map = {
        entry["object"]: entry.get("properties", {})
        for entry in require_list(defaults, "objectDefaults")
    }
    required_map: dict[str, list[str]] = {}
    for entry in require_list(defaults, "requiredProperties"):
        required_map.setdefault(entry["object"], []).append(entry["property"])

    definitions: dict[str, Any] = {}
    for entry in objects:
        object_id = entry["type"]
        properties: dict[str, Any] = {}
        for property_id in entry["properties"]:
            property_schema = schema_for_property(property_id, property_backing[property_id])
            default_entry = default_map.get(object_id, {}).get(property_id)
            if default_entry is not None and default_entry["applyOnLoad"] is True:
                property_schema["default"] = default_map[object_id][property_id]["value"]
            properties[property_id] = property_schema
        definitions[object_id] = {
            "type": "object",
            "additionalProperties": False,
            "properties": properties,
            "required": sorted(required_map.get(object_id, [])),
        }
        if object_id == "bone" and {"inheritRotation", "inheritScale", "inheritReflection", "transformMode"}.issubset(
            properties
        ):
            definitions[object_id]["allOf"] = transform_constraint_schema()

    root_properties, required_root = build_root_properties(type_keys)

    schema: dict[str, Any] = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://bony.local/spec/bony-wire.schema.json",
        "title": "bony wire registry objects",
        "description": "Generated flat registry-object schema from registry/wire.yml and spec/defaults.yml.",
        "type": "object",
        "additionalProperties": False,
        "properties": root_properties,
        "required": required_root,
        "$defs": definitions,
    }
    if not type_keys:
        schema["not"] = {}
    return json.dumps(schema, indent=2) + "\n"


def canonical_json_overrides() -> dict[str, Any]:
    named_string = {"type": "string", "minLength": 1}
    number = {"type": "number"}
    keyframes = {
        "type": "array",
        "minItems": 1,
        "items": {
            "type": "object",
            "additionalProperties": True,
            "properties": {"t": {"type": "number"}},
            "required": ["t"],
        },
    }
    # Event keyframes enumerate the readable EventData fields (docs/event-timeline-contract.md
    # "Model"); optional-field defaults mirror the eventData constructor
    # (runtime-nim/src/bony/anim/timelines.nim eventData). Unlike bone/slot/deform keyframes
    # (which carry unenumerated packed fields), the event keyframe shape is fully specified.
    event_keyframes = {
        "type": "array",
        "minItems": 1,
        "items": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "t": {"type": "number"},
                "name": named_string,
                "intValue": {"type": "integer", "default": 0},
                "floatValue": {"type": "number", "default": 0.0},
                "stringValue": {"type": "string", "default": ""},
                "audioPath": {"type": "string", "default": ""},
                "volume": {"type": "number", "default": 1.0},
                "balance": {"type": "number", "default": 0.0},
            },
            "required": ["name", "t"],
        },
    }
    return {
        "region": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "name": named_string,
                "width": {"type": "number", "minimum": 0},
                "height": {"type": "number", "minimum": 0},
                "texturePage": {"type": "string", "default": ""},
                "u0": {"type": "number", "minimum": 0, "maximum": 1, "default": 0.0},
                "v0": {"type": "number", "minimum": 0, "maximum": 1, "default": 0.0},
                "u1": {"type": "number", "minimum": 0, "maximum": 1, "default": 1.0},
                "v1": {"type": "number", "minimum": 0, "maximum": 1, "default": 1.0},
                "alphaMode": {
                    "type": "string",
                    "enum": ["straight", "premultiplied"],
                    "default": "straight",
                },
            },
            "required": ["height", "name", "width"],
        },
        "ikConstraint": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "name": named_string,
                "bones": {"type": "array", "minItems": 1, "items": named_string},
                "target": {"type": "string"},
                "order": {"type": "integer", "default": 0},
                "skinRequired": {"type": "boolean", "default": False},
                "mix": {"type": "number", "minimum": 0, "maximum": 1, "default": 1.0},
                "bendPositive": {"type": "boolean", "default": True},
            },
            "required": ["bones", "name", "target"],
        },
        "clippingAttachment": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "name": named_string,
                "vertices": {"type": "array", "minItems": 6, "items": number},
                "untilSlot": {"type": "string", "default": ""},
            },
            "required": ["name", "vertices"],
        },
        "pointAttachment": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "name": named_string,
                "x": number,
                "y": number,
                "rotation": number,
            },
            "required": ["name", "rotation", "x", "y"],
        },
        "boundingBoxAttachment": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "name": named_string,
                "vertices": {"type": "array", "minItems": 6, "items": number},
            },
            "required": ["name", "vertices"],
        },
        "meshAttachment": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "name": named_string,
                "weighted": {"type": "boolean", "default": False},
                "vertices": {
                    "type": "array",
                    "minItems": 1,
                    "items": {
                        "oneOf": [
                            {
                                "type": "object",
                                "additionalProperties": False,
                                "properties": {"x": number, "y": number},
                                "required": ["x", "y"],
                            },
                            {
                                "type": "object",
                                "additionalProperties": False,
                                "properties": {
                                    "influences": {
                                        "type": "array",
                                        "minItems": 1,
                                        "items": {
                                            "type": "object",
                                            "additionalProperties": False,
                                            "properties": {
                                                "bone": named_string,
                                                "bindX": number,
                                                "bindY": number,
                                                "weight": number,
                                            },
                                            "required": ["bindX", "bindY", "bone", "weight"],
                                        },
                                    },
                                },
                                "required": ["influences"],
                            },
                        ],
                    },
                },
                "uvs": {
                    "type": "array",
                    "minItems": 2,
                    "items": {"type": "number", "minimum": 0, "maximum": 1},
                    "description": (
                        "Flat [u0, v0, u1, v1, ...] pairs; each coordinate is unit-range "
                        "0..1; length is even and matches the vertex count "
                        "(loader-validated per docs/mesh-attachment-contract.md)."
                    ),
                },
                "triangles": {
                    "type": "array",
                    "minItems": 3,
                    "items": {"type": "integer", "minimum": 0},
                    "description": (
                        "Flat vertex-index triples; length is a multiple of 3 "
                        "(loader-validated per docs/mesh-attachment-contract.md)."
                    ),
                },
            },
            "required": ["name", "triangles", "uvs", "vertices"],
        },
        "nestedRigAttachment": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "name": named_string,
                "skeleton": named_string,
                "skin": {"type": "string", "default": ""},
                "animation": {"type": "string", "default": ""},
            },
            "required": ["name", "skeleton"],
        },
        "parameter": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "name": named_string,
                "min": number,
                "max": number,
                "default": {"type": "number", "default": 0.0},
            },
            "required": ["max", "min", "name"],
        },
        "deformer": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "id": named_string,
                "parent": {"type": "string", "default": ""},
                "order": {"type": "integer", "default": 0},
                "kind": {"type": "string", "enum": ["warp", "rotation"]},
                "warp": {"$ref": "#/$defs/warpLattice"},
                "rotation": {"$ref": "#/$defs/rotationDeformer"},
                "keyformBlend": {"$ref": "#/$defs/keyformBlend"},
            },
            "required": ["id", "kind"],
        },
        "warpLattice": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "rows": {"type": "integer", "minimum": 0},
                "cols": {"type": "integer", "minimum": 0},
                "minX": number,
                "minY": number,
                "maxX": number,
                "maxY": number,
                "controlPoints": {
                    "type": "array",
                    "items": {"$ref": "#/$defs/deformerPoint"},
                },
            },
            "required": ["cols", "controlPoints", "maxX", "maxY", "minX", "minY", "rows"],
        },
        "deformerPoint": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "x": number,
                "y": number,
            },
            "required": ["x", "y"],
        },
        "rotationDeformer": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "pivotX": number,
                "pivotY": number,
                "angleDegrees": number,
                "scaleX": {"type": "number", "default": 1.0},
                "scaleY": {"type": "number", "default": 1.0},
                "opacity": {"type": "number", "default": 1.0},
            },
            "required": ["angleDegrees", "pivotX", "pivotY"],
        },
        "keyformBlend": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "axes": {
                    "type": "array",
                    "minItems": 1,
                    "items": named_string,
                },
                "keyforms": {
                    "type": "array",
                    "minItems": 1,
                    "items": {"$ref": "#/$defs/keyform"},
                },
            },
            "required": ["axes", "keyforms"],
        },
        "keyform": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "coordinates": {
                    "type": "object",
                    "additionalProperties": {"type": "number"},
                },
                "values": {
                    "type": "array",
                    "items": number,
                },
            },
            "required": ["coordinates", "values"],
        },
        "animationClip": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "name": named_string,
                "boneTimelines": {
                    "type": "array",
                    "items": {"$ref": "#/$defs/boneTimeline"},
                    "default": [],
                },
                "slotTimelines": {
                    "type": "array",
                    "items": {"$ref": "#/$defs/slotTimeline"},
                    "default": [],
                },
                "deformTimelines": {
                    "type": "array",
                    "items": {"$ref": "#/$defs/deformTimeline"},
                    "default": [],
                },
                "eventTimelines": {
                    "type": "array",
                    "items": {"$ref": "#/$defs/eventTimeline"},
                    "default": [],
                },
            },
            "required": ["name"],
        },
        "boneTimeline": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "bone": named_string,
                "property": {
                    "type": "string",
                    "enum": [
                        "rotate",
                        "translateX",
                        "translateY",
                        "scaleX",
                        "scaleY",
                        "shearX",
                        "shearY",
                        "translate",
                        "scale",
                        "shear",
                        "inherit",
                    ],
                },
                "keyframes": keyframes,
            },
            "required": ["bone", "keyframes", "property"],
        },
        "slotTimeline": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "slot": named_string,
                "property": {
                    "type": "string",
                    "enum": ["attachment", "rgba", "rgb", "alpha", "rgba2", "sequence"],
                },
                "keyframes": keyframes,
            },
            "required": ["keyframes", "property", "slot"],
        },
        "deformTimeline": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "skin": named_string,
                "slot": named_string,
                "attachment": named_string,
                "vertexCount": {"type": "integer", "minimum": 1},
                "keyframes": keyframes,
            },
            "required": ["attachment", "keyframes", "skin", "slot", "vertexCount"],
        },
        "skin": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "name": named_string,
                "bones": {"type": "array", "items": named_string, "default": []},
                "ikConstraints": {"type": "array", "items": named_string, "default": []},
                "transformConstraints": {"type": "array", "items": named_string, "default": []},
                "pathConstraints": {"type": "array", "items": named_string, "default": []},
                "physicsConstraints": {"type": "array", "items": named_string, "default": []},
                "entries": {
                    "type": "array",
                    "items": {"$ref": "#/$defs/skinEntry"},
                    "default": [],
                },
            },
            "required": ["name"],
        },
        "skinEntry": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "slot": named_string,
                "attachment": named_string,
                "target": named_string,
            },
            "required": ["attachment", "slot", "target"],
        },
        "eventTimeline": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "keyframes": event_keyframes,
            },
            "required": ["keyframes"],
        },
        "stateMachine": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "name": named_string,
                "inputs": {
                    "type": "array",
                    "items": {"$ref": "#/$defs/stateMachineInput"},
                    "default": [],
                },
                "layers": {
                    "type": "array",
                    "minItems": 1,
                    "items": {"$ref": "#/$defs/stateMachineLayer"},
                },
                "listeners": {
                    "type": "array",
                    "items": {"$ref": "#/$defs/stateMachineListener"},
                    "default": [],
                },
            },
            "required": ["layers", "name"],
        },
        "stateMachineInput": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "name": named_string,
                "kind": {"type": "string", "enum": ["bool", "number", "trigger"]},
                "default": {"type": ["boolean", "number"]},
            },
            "required": ["kind", "name"],
        },
        "stateMachineLayer": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "name": named_string,
                "initialState": named_string,
                "states": {
                    "type": "array",
                    "minItems": 1,
                    "items": {"$ref": "#/$defs/stateMachineState"},
                },
                "transitions": {
                    "type": "array",
                    "items": {"$ref": "#/$defs/stateMachineTransition"},
                    "default": [],
                },
            },
            "required": ["name", "states"],
        },
        "stateMachineState": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "name": named_string,
                "kind": {"type": "string", "enum": ["clip", "blend1d"]},
                "clip": named_string,
                "loop": {"type": "boolean", "default": False},
                "blendInput": named_string,
                "blendClips": {
                    "type": "array",
                    "minItems": 1,
                    "items": {"$ref": "#/$defs/stateMachineBlendClip"},
                },
            },
            "required": ["kind", "name"],
        },
        "stateMachineBlendClip": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "clip": named_string,
                "value": {"type": "number"},
                "loop": {"type": "boolean", "default": False},
            },
            "required": ["clip", "value"],
        },
        "stateMachineTransition": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "fromState": named_string,
                "toState": named_string,
                "conditions": {
                    "type": "array",
                    "minItems": 1,
                    "items": {"$ref": "#/$defs/stateMachineCondition"},
                },
            },
            "required": ["conditions", "fromState", "toState"],
        },
        "stateMachineCondition": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "input": named_string,
                "kind": {
                    "type": "string",
                    "enum": [
                        "boolEquals",
                        "numberEquals",
                        "numberGreater",
                        "numberGreaterOrEqual",
                        "numberLess",
                        "numberLessOrEqual",
                        "triggerSet",
                    ],
                },
                "value": {"type": ["boolean", "number"]},
            },
            "required": ["input", "kind"],
        },
        "stateMachineListener": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "name": named_string,
                "kind": {
                    "type": "string",
                    "enum": [
                        "stateEnter",
                        "stateExit",
                        "transition",
                        "pointerDown",
                        "pointerUp",
                        "pointerEnter",
                        "pointerExit",
                        "pointerMove",
                    ],
                },
                "layer": named_string,
                "fromState": named_string,
                "toState": named_string,
                "slot": named_string,
                "targetKind": {"type": "string", "enum": ["point", "boundingBox"]},
                "target": named_string,
                "hitRadius": {"type": "number"},
                "input": named_string,
                "value": {"type": ["boolean", "number"]},
            },
            "required": ["kind", "name"],
        },
    }


def schema_for_backing_type(backing_type: str) -> dict[str, Any]:
    mapping = {
        "varuint": {"type": "integer", "minimum": 0},
        "varint": {"type": "integer"},
        "f32": {"type": "number"},
        "f64": {"type": "number"},
        "bool": {"type": "boolean"},
        "string": {"type": "string"},
        "color": {
            "type": "array",
            "prefixItems": [{"type": "integer", "minimum": 0, "maximum": 255}] * 4,
            "minItems": 4,
            "maxItems": 4,
        },
        "bytes": {"type": "string", "contentEncoding": "base64"},
    }
    if backing_type not in mapping:
        raise SourceError(f"cannot map backing type to JSON Schema: {backing_type}")
    return dict(mapping[backing_type])


def schema_for_property(property_id: str, backing_type: str) -> dict[str, Any]:
    schema = schema_for_backing_type(backing_type)
    if backing_type == "bytes" and property_id in PACKED_BYTES_METADATA:
        schema["x-bony-packedBytes"] = dict(PACKED_BYTES_METADATA[property_id])
    if property_id == "name":
        schema["minLength"] = 1
    if property_id == "transformMode":
        schema["enum"] = [
            "normal",
            "onlyTranslation",
            "noRotationOrReflection",
            "noScale",
            "noScaleOrReflection",
        ]
    if property_id in {"width", "height", "mass"}:
        schema["minimum"] = 0
    if property_id in {"position", "translateMix", "rotateMix", "scaleMix", "shearMix", "mix", "physicsMix"}:
        schema["minimum"] = 0
        schema["maximum"] = 1
    if property_id == "channels":
        # Physics enabled-channel bitmask: at least one bit set, no bit beyond the
        # five PhysicsChannel ordinals (pcX..pcShearX). Matches the loader, which
        # rejects an empty mask and any bit >= 1 << 5.
        schema["minimum"] = 1
        schema["maximum"] = 31
    return schema


def transform_constraint_schema() -> list[dict[str, Any]]:
    modes = {
        "normal": (True, True, True),
        "onlyTranslation": (False, False, False),
        "noRotationOrReflection": (False, True, False),
        "noScale": (True, False, True),
        "noScaleOrReflection": (True, False, False),
    }
    constraints: list[dict[str, Any]] = []

    for mode, (inherit_rotation, inherit_scale, inherit_reflection) in modes.items():
        required_false_flags = [
            name
            for name, value in [
                ("inheritRotation", inherit_rotation),
                ("inheritScale", inherit_scale),
                ("inheritReflection", inherit_reflection),
            ]
            if value is False
        ]
        constraints.append(
            {
                "if": {
                    "properties": {"transformMode": {"const": mode}},
                    "required": ["transformMode"],
                },
                "then": {
                    "properties": {
                        "inheritRotation": {"const": inherit_rotation},
                        "inheritScale": {"const": inherit_scale},
                        "inheritReflection": {"const": inherit_reflection},
                    },
                    "required": required_false_flags,
                },
            }
        )
        if mode == "normal":
            continue
        constraints.append(
            {
                "if": {
                    "properties": {
                        "inheritRotation": {"const": inherit_rotation},
                        "inheritScale": {"const": inherit_scale},
                        "inheritReflection": {"const": inherit_reflection},
                    },
                    "required": required_false_flags,
                },
                "then": {
                    "properties": {
                        "transformMode": {"const": mode},
                    },
                    "required": ["transformMode"],
                },
            }
        )

    for inherit_rotation, inherit_scale, inherit_reflection in [
        (False, False, True),
        (False, True, True),
        (True, True, False),
    ]:
        required_false_flags = [
            name
            for name, value in [
                ("inheritRotation", inherit_rotation),
                ("inheritScale", inherit_scale),
                ("inheritReflection", inherit_reflection),
            ]
            if value is False
        ]
        constraints.append(
            {
                "not": {
                    "properties": {
                        "inheritRotation": {"const": inherit_rotation},
                        "inheritScale": {"const": inherit_scale},
                        "inheritReflection": {"const": inherit_reflection},
                    },
                    "required": required_false_flags,
                }
            }
        )
    return constraints


def emit_runtime_metadata(registry: dict[str, Any], defaults: dict[str, Any], spec: TargetLangSpec) -> str:
    backing_types = require_list(registry, "backingTypes")
    type_keys = require_list(registry, "typeKeys")
    property_keys = require_list(registry, "propertyKeys")
    objects = require_list(registry, "objects")
    object_defaults = require_list(defaults, "objectDefaults")
    required_properties = require_list(defaults, "requiredProperties")
    lines = [
        f"{spec.comment_prefix} Generated by codegen/generate.py; do not edit by hand.",
        "",
    ]
    lines.extend(spec.declarations)
    lines.extend([spec.registry_version_line(registry["registryVersion"]), spec.backing_types_start])
    for entry in backing_types:
        lines.append(spec.backing_type_record(entry))
    lines.extend([spec.backing_types_end, *spec.type_key_prefix_lines(type_keys), spec.type_keys_start])
    for entry in type_keys:
        lines.append(spec.type_key_record(entry))
    lines.extend([spec.type_keys_end, *spec.property_key_prefix_lines(property_keys), spec.property_keys_start])
    for entry in property_keys:
        lines.append(spec.property_key_record(entry))
    lines.extend([spec.property_keys_end, spec.object_specs_start])
    for entry in objects:
        properties = spec.object_properties_literal(entry["properties"])
        lines.append(spec.object_spec_record(entry, properties))
    lines.extend([spec.object_specs_end, spec.property_defaults_start])
    for entry in object_defaults:
        object_id = entry["object"]
        for property_id, default in entry.get("properties", {}).items():
            equality = default.get("equality") or inferred_equality_mode(
                property_backing_type(registry, property_id)
            )
            lines.append(
                spec.property_default_record(
                    object_id,
                    property_id,
                    equality,
                    spec.json_text_literal(default["value"]),
                    spec.bool_literal(default["omitWhenDefault"]),
                    spec.bool_literal(default["applyOnLoad"]),
                )
            )
    lines.extend([spec.property_defaults_end, spec.required_properties_start])
    for entry in required_properties:
        lines.append(spec.required_property_record(entry, spec.string_literal(entry["reason"])))
    lines.extend([spec.required_properties_end, *spec.trailer])
    return "\n".join(lines)


def nim_identifier_suffix(identifier: str) -> str:
    return dart_const_suffix(identifier)


def nim_scalar_value_literal(backing_type: str, value: Any | None) -> str:
    if backing_type == "string":
        return f"bonyStringValue({nim_string_literal(value if isinstance(value, str) else '')})"
    if backing_type == "f32":
        numeric = 0.0 if value is None else value
        return f"bonyF32Value({float(numeric)!r})"
    if backing_type == "f64":
        numeric = 0.0 if value is None else value
        return f"bonyF64Value({float(numeric)!r})"
    if backing_type == "bool":
        return f"bonyBoolValue({generated_bool(bool(value))})"
    if backing_type == "varint":
        numeric = 0 if value is None else int(value)
        return f"bonyIntValue({numeric}.int64)"
    if backing_type == "varuint":
        numeric = 0 if value is None else int(value)
        return f"bonyUintValue({numeric}.uint64)"
    raise SourceError(f"unsupported Nim scalar backing type {backing_type}")


def nim_scalar_codec_lines(registry: dict[str, Any], defaults: dict[str, Any]) -> list[str]:
    type_keys = require_list(registry, "typeKeys")
    property_keys = require_list(registry, "propertyKeys")
    objects = require_list(registry, "objects")
    property_by_id = {entry["id"]: entry for entry in property_keys}
    type_key_by_id = {entry["id"]: entry["key"] for entry in type_keys}
    default_map = {
        entry["object"]: entry.get("properties", {})
        for entry in require_list(defaults, "objectDefaults")
    }
    required_map: dict[str, set[str]] = {}
    for entry in require_list(defaults, "requiredProperties"):
        required_map.setdefault(entry["object"], set()).add(entry["property"])

    lines = [
        "",
        "type",
        "  BonyScalarKind* = enum",
        "    bskString, bskF32, bskF64, bskBool, bskVarint, bskVaruint",
        "  BonyScalarValue* = object",
        "    case kind*: BonyScalarKind",
        "    of bskString:",
        "      stringValue*: string",
        "    of bskF32, bskF64:",
        "      floatValue*: float64",
        "    of bskBool:",
        "      boolValue*: bool",
        "    of bskVarint:",
        "      intValue*: int64",
        "    of bskVaruint:",
        "      uintValue*: uint64",
        "  BonyJsonScalarProperty* = object",
        "    propertyId*: string",
        "    value*: BonyScalarValue",
        "  BonyBnbScalarProperty* = object",
        "    propertyKey*: uint64",
        "    value*: BonyScalarValue",
        "  BonyScalarPropertySpec* = object",
        "    objectId*: string",
        "    propertyId*: string",
        "    propertyKey*: uint64",
        "    kind*: BonyScalarKind",
        "    required*: bool",
        "    hasDefault*: bool",
        "    defaultValue*: BonyScalarValue",
        "    equality*: string",
        "    omitWhenDefault*: bool",
        "    applyOnLoad*: bool",
        "",
        "func bonyStringValue*(value: string): BonyScalarValue =",
        "  BonyScalarValue(kind: bskString, stringValue: value)",
        "",
        "func bonyF32Value*(value: float64): BonyScalarValue =",
        "  BonyScalarValue(kind: bskF32, floatValue: value)",
        "",
        "func bonyF64Value*(value: float64): BonyScalarValue =",
        "  BonyScalarValue(kind: bskF64, floatValue: value)",
        "",
        "func bonyBoolValue*(value: bool): BonyScalarValue =",
        "  BonyScalarValue(kind: bskBool, boolValue: value)",
        "",
        "func bonyIntValue*(value: int64): BonyScalarValue =",
        "  BonyScalarValue(kind: bskVarint, intValue: value)",
        "",
        "func bonyUintValue*(value: uint64): BonyScalarValue =",
        "  BonyScalarValue(kind: bskVaruint, uintValue: value)",
        "",
        "proc bonyScalarMatchesKind(value: BonyScalarValue; kind: BonyScalarKind): bool =",
        "  if kind == bskF32:",
        "    return value.kind in {bskF32, bskF64}",
        "  value.kind == kind",
        "",
        "proc bonyScalarEquals(value, defaultValue: BonyScalarValue; equality: string): bool =",
        "  if equality == \"storedF32\":",
        "    return value.kind in {bskF32, bskF64} and defaultValue.kind in {bskF32, bskF64} and",
        "      float32(value.floatValue) == float32(defaultValue.floatValue)",
        "  if not value.bonyScalarMatchesKind(defaultValue.kind):",
        "    return false",
        "  case defaultValue.kind",
        "  of bskString:",
        "    value.stringValue == defaultValue.stringValue",
        "  of bskF32:",
        "    value.floatValue == defaultValue.floatValue",
        "  of bskF64:",
        "    value.floatValue == defaultValue.floatValue",
        "  of bskBool:",
        "    value.boolValue == defaultValue.boolValue",
        "  of bskVarint:",
        "    value.intValue == defaultValue.intValue",
        "  of bskVaruint:",
        "    value.uintValue == defaultValue.uintValue",
        "",
        "proc bonyFindJsonScalar(properties: openArray[BonyJsonScalarProperty]; propertyId: string): int =",
        "  for index, property in properties:",
        "    if property.propertyId == propertyId:",
        "      return index",
        "  -1",
        "",
        "proc bonyFindBnbScalar(properties: openArray[BonyBnbScalarProperty]; propertyKey: uint64): int =",
        "  for index, property in properties:",
        "    if property.propertyKey == propertyKey:",
        "      return index",
        "  -1",
        "",
        "proc bonyValidateJsonScalar(specs: openArray[BonyScalarPropertySpec]; property: BonyJsonScalarProperty) =",
        "  for spec in specs:",
        "    if spec.propertyId == property.propertyId:",
        "      if not property.value.bonyScalarMatchesKind(spec.kind):",
        "        raise newException(ValueError, \"wrong scalar kind for \" & spec.objectId & \".\" & spec.propertyId)",
        "      return",
        "  raise newException(ValueError, \"unknown scalar property id: \" & property.propertyId)",
        "",
        "proc bonyValidateBnbScalar(specs: openArray[BonyScalarPropertySpec]; property: BonyBnbScalarProperty) =",
        "  for spec in specs:",
        "    if spec.propertyKey == property.propertyKey:",
        "      if not property.value.bonyScalarMatchesKind(spec.kind):",
        "        raise newException(ValueError, \"wrong scalar kind for \" & spec.objectId & \".\" & spec.propertyId)",
        "      return",
        "  raise newException(ValueError, \"unknown scalar property key: \" & $property.propertyKey)",
        "",
        "proc bonyValidateJsonScalarProperties(specs: openArray[BonyScalarPropertySpec]; properties: openArray[BonyJsonScalarProperty]) =",
        "  var seen: seq[string]",
        "  for property in properties:",
        "    if property.propertyId in seen:",
        "      raise newException(ValueError, \"duplicate scalar property id: \" & property.propertyId)",
        "    seen.add property.propertyId",
        "    bonyValidateJsonScalar(specs, property)",
        "",
        "proc bonyValidateBnbScalarProperties(specs: openArray[BonyScalarPropertySpec]; properties: openArray[BonyBnbScalarProperty]) =",
        "  var seen: seq[uint64]",
        "  for property in properties:",
        "    if property.propertyKey in seen:",
        "      raise newException(ValueError, \"duplicate scalar property key: \" & $property.propertyKey)",
        "    seen.add property.propertyKey",
        "    bonyValidateBnbScalar(specs, property)",
        "",
        "proc bonyEncodeJsonScalars*(specs: openArray[BonyScalarPropertySpec]; properties: openArray[BonyJsonScalarProperty]): seq[BonyJsonScalarProperty] =",
        "  bonyValidateJsonScalarProperties(specs, properties)",
        "  for spec in specs:",
        "    let index = properties.bonyFindJsonScalar(spec.propertyId)",
        "    if index < 0:",
        "      if spec.required:",
        "        raise newException(ValueError, \"missing required scalar property: \" & spec.objectId & \".\" & spec.propertyId)",
        "      continue",
        "    let value = properties[index].value",
        "    if spec.omitWhenDefault and spec.hasDefault and bonyScalarEquals(value, spec.defaultValue, spec.equality):",
        "      continue",
        "    result.add BonyJsonScalarProperty(propertyId: spec.propertyId, value: value)",
        "",
        "proc bonyDecodeJsonScalars*(specs: openArray[BonyScalarPropertySpec]; properties: openArray[BonyJsonScalarProperty]): seq[BonyJsonScalarProperty] =",
        "  bonyValidateJsonScalarProperties(specs, properties)",
        "  for spec in specs:",
        "    let index = properties.bonyFindJsonScalar(spec.propertyId)",
        "    if index >= 0:",
        "      result.add BonyJsonScalarProperty(propertyId: spec.propertyId, value: properties[index].value)",
        "    elif spec.hasDefault and spec.applyOnLoad:",
        "      result.add BonyJsonScalarProperty(propertyId: spec.propertyId, value: spec.defaultValue)",
        "    elif spec.required:",
        "      raise newException(ValueError, \"missing required scalar property: \" & spec.objectId & \".\" & spec.propertyId)",
        "",
        "proc bonyEncodeBnbScalars*(specs: openArray[BonyScalarPropertySpec]; properties: openArray[BonyBnbScalarProperty]): seq[BonyBnbScalarProperty] =",
        "  bonyValidateBnbScalarProperties(specs, properties)",
        "  for spec in specs:",
        "    let index = properties.bonyFindBnbScalar(spec.propertyKey)",
        "    if index < 0:",
        "      if spec.required:",
        "        raise newException(ValueError, \"missing required scalar property: \" & spec.objectId & \".\" & spec.propertyId)",
        "      continue",
        "    let value = properties[index].value",
        "    if spec.omitWhenDefault and spec.hasDefault and bonyScalarEquals(value, spec.defaultValue, spec.equality):",
        "      continue",
        "    result.add BonyBnbScalarProperty(propertyKey: spec.propertyKey, value: value)",
        "",
        "proc bonyDecodeBnbScalars*(specs: openArray[BonyScalarPropertySpec]; properties: openArray[BonyBnbScalarProperty]): seq[BonyBnbScalarProperty] =",
        "  bonyValidateBnbScalarProperties(specs, properties)",
        "  for spec in specs:",
        "    let index = properties.bonyFindBnbScalar(spec.propertyKey)",
        "    if index >= 0:",
        "      result.add BonyBnbScalarProperty(propertyKey: spec.propertyKey, value: properties[index].value)",
        "    elif spec.hasDefault and spec.applyOnLoad:",
        "      result.add BonyBnbScalarProperty(propertyKey: spec.propertyKey, value: spec.defaultValue)",
        "    elif spec.required:",
        "      raise newException(ValueError, \"missing required scalar property: \" & spec.objectId & \".\" & spec.propertyId)",
        "",
    ]

    scalar_object_ids: list[str] = []
    for obj in objects:
        object_id = obj["type"]
        scalar_properties = [
            property_id
            for property_id in obj["properties"]
            if property_by_id[property_id]["backingType"] in NIM_SCALAR_BACKINGS
        ]
        scalar_object_ids.append(object_id)
        suffix = nim_identifier_suffix(object_id)
        if scalar_properties:
            lines.append(f"const bony{suffix}ScalarSpecs* = [")
            for property_id in scalar_properties:
                property_entry = property_by_id[property_id]
                backing_type = property_entry["backingType"]
                default = default_map.get(object_id, {}).get(property_id)
                equality = (default or {}).get("equality") or inferred_equality_mode(backing_type)
                default_value = default["value"] if default is not None else None
                lines.append(
                    "  BonyScalarPropertySpec("
                    f"objectId: {nim_string_literal(object_id)}, "
                    f"propertyId: {nim_string_literal(property_id)}, "
                    f"propertyKey: {property_entry['key']}.uint64, "
                    f"kind: {NIM_SCALAR_BACKINGS[backing_type]}, "
                    f"required: {generated_bool(property_id in required_map.get(object_id, set()))}, "
                    f"hasDefault: {generated_bool(default is not None)}, "
                    f"defaultValue: {nim_scalar_value_literal(backing_type, default_value)}, "
                    f"equality: {nim_string_literal(equality)}, "
                    f"omitWhenDefault: {generated_bool(default['omitWhenDefault'] if default is not None else False)}, "
                    f"applyOnLoad: {generated_bool(default['applyOnLoad'] if default is not None else False)}),"
                )
        else:
            lines.append(f"const bony{suffix}ScalarSpecs*: array[0, BonyScalarPropertySpec] = []")
        if scalar_properties:
            lines.append("]")
        lines.extend(
            [
                "",
                f"proc encode{suffix}JsonScalars*(properties: openArray[BonyJsonScalarProperty]): seq[BonyJsonScalarProperty] =",
                f"  bonyEncodeJsonScalars(bony{suffix}ScalarSpecs, properties)",
                "",
                f"proc decode{suffix}JsonScalars*(properties: openArray[BonyJsonScalarProperty]): seq[BonyJsonScalarProperty] =",
                f"  bonyDecodeJsonScalars(bony{suffix}ScalarSpecs, properties)",
                "",
                f"proc encode{suffix}BnbScalars*(properties: openArray[BonyBnbScalarProperty]): seq[BonyBnbScalarProperty] =",
                f"  bonyEncodeBnbScalars(bony{suffix}ScalarSpecs, properties)",
                "",
                f"proc decode{suffix}BnbScalars*(properties: openArray[BonyBnbScalarProperty]): seq[BonyBnbScalarProperty] =",
                f"  bonyDecodeBnbScalars(bony{suffix}ScalarSpecs, properties)",
                "",
            ]
        )

    lines.extend(
        [
            "proc encodeBonyObjectJsonScalars*(typeId: string; properties: openArray[BonyJsonScalarProperty]): seq[BonyJsonScalarProperty] =",
            "  discard bonyObjectSpec(typeId)",
            "  case typeId",
        ]
    )
    for object_id in scalar_object_ids:
        suffix = nim_identifier_suffix(object_id)
        lines.append(f"  of {nim_string_literal(object_id)}: encode{suffix}JsonScalars(properties)")
    lines.extend(
        [
            "  else: @[]",
            "",
            "proc decodeBonyObjectJsonScalars*(typeId: string; properties: openArray[BonyJsonScalarProperty]): seq[BonyJsonScalarProperty] =",
            "  discard bonyObjectSpec(typeId)",
            "  case typeId",
        ]
    )
    for object_id in scalar_object_ids:
        suffix = nim_identifier_suffix(object_id)
        lines.append(f"  of {nim_string_literal(object_id)}: decode{suffix}JsonScalars(properties)")
    lines.extend(
        [
            "  else: @[]",
            "",
            "proc encodeBonyObjectBnbScalars*(typeKey: uint64; properties: openArray[BonyBnbScalarProperty]): seq[BonyBnbScalarProperty] =",
            "  case typeKey",
        ]
    )
    for object_id in scalar_object_ids:
        suffix = nim_identifier_suffix(object_id)
        lines.append(f"  of {type_key_by_id[object_id]}.uint64: encode{suffix}BnbScalars(properties)")
    lines.extend(
        [
            "  else:",
            "    for item in bonyTypeKeys:",
            "      if item.key == typeKey:",
            "        return @[]",
            "    raise newException(ValueError, \"unknown bony object type key: \" & $typeKey)",
            "",
            "proc decodeBonyObjectBnbScalars*(typeKey: uint64; properties: openArray[BonyBnbScalarProperty]): seq[BonyBnbScalarProperty] =",
            "  case typeKey",
        ]
    )
    for object_id in scalar_object_ids:
        suffix = nim_identifier_suffix(object_id)
        lines.append(f"  of {type_key_by_id[object_id]}.uint64: decode{suffix}BnbScalars(properties)")
    lines.extend(
        [
            "  else:",
            "    for item in bonyTypeKeys:",
            "      if item.key == typeKey:",
            "        return @[]",
            "    raise newException(ValueError, \"unknown bony object type key: \" & $typeKey)",
            "",
        ]
    )
    return lines


def generate_nim(registry: dict[str, Any], defaults: dict[str, Any]) -> str:
    spec = TargetLangSpec(
        comment_prefix="##",
        declarations=(
            "type",
            "  BonyBackingType* = object",
            "    id*: string",
            "    code*: uint8",
            "  BonyTypeKey* = object",
            "    id*: string",
            "    key*: uint64",
            "  BonyPropertyKey* = object",
            "    id*: string",
            "    key*: uint64",
            "    backingType*: string",
            "  BonyObjectSpec* = object",
            "    typeId*: string",
            "    properties*: seq[string]",
            "  BonyPropertyDefault* = object",
            "    objectId*: string",
            "    propertyId*: string",
            "    equality*: string",
            "    value*: string",
            "    omitWhenDefault*: bool",
            "    applyOnLoad*: bool",
            "  BonyRequiredProperty* = object",
            "    objectId*: string",
            "    propertyId*: string",
            "    reason*: string",
            "",
        ),
        registry_version_line=lambda version: f"const bonyRegistryVersion* = {version}",
        backing_types_start="const bonyBackingTypes* = [",
        backing_types_end="]",
        type_key_prefix_lines=lambda _entries: [],
        type_keys_start="const bonyTypeKeys* = [",
        type_keys_end="]",
        property_key_prefix_lines=lambda _entries: [],
        property_keys_start="const bonyPropertyKeys* = [",
        property_keys_end="]",
        object_specs_start="let bonyObjectSpecs*: seq[BonyObjectSpec] = @[",
        object_specs_end="]",
        property_defaults_start="const bonyPropertyDefaults* = [",
        property_defaults_end="]",
        required_properties_start="const bonyRequiredProperties* = [",
        required_properties_end="]",
        object_properties_literal=lambda properties: "@["
        + ", ".join(nim_string_literal(property_id) for property_id in properties)
        + "]",
        json_text_literal=lambda value: nim_string_literal(canonical_json_value(value)),
        string_literal=nim_string_literal,
        bool_literal=generated_bool,
        backing_type_record=lambda entry: (
            f"  BonyBackingType(id: {nim_string_literal(entry['id'])}, code: {entry['code']}.uint8),"
        ),
        type_key_record=lambda entry: (
            f"  BonyTypeKey(id: {nim_string_literal(entry['id'])}, key: {entry['key']}.uint64),"
        ),
        property_key_record=lambda entry: (
            f"  BonyPropertyKey(id: {nim_string_literal(entry['id'])}, key: {entry['key']}.uint64, "
            f"backingType: {nim_string_literal(entry['backingType'])}),"
        ),
        object_spec_record=lambda entry, properties: (
            f"  BonyObjectSpec(typeId: {nim_string_literal(entry['type'])}, properties: {properties}),"
        ),
        property_default_record=lambda object_id, property_id, equality, value, omit, apply: (
            f"  BonyPropertyDefault(objectId: {nim_string_literal(object_id)}, "
            f"propertyId: {nim_string_literal(property_id)}, "
            f"equality: {nim_string_literal(equality)}, "
            f"value: {value}, "
            f"omitWhenDefault: {omit}, "
            f"applyOnLoad: {apply}),"
        ),
        required_property_record=lambda entry, reason: (
            f"  BonyRequiredProperty(objectId: {nim_string_literal(entry['object'])}, "
            f"propertyId: {nim_string_literal(entry['property'])}, reason: {reason}),"
        ),
        trailer=(
            "",
            "proc bonyObjectSpec*(typeId: string): BonyObjectSpec =",
            "  for spec in bonyObjectSpecs:",
            "    if spec.typeId == typeId:",
            "      return spec",
            "  raise newException(ValueError, \"unknown bony object type: \" & typeId)",
            *nim_scalar_codec_lines(registry, defaults),
            "proc encodeBonyObject*(typeId: string) =",
            "  discard bonyObjectSpec(typeId)",
            "  raise newException(CatchableError, \"generated encodeBonyObject has no registered fields yet\")",
            "",
            "proc decodeBonyObject*(typeId: string) =",
            "  discard bonyObjectSpec(typeId)",
            "  raise newException(CatchableError, \"generated decodeBonyObject has no registered fields yet\")",
            "",
        ),
    )
    return emit_runtime_metadata(registry, defaults, spec)


def generate_dart(registry: dict[str, Any], defaults: dict[str, Any]) -> str:
    type_keys = require_list(registry, "typeKeys")
    property_keys = require_list(registry, "propertyKeys")
    type_const_names = dart_const_names(type_keys, "bonyTypeKey", "type key")
    property_const_names = dart_const_names(property_keys, "bonyPropertyKey", "property key")
    spec = TargetLangSpec(
        comment_prefix="//",
        declarations=(
            "class BonyBackingType {",
            "  const BonyBackingType({required this.id, required this.code});",
            "  final String id;",
            "  final int code;",
            "}",
            "",
            "class BonyTypeKey {",
            "  const BonyTypeKey({required this.id, required this.key});",
            "  final String id;",
            "  final int key;",
            "}",
            "",
            "class BonyPropertyKey {",
            "  const BonyPropertyKey({",
            "    required this.id,",
            "    required this.key,",
            "    required this.backingType,",
            "  });",
            "  final String id;",
            "  final int key;",
            "  final String backingType;",
            "}",
            "",
            "class BonyObjectSpec {",
            "  const BonyObjectSpec({required this.typeId, required this.properties});",
            "  final String typeId;",
            "  final List<String> properties;",
            "}",
            "",
            "class BonyPropertyDefault {",
            "  const BonyPropertyDefault({",
            "    required this.objectId,",
            "    required this.propertyId,",
            "    required this.equality,",
            "    required this.value,",
            "    required this.omitWhenDefault,",
            "    required this.applyOnLoad,",
            "  });",
            "  final String objectId;",
            "  final String propertyId;",
            "  final String equality;",
            "  final String value;",
            "  final bool omitWhenDefault;",
            "  final bool applyOnLoad;",
            "}",
            "",
            "class BonyRequiredProperty {",
            "  const BonyRequiredProperty({",
            "    required this.objectId,",
            "    required this.propertyId,",
            "    required this.reason,",
            "  });",
            "  final String objectId;",
            "  final String propertyId;",
            "  final String reason;",
            "}",
            "",
        ),
        registry_version_line=lambda version: f"const int bonyRegistryVersion = {version};",
        backing_types_start="const List<BonyBackingType> bonyBackingTypes = [",
        backing_types_end="];",
        type_key_prefix_lines=lambda entries: [
            "",
            "// Registry-derived type keys for compile-time loader use.",
            *[f"const int {type_const_names[entry['id']]} = {entry['key']};" for entry in entries],
            "",
        ],
        type_keys_start="const List<BonyTypeKey> bonyTypeKeys = [",
        type_keys_end="];",
        property_key_prefix_lines=lambda entries: [
            "",
            "// Registry-derived property keys for compile-time loader use.",
            *[f"const int {property_const_names[entry['id']]} = {entry['key']};" for entry in entries],
            "",
        ],
        property_keys_start="const List<BonyPropertyKey> bonyPropertyKeys = [",
        property_keys_end="];",
        object_specs_start="const List<BonyObjectSpec> bonyObjectSpecs = [",
        object_specs_end="];",
        property_defaults_start="const List<BonyPropertyDefault> bonyPropertyDefaults = [",
        property_defaults_end="];",
        required_properties_start="const List<BonyRequiredProperty> bonyRequiredProperties = [",
        required_properties_end="];",
        object_properties_literal=lambda properties: "["
        + ", ".join(dart_string_literal(property_id) for property_id in properties)
        + "]",
        json_text_literal=lambda value: dart_string_literal(canonical_json_value(value)),
        string_literal=dart_string_literal,
        bool_literal=generated_bool,
        backing_type_record=lambda entry: (
            f"  BonyBackingType(id: {dart_registry_string_literal(entry['id'])}, code: {entry['code']}),"
        ),
        type_key_record=lambda entry: (
            f"  BonyTypeKey(id: {dart_registry_string_literal(entry['id'])}, key: {type_const_names[entry['id']]}),"
        ),
        property_key_record=lambda entry: (
            f"  BonyPropertyKey(id: {dart_registry_string_literal(entry['id'])}, "
            f"key: {property_const_names[entry['id']]}, "
            f"backingType: {dart_registry_string_literal(entry['backingType'])}),"
        ),
        object_spec_record=lambda entry, properties: (
            f"  BonyObjectSpec(typeId: {dart_registry_string_literal(entry['type'])}, properties: {properties}),"
        ),
        property_default_record=lambda object_id, property_id, equality, value, omit, apply: (
            f"  BonyPropertyDefault(objectId: {dart_registry_string_literal(object_id)}, "
            f"propertyId: {dart_registry_string_literal(property_id)}, "
            f"equality: {dart_registry_string_literal(equality)}, "
            f"value: {value}, "
            f"omitWhenDefault: {omit}, "
            f"applyOnLoad: {apply}),"
        ),
        required_property_record=lambda entry, reason: (
            f"  BonyRequiredProperty(objectId: {dart_registry_string_literal(entry['object'])}, "
            f"propertyId: {dart_registry_string_literal(entry['property'])}, reason: {reason}),"
        ),
        trailer=(
            "",
            "BonyObjectSpec bonyObjectSpec(String typeId) {",
            "  return bonyObjectSpecs.firstWhere(",
            "    (spec) => spec.typeId == typeId,",
            "    orElse: () => throw ArgumentError.value(typeId, 'typeId', 'unknown bony object type'),",
            "  );",
            "}",
            "",
            "Never encodeBonyObject(String typeId) {",
            "  bonyObjectSpec(typeId);",
            "  throw UnsupportedError('generated encodeBonyObject has no registered fields yet');",
            "}",
            "",
            "Never decodeBonyObject(String typeId) {",
            "  bonyObjectSpec(typeId);",
            "  throw UnsupportedError('generated decodeBonyObject has no registered fields yet');",
            "}",
            "",
        ),
    )
    return emit_runtime_metadata(registry, defaults, spec)


def property_backing_type(registry: dict[str, Any], property_id: str) -> str:
    for entry in require_list(registry, "propertyKeys"):
        if entry["id"] == property_id:
            return entry["backingType"]
    raise SourceError(f"unknown property id {property_id}")


def canonical_json_value(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def nim_json_text(value: Any) -> str:
    return escape_string(json.dumps(value, sort_keys=True, separators=(",", ":")))


def escape_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("'", "\\'")


def nim_string_literal(value: str) -> str:
    return '"' + escape_string(value) + '"'


def dart_string_literal(value: str) -> str:
    return json.dumps(value).replace("$", r"\$")


def dart_registry_string_literal(value: str) -> str:
    return "'" + escape_string(value) + "'"


def dart_const_suffix(identifier: str) -> str:
    if not identifier:
        raise SourceError("Dart const identifier suffix must not be empty")
    suffix = identifier[0].upper() + identifier[1:]
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", suffix):
        raise SourceError(f"registry id {identifier!r} cannot form a Dart const suffix")
    return suffix


def dart_const_names(entries: list[dict[str, Any]], prefix: str, label: str) -> dict[str, str]:
    result: dict[str, str] = {}
    seen: dict[str, str] = {}
    for entry in entries:
        identifier = entry.get("id")
        if not isinstance(identifier, str) or not identifier:
            raise SourceError(f"{label} id must be a non-empty string")
        name = prefix + dart_const_suffix(identifier)
        previous = seen.get(name)
        if previous is not None:
            raise SourceError(
                f"duplicate generated Dart const name {name!r} for {label} ids "
                f"{previous!r} and {identifier!r}"
            )
        seen[name] = identifier
        result[identifier] = name
    return result


def generated_bool(value: bool) -> str:
    return "true" if value else "false"


def write_or_check(path: Path, content: str, check: bool, changed: list[Path]) -> None:
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return
    if check:
        changed.append(path)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if generated outputs are stale")
    args = parser.parse_args()

    try:
        registry = load_yaml_subset(REGISTRY_PATH)
        defaults = load_yaml_subset(DEFAULTS_PATH)
        validate_sources(registry, defaults)
        changed: list[Path] = []
        write_or_check(SCHEMA_PATH, generate_schema(registry, defaults), args.check, changed)
        write_or_check(WIRE_SCHEMA_PATH, generate_wire_schema(registry, defaults), args.check, changed)
        write_or_check(NIM_WIRE_PATH, generate_nim(registry, defaults), args.check, changed)
        write_or_check(DART_WIRE_PATH, generate_dart(registry, defaults), args.check, changed)
    except SourceError as exc:
        print(f"codegen: {exc}", file=sys.stderr)
        return 1

    if changed:
        print("stale generated files:", file=sys.stderr)
        for path in changed:
            print(f"  {path.relative_to(ROOT)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
