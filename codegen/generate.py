#!/usr/bin/env python3
"""Generate bony runtime metadata and schema from registry/default sources."""

from __future__ import annotations

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from codegen.cli import main, write_or_check
from codegen.emit import *
from codegen.paths import *
from codegen.schema import *
from codegen.schema_types import *
from codegen.validate import *
from codegen.yaml_subset import *


if __name__ == "__main__":
    raise SystemExit(main())
