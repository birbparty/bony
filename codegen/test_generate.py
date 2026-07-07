#!/usr/bin/env python3
"""Unit tests for the bony generator source validation."""

from __future__ import annotations

import sys
import json
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate


M3_M8_OBJECTS = [
    "animationClip",
    "boneTimeline",
    "slotTimeline",
    "stateMachine",
    "stateMachineInput",
    "stateMachineLayer",
    "stateMachineState",
    "stateMachineBlendClip",
    "stateMachineTransition",
    "stateMachineCondition",
    "stateMachineListener",
]

M3_M8_TYPE_KEYS = {
    "animationClip": 2000,
    "boneTimeline": 2001,
    "slotTimeline": 2002,
    "stateMachine": 7000,
    "stateMachineInput": 7001,
    "stateMachineLayer": 7002,
    "stateMachineState": 7003,
    "stateMachineBlendClip": 7004,
    "stateMachineTransition": 7005,
    "stateMachineCondition": 7006,
    "stateMachineListener": 7007,
}

M3_M8_PROPERTY_KEYS = {
    "boneIndex": 2000,
    "boneTimelineKind": 2001,
    "slotIndex": 2002,
    "slotTimelineKind": 2003,
    "timelineKeys": 2004,
    "stateMachineInputKind": 7000,
    "inputDefaultBool": 7001,
    "inputDefaultNumber": 7002,
    "initialStateIndex": 7010,
    "stateMachineStateKind": 7020,
    "stateClipIndex": 7021,
    "stateLoop": 7022,
    "stateBlendInputIndex": 7023,
    "blendClipAnimationIndex": 7030,
    "blendClipValue": 7031,
    "blendClipLoop": 7032,
    "transitionFromStateIndex": 7040,
    "transitionToStateIndex": 7041,
    "conditionInputIndex": 7050,
    "stateMachineConditionKind": 7051,
    "conditionBoolValue": 7052,
    "conditionNumberValue": 7053,
    "stateMachineListenerKind": 7060,
    "listenerLayerIndex": 7061,
    "listenerFromStateIndex": 7062,
    "listenerToStateIndex": 7063,
    "listenerSlotIndex": 7064,
    "listenerHelperKind": 7065,
    "listenerHelperTarget": 7066,
    "listenerInputIndex": 7067,
    "listenerBoolValue": 7068,
    "listenerNumberValue": 7069,
    "listenerHitRadius": 7070,
}

M4_SKIN_TYPE_KEYS = {
    "skin": 3003,
    "skinEntry": 3004,
}

M4_SKIN_PROPERTY_KEYS = {
    "skinAttachment": 3010,
    "skinTarget": 3011,
}


def sample_registry() -> dict:
    return {
        "format": "bony-wire-registry",
        "registryVersion": 1,
        "keyRanges": {
            "canonicalMilestoneTokens": ["M1", "M2"],
            "appliesTo": ["typeKeys", "propertyKeys"],
            "spacesAreIndependent": True,
            "bands": [
                {"milestone": "M1", "first": 1, "last": 999, "scope": "test"},
                {"milestone": "M2", "first": 1000, "last": 1999, "scope": "test"},
            ],
        },
        "backingTypes": [
            {"id": "varuint", "code": 1, "skipRule": "read"},
            {"id": "bool", "code": 4, "skipRule": "read"},
            {"id": "string", "code": 5, "skipRule": "read"},
        ],
        "typeKeys": [
            {"id": "bone", "key": 1, "status": "active", "milestone": "M1", "ownerBead": "test"},
        ],
        "propertyKeys": [
            {
                "id": "name",
                "key": 1,
                "backingType": "string",
                "status": "active",
                "milestone": "M1",
                "ownerBead": "test",
            },
            {
                "id": "visible",
                "key": 2,
                "backingType": "bool",
                "status": "active",
                "milestone": "M1",
                "ownerBead": "test",
            },
        ],
        "objects": [{"type": "bone", "properties": ["name", "visible"]}],
    }


def sample_defaults() -> dict:
    return {
        "format": "bony-default-table",
        "defaultsVersion": 1,
        "equalityModes": [
            {"id": "exactBool", "appliesTo": ["bool"]},
            {"id": "exactString", "appliesTo": ["string"]},
        ],
        "objectDefaults": [
            {
                "object": "bone",
                "ownerBead": "test",
                "properties": {
                    "name": {"value": "root#1", "omitWhenDefault": False, "applyOnLoad": True},
                    "visible": {
                        "value": True,
                        "omitWhenDefault": True,
                        "applyOnLoad": True,
                        "equality": "exactBool",
                    },
                },
            }
        ],
        "requiredProperties": [],
    }


