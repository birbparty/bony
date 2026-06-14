# Nim Dependency License Scan

This scan records the permissive-license check required before Nim runtime
dependencies become hard dependencies. It covers the dependency candidates named
in the project plan plus the resolved dependency versions currently used by the
software rasterizer.

Scan date: 2026-06-14

## Decision

The named Nim dependency candidates are acceptable for use in this repository.
`runtime-nim/bony.nimble` pins `pixie == 6.1.0`; this scan authorizes that
version and the resolved transitive versions below. Bumping `pixie` or adding a
new Nim dependency requires updating this scan first.

- `vmath`: MIT.
- `chroma`: MIT.
- `pixie`: MIT.
- `jsony`: MIT.
- `flatty`: MIT.
- `binny`: covered as a module shipped inside `flatty`, MIT through `flatty`.
- `naylib`: MIT.
- raylib, the native library wrapped by `naylib`: zlib/libpng-style license.

No GPL, Creative Commons, proprietary, or source-available-only license was
found in the named candidates.

## Evidence

| Dependency | Upstream | Package metadata | License file | Result |
| --- | --- | --- | --- | --- |
| `vmath` | `https://github.com/treeform/vmath` | `vmath.nimble` declares `license = "MIT"` | `LICENSE` is MIT | Accept |
| `chroma` | `https://github.com/treeform/chroma` | `chroma.nimble` declares `license = "MIT"` | `LICENSE` is MIT | Accept |
| `pixie` 6.1.0 | `https://github.com/treeform/pixie` | `pixie.nimble` declares `license = "MIT"` | `LICENSE` is MIT | Accept |
| `jsony` | `https://github.com/treeform/jsony` | `jsony.nimble` declares `license = "MIT"` | `LICENSE` is MIT | Accept |
| `flatty` | `https://github.com/treeform/flatty` | `flatty.nimble` declares `license = "MIT"` | `LICENSE` is MIT | Accept |
| `binny` | `https://github.com/treeform/flatty` | Not a separate Nimble package; `flatty` README says it ships `binny` | `flatty` `LICENSE` is MIT | Accept as part of `flatty` |
| `naylib` | `https://github.com/planetis-m/naylib` | `naylib.nimble` declares `license = "MIT"` | `LICENSE` is MIT | Accept |
| `raylib` | `https://github.com/raysan5/raylib` | Native dependency of `naylib` | `LICENSE` permits commercial use, modification, and redistribution with notice conditions | Accept |

Primary source URLs checked:

- `https://raw.githubusercontent.com/treeform/vmath/master/vmath.nimble`
- `https://raw.githubusercontent.com/treeform/vmath/master/LICENSE`
- `https://raw.githubusercontent.com/treeform/chroma/master/chroma.nimble`
- `https://raw.githubusercontent.com/treeform/chroma/master/LICENSE`
- `https://raw.githubusercontent.com/treeform/pixie/master/pixie.nimble`
- `https://raw.githubusercontent.com/treeform/pixie/master/LICENSE`
- `https://raw.githubusercontent.com/treeform/jsony/master/jsony.nimble`
- `https://raw.githubusercontent.com/treeform/jsony/master/LICENSE`
- `https://raw.githubusercontent.com/treeform/flatty/master/flatty.nimble`
- `https://raw.githubusercontent.com/treeform/flatty/master/README.md`
- `https://raw.githubusercontent.com/treeform/flatty/master/LICENSE`
- `https://raw.githubusercontent.com/planetis-m/naylib/master/naylib.nimble`
- `https://raw.githubusercontent.com/planetis-m/naylib/master/LICENSE`
- `https://raw.githubusercontent.com/raysan5/raylib/master/LICENSE`

## Pixie Transitives

The local Nimble resolution for `pixie == 6.1.0` used these direct
dependencies:

- `vmath` 3.0.0: MIT, covered above.
- `chroma` 1.0.0: MIT, covered above.
- `zippy` 0.10.19: MIT.
- `flatty` 0.4.0: MIT, covered above.
- `nimsimd` 1.3.2: MIT.
- `bumpy` 1.1.3: MIT.
- `crunchy` 0.1.11: MIT.

Additional primary source URLs checked for pixie transitives:

- `https://raw.githubusercontent.com/guzba/zippy/master/LICENSE`
- `https://raw.githubusercontent.com/guzba/nimsimd/master/LICENSE`
- `https://raw.githubusercontent.com/treeform/bumpy/master/LICENSE`
- `https://raw.githubusercontent.com/guzba/crunchy/master/crunchy.nimble`
- `https://raw.githubusercontent.com/guzba/crunchy/master/LICENSE`

## Ongoing Rule

Before adding any new Nim dependency or upgrading an existing dependency to a
version whose license metadata changes, update this scan with the package
metadata and license-file evidence. Do not add GPL, Creative Commons,
proprietary, or source-available-only dependencies to runtime code.
