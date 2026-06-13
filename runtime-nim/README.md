# bony Nim Runtime

This package is the Nim reference runtime skeleton.

Tests use `bddy` from a sibling checkout:

```text
~/git/
  bddy/
  bony/
```

`runtime-nim/nim.cfg` scopes that path to this package so production runtime
code is not given `bddy` from the repository root config.
