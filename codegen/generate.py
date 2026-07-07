#!/usr/bin/env python3
"""Generate bony runtime metadata and schema from registry/default sources."""

from __future__ import annotations

from cli import main, write_or_check
from emit import *
from paths import *
from schema import *
from schema_types import *
from validate import *
from yaml_subset import *


if __name__ == "__main__":
    raise SystemExit(main())
