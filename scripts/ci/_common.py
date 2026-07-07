"""Shared scaffolding for bony CI helper scripts."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import glob
import json
import os
import sys


class Outcome(str, Enum):
    PASS = "pass"
    FAIL = "fail"
    SKIP = "skip"


def resolve_bony_bin(path: str) -> str:
    bony_bin = os.path.abspath(path)
    if not os.path.isfile(bony_bin):
        print(f"error: bony binary not found: {bony_bin}", file=sys.stderr)
        sys.exit(2)
    return bony_bin


def require_glob(pattern: str, label: str) -> list[str]:
    paths = sorted(glob.glob(pattern))
    if not paths:
        print(f"error: no {label} found at {pattern}", file=sys.stderr)
        sys.exit(2)
    return paths


def _object_without_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key: {key}")
        result[key] = value
    return result


def load_json_without_duplicate_keys(path: str):
    with open(path) as f:
        return json.load(f, object_pairs_hook=_object_without_duplicate_keys)


@dataclass
class GateTally:
    passed: int = 0
    failed: int = 0
    skipped: int = 0

    def record(self, outcome: Outcome | str) -> None:
        outcome = Outcome(outcome)
        if outcome == Outcome.PASS:
            self.passed += 1
        elif outcome == Outcome.FAIL:
            self.failed += 1
        else:
            self.skipped += 1

    def summary_line(self) -> str:
        return f"{self.passed} passed, {self.failed} failed, {self.skipped} skipped"

    def assert_not_vacuous(self, label: str) -> None:
        if self.passed == 0 and self.failed == 0:
            print(f"error: no {label} were checked — gate is vacuously green", file=sys.stderr)
            sys.exit(2)

    def exit_code(self) -> int:
        return 1 if self.failed else 0
