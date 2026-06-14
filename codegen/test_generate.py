#!/usr/bin/env python3
"""Unit tests for the bony generator source validation."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate


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
    def test_valid_non_empty_sources_generate_runtime_metadata(self) -> None:
        registry = sample_registry()
        defaults = sample_defaults()

        generate.validate_sources(registry, defaults)

        self.assertIn("BonyObjectSpec", generate.generate_nim(registry, defaults))
        self.assertIn("BonyObjectSpec", generate.generate_dart(registry, defaults))
        self.assertIn('"bones"', generate.generate_schema(registry, defaults))

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


if __name__ == "__main__":
    unittest.main()
