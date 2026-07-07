from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
from typing import Any, cast

from .schema_types import ObjectEntry, PropertyKeyEntry, SourceError, TypeKeyEntry
from .validate import require_list


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

TRANSFORM_MODE_ENUM = [
    "normal",
    "onlyTranslation",
    "noRotationOrReflection",
    "noScale",
    "noScaleOrReflection",
]

PROPERTY_SCHEMA_OVERRIDES: dict[str, dict[str, Any]] = {
    "name": {"minLength": 1},
    "transformMode": {"enum": TRANSFORM_MODE_ENUM},
    "width": {"minimum": 0},
    "height": {"minimum": 0},
    "mass": {"minimum": 0},
    "position": {"minimum": 0, "maximum": 1},
    "translateMix": {"minimum": 0, "maximum": 1},
    "rotateMix": {"minimum": 0, "maximum": 1},
    "scaleMix": {"minimum": 0, "maximum": 1},
    "shearMix": {"minimum": 0, "maximum": 1},
    "mix": {"minimum": 0, "maximum": 1},
    "physicsMix": {"minimum": 0, "maximum": 1},
    # Physics enabled-channel bitmask: at least one bit set, no bit beyond the
    # five PhysicsChannel ordinals (pcX..pcShearX). Matches the loader, which
    # rejects an empty mask and any bit >= 1 << 5.
    "channels": {"minimum": 1, "maximum": 31},
}

CANONICAL_JSON_OVERRIDES_PATH = Path(__file__).with_name("canonical_json_overrides.json")
_CANONICAL_JSON_OVERRIDES = json.loads(CANONICAL_JSON_OVERRIDES_PATH.read_text(encoding="utf-8"))


def canonical_json_overrides() -> dict[str, Any]:
    return deepcopy(_CANONICAL_JSON_OVERRIDES)


def build_root_properties(
    type_keys: list[TypeKeyEntry],
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
        cast(list[TypeKeyEntry], require_list(registry, "typeKeys")),
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
    type_keys = cast(list[TypeKeyEntry], require_list(registry, "typeKeys"))
    property_keys = cast(list[PropertyKeyEntry], require_list(registry, "propertyKeys"))
    objects = cast(list[ObjectEntry], require_list(registry, "objects"))
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
    override = PROPERTY_SCHEMA_OVERRIDES.get(property_id)
    if override is not None:
        schema.update(deepcopy(override))
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
