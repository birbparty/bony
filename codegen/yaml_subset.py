from __future__ import annotations

import ast
import re
from pathlib import Path
from typing import Any

from schema_types import Line, SourceError


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
