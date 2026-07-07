from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, NotRequired, TypedDict


class SourceError(ValueError):
    pass


@dataclass
class Line:
    indent: int
    text: str


class TypeKeyEntry(TypedDict):
    id: str
    key: NotRequired[int]
    status: NotRequired[str]
    milestone: NotRequired[str]
    ownerBead: NotRequired[str]


class PropertyKeyEntry(TypedDict):
    id: str
    key: int
    backingType: str
    status: NotRequired[str]
    milestone: NotRequired[str]
    ownerBead: NotRequired[str]


class ObjectEntry(TypedDict):
    type: str
    properties: list[str]


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
    ordinal_enums_start: str
    ordinal_enums_end: str
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
    ordinal_enum_record: Callable[[dict[str, Any], str], str]
    trailer: tuple[str, ...]
