from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "registry" / "wire.yml"
DEFAULTS_PATH = ROOT / "spec" / "defaults.yml"
SCHEMA_PATH = ROOT / "spec" / "bony.schema.json"
WIRE_SCHEMA_PATH = ROOT / "spec" / "bony-wire.schema.json"
NIM_WIRE_PATH = ROOT / "runtime-nim" / "src" / "bony" / "generated" / "wire.nim"
DART_WIRE_PATH = ROOT / "runtime-dart" / "lib" / "src" / "generated" / "wire.dart"
