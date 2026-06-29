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
from typing import Any


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
}


class SourceError(ValueError):
    pass


@dataclass
class Line:
    indent: int
    text: str


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


def generate_schema(registry: dict[str, Any], defaults: dict[str, Any]) -> str:
    schema = json.loads(generate_wire_schema(registry, defaults))
    schema["$id"] = "https://bony.local/spec/bony.schema.json"
    schema["title"] = "bony JSON"
    schema["description"] = (
        "Generated canonical .bony JSON schema from registry/wire.yml and spec/defaults.yml."
    )
    schema["$defs"].update(canonical_json_overrides())

    root_properties: dict[str, Any] = {}
    required_root: list[str] = []
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
        "warpLattice",
        "rotationDeformer",
        "keyformBlend",
        "keyform",
    }
    root_collection_overrides = {
        "animationClip": "animations",
        "stateMachine": "stateMachines",
    }
    for entry in require_list(registry, "typeKeys"):
        object_id = entry["id"]
        if object_id in hidden_binary_children:
            continue
        if object_id == "skeleton":
            root_properties["skeleton"] = {"$ref": "#/$defs/skeleton"}
            required_root.append("skeleton")
            continue
        collection_id = root_collection_overrides.get(object_id, object_id + "s")
        root_properties[collection_id] = {
            "type": "array",
            "items": {"$ref": f"#/$defs/{object_id}"},
        }
        if object_id == "bone":
            required_root.append(collection_id)

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

    root_properties: dict[str, Any] = {}
    required_root: list[str] = []
    for entry in type_keys:
        object_id = entry["id"]
        if object_id == "skeleton":
            root_properties["skeleton"] = {"$ref": "#/$defs/skeleton"}
            required_root.append("skeleton")
        else:
            collection_id = object_id + "s"
            root_properties[collection_id] = {
                "type": "array",
                "items": {"$ref": f"#/$defs/{object_id}"},
            }
            if object_id == "bone":
                required_root.append(collection_id)

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
    return {
        "ikConstraint": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "name": named_string,
                "bones": {"type": "array", "minItems": 1, "items": named_string},
                "target": {"type": "string"},
                "order": {"type": "integer", "default": 0},
                "mix": {"type": "number", "minimum": 0, "maximum": 1, "default": 1.0},
                "bendPositive": {"type": "boolean", "default": True},
            },
            "required": ["bones", "name", "target"],
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
                "kind": {"type": "string", "enum": ["stateEnter", "stateExit", "transition"]},
                "layer": named_string,
                "fromState": named_string,
                "toState": named_string,
            },
            "required": ["kind", "layer", "name"],
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
    if property_id in {"width", "height"}:
        schema["minimum"] = 0
    if property_id in {"position", "translateMix", "rotateMix"}:
        schema["minimum"] = 0
        schema["maximum"] = 1
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


