#!/usr/bin/env python3
"""Generate bony runtime metadata and schema from registry/default sources."""

from __future__ import annotations

import argparse
import ast
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
NIM_WIRE_PATH = ROOT / "runtime-nim" / "src" / "bony" / "generated" / "wire.nim"
DART_WIRE_PATH = ROOT / "runtime-dart" / "lib" / "src" / "generated" / "wire.dart"


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
        text = raw.split("#", 1)[0].rstrip()
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
        return [parse_scalar(part.strip()) for part in text[1:-1].split(",") if part.strip()]
    if text in ("true", "false"):
        return text == "true"
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if re.fullmatch(r"-?\d+\.\d+", text):
        return float(text)
    if (text.startswith('"') and text.endswith('"')) or (text.startswith("'") and text.endswith("'")):
        return ast.literal_eval(text)
    return text


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
            if default.get("omitWhenDefault") is True and default.get("applyOnLoad") is not True:
                raise SourceError(f"default {object_id}.{property_id} omits without applyOnLoad")

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


def generate_schema(registry: dict[str, Any], defaults: dict[str, Any]) -> str:
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
            property_schema = schema_for_backing_type(property_backing[property_id])
            if property_id in default_map.get(object_id, {}):
                property_schema["default"] = default_map[object_id][property_id]["value"]
            properties[property_id] = property_schema
        definitions[object_id] = {
            "type": "object",
            "additionalProperties": False,
            "properties": properties,
            "required": sorted(required_map.get(object_id, [])),
        }

    schema: dict[str, Any] = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://bony.local/spec/bony.schema.json",
        "title": "bony",
        "description": "Generated from registry/wire.yml and spec/defaults.yml.",
        "type": "object",
        "additionalProperties": False,
        "oneOf": [{"$ref": f"#/$defs/{entry['id']}"} for entry in type_keys],
        "$defs": definitions,
    }
    return json.dumps(schema, indent=2, sort_keys=True) + "\n"


def schema_for_backing_type(backing_type: str) -> dict[str, Any]:
    mapping = {
        "varuint": {"type": "integer", "minimum": 0},
        "varint": {"type": "integer"},
        "f32": {"type": "number"},
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


def generate_nim(registry: dict[str, Any], defaults: dict[str, Any]) -> str:
    backing_types = require_list(registry, "backingTypes")
    type_keys = require_list(registry, "typeKeys")
    property_keys = require_list(registry, "propertyKeys")
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
        "  BonyPropertyDefault* = object",
        "    objectId*: string",
        "    propertyId*: string",
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
    lines.extend(["]", "const bonyPropertyDefaults* = ["])
    for entry in object_defaults:
        object_id = entry["object"]
        for property_id, default in entry.get("properties", {}).items():
            lines.append(
                f'  BonyPropertyDefault(objectId: "{object_id}", propertyId: "{property_id}", '
                f'value: "{json_text(default["value"])}", '
                f'omitWhenDefault: {generated_bool(default["omitWhenDefault"])}, '
                f'applyOnLoad: {generated_bool(default["applyOnLoad"])}),'
            )
    lines.extend(["]", "const bonyRequiredProperties* = ["])
    for entry in required_properties:
        lines.append(
            f'  BonyRequiredProperty(objectId: "{entry["object"]}", propertyId: "{entry["property"]}", '
            f'reason: "{escape_string(entry["reason"])}"),'
        )
    lines.extend(["]", ""])
    return "\n".join(lines)


def generate_dart(registry: dict[str, Any], defaults: dict[str, Any]) -> str:
    backing_types = require_list(registry, "backingTypes")
    type_keys = require_list(registry, "typeKeys")
    property_keys = require_list(registry, "propertyKeys")
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
        "class BonyPropertyDefault {",
        "  const BonyPropertyDefault({",
        "    required this.objectId,",
        "    required this.propertyId,",
        "    required this.value,",
        "    required this.omitWhenDefault,",
        "    required this.applyOnLoad,",
        "  });",
        "  final String objectId;",
        "  final String propertyId;",
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
    lines.extend(["];", "const List<BonyPropertyDefault> bonyPropertyDefaults = ["])
    for entry in object_defaults:
        object_id = entry["object"]
        for property_id, default in entry.get("properties", {}).items():
            lines.append(
                f"  BonyPropertyDefault(objectId: '{object_id}', propertyId: '{property_id}', "
                f"value: '{json_text(default['value'])}', "
                f"omitWhenDefault: {generated_bool(default['omitWhenDefault'])}, "
                f"applyOnLoad: {generated_bool(default['applyOnLoad'])}),"
            )
    lines.extend(["];", "const List<BonyRequiredProperty> bonyRequiredProperties = ["])
    for entry in required_properties:
        lines.append(
            f"  BonyRequiredProperty(objectId: '{entry['object']}', propertyId: '{entry['property']}', "
            f"reason: '{escape_string(entry['reason'])}'),"
        )
    lines.extend(["];", ""])
    return "\n".join(lines)


def json_text(value: Any) -> str:
    return escape_string(json.dumps(value, sort_keys=True, separators=(",", ":")))


def escape_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("'", "\\'")


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