class GeneratorValidationTests(unittest.TestCase):
    def assert_subsequence(self, expected: list[str], actual: list[str]) -> None:
        position = -1
        for item in expected:
            try:
                position = actual.index(item, position + 1)
            except ValueError:
                self.fail(f"{item!r} missing after index {position} in {actual!r}")

    def project_sources(self) -> tuple[dict, dict]:
        registry = generate.load_yaml_subset(generate.ROOT / "registry" / "wire.yml")
        defaults = generate.load_yaml_subset(generate.ROOT / "spec" / "defaults.yml")
        return registry, defaults

    def test_valid_non_empty_sources_generate_runtime_metadata(self) -> None:
        registry = sample_registry()
        defaults = sample_defaults()

        generate.validate_sources(registry, defaults)

        self.assertIn("BonyObjectSpec", generate.generate_nim(registry, defaults))
        self.assertIn("BonyObjectSpec", generate.generate_dart(registry, defaults))
        schema_text = generate.generate_schema(registry, defaults)
        schema = json.loads(schema_text)
        self.assertEqual(schema["$id"], "https://bony.local/spec/bony.schema.json")
        self.assertEqual(list(schema["properties"].keys()), ["bones"])
        self.assertEqual(schema["required"], ["bones"])
        self.assertFalse(schema["$defs"]["bone"]["additionalProperties"])
        self.assertEqual(schema["$defs"]["bone"]["properties"]["name"]["minLength"], 1)

        wire_schema = json.loads(generate.generate_wire_schema(registry, defaults))
        self.assertEqual(wire_schema["$id"], "https://bony.local/spec/bony-wire.schema.json")
        self.assertEqual(list(wire_schema["properties"].keys()), ["bones"])

    def test_project_schema_contains_m2_runtime_constraints(self) -> None:
        registry, defaults = self.project_sources()

        schema = json.loads(generate.generate_schema(registry, defaults))

        self.assertEqual(
            schema["$defs"]["bone"]["properties"]["transformMode"]["enum"],
            [
                "normal",
                "onlyTranslation",
                "noRotationOrReflection",
                "noScale",
                "noScaleOrReflection",
            ],
        )
        self.assertEqual(schema["$defs"]["region"]["properties"]["width"]["minimum"], 0)
        self.assertIn("allOf", schema["$defs"]["bone"])
        self.assertEqual(schema["required"], ["skeleton", "bones"])
        self.assertIn("animations", schema["properties"])
        self.assertIn("stateMachines", schema["properties"])
        self.assertNotIn("animationClips", schema["properties"])
        self.assertNotIn("boneTimelines", schema["properties"])
        self.assertNotIn("stateMachineInputs", schema["properties"])
        self.assertNotIn("warpLattices", schema["properties"])
        self.assertNotIn("keyformBlends", schema["properties"])
        self.assertIn("min", schema["$defs"]["parameter"]["properties"])
        self.assertNotIn("parameterMin", schema["$defs"]["parameter"]["properties"])
        self.assertIn("warp", schema["$defs"]["deformer"]["properties"])
        self.assertIn("boneTimelines", schema["$defs"]["animationClip"]["properties"])
        self.assertIn("layers", schema["$defs"]["stateMachine"]["properties"])

    def test_project_m3_m8_keys_are_in_reserved_bands(self) -> None:
        registry, defaults = self.project_sources()
        generate.validate_sources(registry, defaults)

        type_keys = {entry["id"]: entry["key"] for entry in registry["typeKeys"]}
        property_keys = {entry["id"]: entry["key"] for entry in registry["propertyKeys"]}

        self.assertEqual({key: type_keys[key] for key in M3_M8_TYPE_KEYS}, M3_M8_TYPE_KEYS)
        self.assertEqual(
            {key: property_keys[key] for key in M3_M8_PROPERTY_KEYS},
            M3_M8_PROPERTY_KEYS,
        )
        self.assertTrue(
            all(2000 <= type_keys[key] <= 2999 for key in ["animationClip", "boneTimeline", "slotTimeline"])
        )
        self.assertTrue(
            all(7000 <= type_keys[key] <= 7999 for key in M3_M8_TYPE_KEYS if key.startswith("stateMachine"))
        )
        m3_property_ids = {
            "boneIndex",
            "boneTimelineKind",
            "slotIndex",
            "slotTimelineKind",
            "timelineKeys",
        }
        self.assertTrue(all(2000 <= property_keys[key] <= 2999 for key in m3_property_ids))
        self.assertTrue(
            all(7000 <= property_keys[key] <= 7999 for key in M3_M8_PROPERTY_KEYS if key not in m3_property_ids)
        )

    def test_project_m3_m8_registry_entries_are_append_only(self) -> None:
        registry, _ = self.project_sources()

        type_ids = [entry["id"] for entry in registry["typeKeys"]]
        property_ids = [entry["id"] for entry in registry["propertyKeys"]]
        object_ids = [entry["type"] for entry in registry["objects"]]

        self.assert_subsequence(M3_M8_OBJECTS, type_ids)
        self.assert_subsequence(list(M3_M8_PROPERTY_KEYS.keys()), property_ids)
        self.assert_subsequence(M3_M8_OBJECTS, object_ids)

    def test_project_m3_m8_defaults_cover_every_property_once(self) -> None:
        registry, defaults = self.project_sources()
        generate.validate_sources(registry, defaults)

        object_properties = {entry["type"]: set(entry["properties"]) for entry in registry["objects"]}
        defaulted = {
            entry["object"]: set((entry.get("properties") or {}).keys())
            for entry in defaults["objectDefaults"]
        }
        required: dict[str, set[str]] = {}
        for entry in defaults["requiredProperties"]:
            required.setdefault(entry["object"], set()).add(entry["property"])

        for object_id in M3_M8_OBJECTS:
            default_set = defaulted.get(object_id, set())
            required_set = required.get(object_id, set())
            self.assertFalse(default_set & required_set, object_id)
            self.assertEqual(default_set | required_set, object_properties[object_id], object_id)

    def test_project_generated_runtime_metadata_exposes_m3_m8_entries(self) -> None:
        registry, defaults = self.project_sources()

        nim = generate.generate_nim(registry, defaults)
        dart = generate.generate_dart(registry, defaults)

        for object_id, key in M3_M8_TYPE_KEYS.items():
            dart_const = f"bonyTypeKey{generate.dart_const_suffix(object_id)}"
            self.assertIn(f'id: "{object_id}", key: {key}.uint64', nim)
            self.assertIn(f"const int {dart_const} = {key};", dart)
            self.assertIn(f"id: '{object_id}', key: {dart_const}", dart)
        for property_id, key in M3_M8_PROPERTY_KEYS.items():
            dart_const = f"bonyPropertyKey{generate.dart_const_suffix(property_id)}"
            self.assertIn(f'id: "{property_id}", key: {key}.uint64', nim)
            self.assertIn(f"const int {dart_const} = {key};", dart)
            self.assertIn(f"id: '{property_id}', key: {dart_const}", dart)
        self.assertIn(
            'BonyObjectSpec(typeId: "boneTimeline", properties: @["boneIndex", "boneTimelineKind", "timelineKeys"])',
            nim,
        )
        self.assertIn(
            'BonyObjectSpec(typeId: "stateMachineState", properties: @["name", "stateMachineStateKind", "stateClipIndex", "stateLoop", "stateBlendInputIndex"])',
            nim,
        )
        self.assertIn(
            'BonyObjectSpec(typeId: "stateMachineListener", properties: @["name", "stateMachineListenerKind", "listenerLayerIndex", "listenerFromStateIndex", "listenerToStateIndex", "listenerSlotIndex", "listenerHelperKind", "listenerHelperTarget", "listenerInputIndex", "listenerBoolValue", "listenerNumberValue", "listenerHitRadius"])',
            nim,
        )
        self.assertIn(
            'BonyObjectSpec(typeId: \'boneTimeline\', properties: ["boneIndex", "boneTimelineKind", "timelineKeys"])',
            dart,
        )
        self.assertIn(
            'BonyObjectSpec(typeId: \'stateMachineState\', properties: ["name", "stateMachineStateKind", "stateClipIndex", "stateLoop", "stateBlendInputIndex"])',
            dart,
        )
        self.assertIn(
            'BonyObjectSpec(typeId: \'stateMachineListener\', properties: ["name", "stateMachineListenerKind", "listenerLayerIndex", "listenerFromStateIndex", "listenerToStateIndex", "listenerSlotIndex", "listenerHelperKind", "listenerHelperTarget", "listenerInputIndex", "listenerBoolValue", "listenerNumberValue", "listenerHitRadius"])',
            dart,
        )

    def test_project_schema_root_orders_animations_before_state_machines(self) -> None:
        registry, defaults = self.project_sources()

        schema = json.loads(generate.generate_schema(registry, defaults))
        root_keys = list(schema["properties"].keys())

        self.assertLess(root_keys.index("animations"), root_keys.index("stateMachines"))
        self.assertNotIn("animationClips", root_keys)
        self.assertNotIn("stateMachineInputs", root_keys)
        self.assertIn("animationClips", json.loads(generate.generate_wire_schema(registry, defaults))["properties"])

    def test_project_schema_exposes_first_class_skins(self) -> None:
        registry, defaults = self.project_sources()

        schema = json.loads(generate.generate_schema(registry, defaults))
        wire = json.loads(generate.generate_wire_schema(registry, defaults))

        self.assertIn("skins", schema["properties"])
        self.assertEqual(schema["properties"]["skins"]["minItems"], 1)
        self.assertEqual(schema["properties"]["skins"]["contains"]["properties"]["name"]["const"], "default")
        self.assertNotIn("skinEntrys", schema["properties"])
        self.assertEqual(schema["$defs"]["skin"]["properties"]["entries"]["items"]["$ref"], "#/$defs/skinEntry")
        self.assertIn("attachment", schema["$defs"]["skinEntry"]["properties"])
        self.assertIn("target", schema["$defs"]["skinEntry"]["properties"])
        self.assertNotIn("skinAttachment", schema["$defs"]["skinEntry"]["properties"])
        self.assertIn("skinEntrys", wire["properties"])

    def test_project_m4_skin_keys_are_in_reserved_band(self) -> None:
        registry, defaults = self.project_sources()
        generate.validate_sources(registry, defaults)

        type_keys = {entry["id"]: entry["key"] for entry in registry["typeKeys"]}
        property_keys = {entry["id"]: entry["key"] for entry in registry["propertyKeys"]}

        self.assertEqual({key: type_keys[key] for key in M4_SKIN_TYPE_KEYS}, M4_SKIN_TYPE_KEYS)
        self.assertEqual(
            {key: property_keys[key] for key in M4_SKIN_PROPERTY_KEYS},
            M4_SKIN_PROPERTY_KEYS,
        )

    def test_project_conformance_assets_validate_against_generated_schema(self) -> None:
        try:
            import jsonschema
        except ModuleNotFoundError:
            self.skipTest("jsonschema is not installed")

        registry, defaults = self.project_sources()
        schema = json.loads(generate.generate_schema(registry, defaults))
        validator = jsonschema.Draft202012Validator(schema)

        asset_paths = sorted((generate.ROOT / "conformance" / "assets").glob("*.bony"))
        self.assertGreater(len(asset_paths), 0)
        for path in asset_paths:
            with self.subTest(path=path.name):
                validator.validate(json.loads(path.read_text(encoding="utf-8")))

    def test_apply_on_load_false_default_is_not_schema_default(self) -> None:
        registry = sample_registry()
        defaults = sample_defaults()
        defaults["objectDefaults"][0]["properties"]["visible"]["applyOnLoad"] = False

        generate.validate_sources(registry, defaults)

        schema = json.loads(generate.generate_schema(registry, defaults))
        self.assertNotIn("default", schema["$defs"]["bone"]["properties"]["visible"])

    def test_project_schema_marks_timeline_keys_as_packed_bytes(self) -> None:
        registry = generate.load_yaml_subset(generate.ROOT / "registry" / "wire.yml")
        defaults = generate.load_yaml_subset(generate.ROOT / "spec" / "defaults.yml")

        schema = json.loads(generate.generate_wire_schema(registry, defaults))
        timeline_keys = schema["$defs"]["boneTimeline"]["properties"]["timelineKeys"]

        self.assertEqual(timeline_keys["contentEncoding"], "base64")
        self.assertEqual(timeline_keys["x-bony-packedBytes"]["payload"], "animationTimelineKeys")
        self.assertEqual(
            timeline_keys["x-bony-packedBytes"]["layout"],
            "docs/binary-animation-state-machine-object-families.md#keyframe-payloads",
        )
        self.assertEqual(timeline_keys["x-bony-packedBytes"]["structuralSchema"], "base64Only")
        self.assertEqual(timeline_keys["x-bony-packedBytes"]["validatedBy"], "loader")

    def test_project_schema_keeps_packed_timeline_keys_out_of_canonical_json(self) -> None:
        registry = generate.load_yaml_subset(generate.ROOT / "registry" / "wire.yml")
        defaults = generate.load_yaml_subset(generate.ROOT / "spec" / "defaults.yml")

        schema = json.loads(generate.generate_schema(registry, defaults))

        self.assertNotIn("timelineKeys", schema["$defs"]["boneTimeline"]["properties"])
        self.assertIn("keyframes", schema["$defs"]["boneTimeline"]["properties"])

    def test_build_root_properties_applies_hidden_ids_and_collection_overrides(self) -> None:
        type_keys = [
            {"id": "skeleton"},
            {"id": "bone"},
            {"id": "animationClip"},
            {"id": "stateMachineInput"},
        ]

        properties, required = generate.build_root_properties(
            type_keys,
            hidden={"stateMachineInput"},
            collection_overrides={"animationClip": "animations"},
        )

        self.assertEqual(required, ["skeleton", "bones"])
        self.assertEqual(properties["skeleton"], {"$ref": "#/$defs/skeleton"})
        self.assertEqual(properties["bones"]["items"], {"$ref": "#/$defs/bone"})
        self.assertEqual(properties["animations"]["items"], {"$ref": "#/$defs/animationClip"})
        self.assertNotIn("stateMachineInputs", properties)

    def test_project_schema_constrains_ik_mix_to_unit_range(self) -> None:
        # Regression guard for the frozen IK format (ik-format-freeze.md §7-C1):
        # ikConstraint.mix must carry [0, 1] in BOTH the canonical schema (via the
        # canonical_json_overrides[ikConstraint] entry) and the wire schema (via the
        # "mix" id in schema_for_property's range set). The two ranges are produced
        # by independent mechanisms, so the wire range can silently disappear if
        # "mix" is dropped from schema_for_property while the override still carries
        # the canonical range. Assert both so neither half can regress unnoticed.
        registry = generate.load_yaml_subset(generate.ROOT / "registry" / "wire.yml")
        defaults = generate.load_yaml_subset(generate.ROOT / "spec" / "defaults.yml")

        canonical = json.loads(generate.generate_schema(registry, defaults))
        wire = json.loads(generate.generate_wire_schema(registry, defaults))

        for label, schema in (("canonical", canonical), ("wire", wire)):
            with self.subTest(schema=label):
                mix = schema["$defs"]["ikConstraint"]["properties"]["mix"]
                self.assertEqual(mix["minimum"], 0)
                self.assertEqual(mix["maximum"], 1)

    def test_invalid_default_type_is_rejected(self) -> None:
        registry = sample_registry()
        defaults = sample_defaults()
        defaults["objectDefaults"][0]["properties"]["visible"]["value"] = "true"

        with self.assertRaisesRegex(generate.SourceError, "must be bool"):
            generate.validate_sources(registry, defaults)

    def test_unknown_equality_mode_is_rejected(self) -> None:
        registry = sample_registry()
        defaults = sample_defaults()
        defaults["objectDefaults"][0]["properties"]["visible"]["equality"] = "approx"

        with self.assertRaisesRegex(generate.SourceError, "unknown equality mode"):
            generate.validate_sources(registry, defaults)

    def test_out_of_range_milestone_key_is_rejected(self) -> None:
        registry = sample_registry()
        defaults = sample_defaults()
        registry["typeKeys"][0]["key"] = 1000

        with self.assertRaisesRegex(generate.SourceError, "outside M1 range"):
            generate.validate_sources(registry, defaults)

    def test_unknown_milestone_token_is_rejected(self) -> None:
        registry = sample_registry()
        defaults = sample_defaults()
        registry["propertyKeys"][0]["milestone"] = "m1"

        with self.assertRaisesRegex(generate.SourceError, "unknown milestone"):
            generate.validate_sources(registry, defaults)

    def test_parser_preserves_quoted_comment_and_comma(self) -> None:
        self.assertEqual(generate.strip_yaml_comment('doc: "a#b" # comment'), 'doc: "a#b" ')
        self.assertEqual(generate.split_inline_list('"a,b", c'), ['"a,b"', " c"])

    def test_parser_rejects_duplicate_mapping_keys(self) -> None:
        lines = [
            generate.Line(0, "format: bony-default-table"),
            generate.Line(0, "format: duplicate"),
        ]

        with self.assertRaisesRegex(generate.SourceError, "duplicate mapping key"):
            generate.parse_map(lines, 0, 0)

    def test_dart_string_literal_escapes_interpolation(self) -> None:
        self.assertEqual(generate.dart_string_literal("price $name"), '"price \\$name"')

    def test_dart_const_suffix_rejects_invalid_identifier_sources(self) -> None:
        with self.assertRaisesRegex(generate.SourceError, "cannot form a Dart const suffix"):
            generate.dart_const_suffix("1bad")

    def test_dart_const_names_reject_generated_name_collisions(self) -> None:
        entries = [
            {"id": "foo", "key": 1},
            {"id": "Foo", "key": 2},
        ]

        with self.assertRaisesRegex(generate.SourceError, "duplicate generated Dart const name"):
            generate.dart_const_names(entries, "bonyTypeKey", "type key")


if __name__ == "__main__":
    unittest.main()