def generate_nim(registry: dict[str, Any], defaults: dict[str, Any]) -> str:
    backing_types = require_list(registry, "backingTypes")
    type_keys = require_list(registry, "typeKeys")
    property_keys = require_list(registry, "propertyKeys")
    objects = require_list(registry, "objects")
    object_defaults = require_list(defaults, "objectDefaults")
    required_properties = require_list(defaults, "requiredProperties")
    lines = [
        "## Generated by codegen/generate.py; do not edit by hand.",
        "",
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
        "const bonyRegistryVersion* = " + str(registry["registryVersion"]),
        "const bonyBackingTypes* = [",
    ]
    for entry in backing_types:
        lines.append(f'  BonyBackingType(id: "{entry["id"]}", code: {entry["code"]}.uint8),')
    lines.extend(["]", "const bonyTypeKeys* = ["])
    for entry in type_keys:
        lines.append(f'  BonyTypeKey(id: "{entry["id"]}", key: {entry["key"]}.uint64),')
    lines.extend(["]", "const bonyPropertyKeys* = ["])
    for entry in property_keys:
        lines.append(
            f'  BonyPropertyKey(id: "{entry["id"]}", key: {entry["key"]}.uint64, '
            f'backingType: "{entry["backingType"]}"),'
        )
    lines.extend(["]", "let bonyObjectSpecs*: seq[BonyObjectSpec] = @["])
    for entry in objects:
        properties = ", ".join(nim_string_literal(property_id) for property_id in entry["properties"])
        lines.append(f'  BonyObjectSpec(typeId: "{entry["type"]}", properties: @[{properties}]),')
    lines.extend(["]", "const bonyPropertyDefaults* = ["])
    for entry in object_defaults:
        object_id = entry["object"]
        for property_id, default in entry.get("properties", {}).items():
            equality = default.get("equality") or inferred_equality_mode(
                property_backing_type(registry, property_id)
            )
            lines.append(
                f'  BonyPropertyDefault(objectId: "{object_id}", propertyId: "{property_id}", '
                f'equality: "{equality}", '
                f'value: "{nim_json_text(default["value"])}", '
                f'omitWhenDefault: {generated_bool(default["omitWhenDefault"])}, '
                f'applyOnLoad: {generated_bool(default["applyOnLoad"])}),'
            )
    lines.extend(["]", "const bonyRequiredProperties* = ["])
    for entry in required_properties:
        lines.append(
            f'  BonyRequiredProperty(objectId: "{entry["object"]}", propertyId: "{entry["property"]}", '
            f'reason: "{escape_string(entry["reason"])}"),'
        )
    lines.extend(
        [
            "]",
            "",
            "proc bonyObjectSpec*(typeId: string): BonyObjectSpec =",
            "  for spec in bonyObjectSpecs:",
            "    if spec.typeId == typeId:",
            "      return spec",
            "  raise newException(ValueError, \"unknown bony object type: \" & typeId)",
            "",
            "proc encodeBonyObject*(typeId: string) =",
            "  discard bonyObjectSpec(typeId)",
            "  raise newException(CatchableError, "
            "\"generated encodeBonyObject has no registered fields yet\")",
            "",
            "proc decodeBonyObject*(typeId: string) =",
            "  discard bonyObjectSpec(typeId)",
            "  raise newException(CatchableError, "
            "\"generated decodeBonyObject has no registered fields yet\")",
            "",
        ]
    )
    return "\n".join(lines)


def generate_dart(registry: dict[str, Any], defaults: dict[str, Any]) -> str:
    backing_types = require_list(registry, "backingTypes")
    type_keys = require_list(registry, "typeKeys")
    property_keys = require_list(registry, "propertyKeys")
    objects = require_list(registry, "objects")
    object_defaults = require_list(defaults, "objectDefaults")
    required_properties = require_list(defaults, "requiredProperties")
    lines = [
        "// Generated by codegen/generate.py; do not edit by hand.",
        "",
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
        f"const int bonyRegistryVersion = {registry['registryVersion']};",
        "const List<BonyBackingType> bonyBackingTypes = [",
    ]
    for entry in backing_types:
        lines.append(f"  BonyBackingType(id: '{entry['id']}', code: {entry['code']}),")
    lines.extend(["];", "const List<BonyTypeKey> bonyTypeKeys = ["])
    for entry in type_keys:
        lines.append(f"  BonyTypeKey(id: '{entry['id']}', key: {entry['key']}),")
    lines.extend(["];", "const List<BonyPropertyKey> bonyPropertyKeys = ["])
    for entry in property_keys:
        lines.append(
            f"  BonyPropertyKey(id: '{entry['id']}', key: {entry['key']}, "
            f"backingType: '{entry['backingType']}'),"
        )
    lines.extend(["];", "const List<BonyObjectSpec> bonyObjectSpecs = ["])
    for entry in objects:
        properties = ", ".join(dart_string_literal(property_id) for property_id in entry["properties"])
        lines.append(f"  BonyObjectSpec(typeId: '{entry['type']}', properties: [{properties}]),")
    lines.extend(["];", "const List<BonyPropertyDefault> bonyPropertyDefaults = ["])
    for entry in object_defaults:
        object_id = entry["object"]
        for property_id, default in entry.get("properties", {}).items():
            equality = default.get("equality") or inferred_equality_mode(
                property_backing_type(registry, property_id)
            )
            lines.append(
                f"  BonyPropertyDefault(objectId: '{object_id}', propertyId: '{property_id}', "
                f"equality: '{equality}', "
                f"value: {dart_string_literal(canonical_json_value(default['value']))}, "
                f"omitWhenDefault: {generated_bool(default['omitWhenDefault'])}, "
                f"applyOnLoad: {generated_bool(default['applyOnLoad'])}),"
            )
    lines.extend(["];", "const List<BonyRequiredProperty> bonyRequiredProperties = ["])
    for entry in required_properties:
        lines.append(
            f"  BonyRequiredProperty(objectId: '{entry['object']}', propertyId: '{entry['property']}', "
            f"reason: {dart_string_literal(entry['reason'])}),"
        )
    lines.extend(
        [
            "];",
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
        ]
    )
    return "\n".join(lines)


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
