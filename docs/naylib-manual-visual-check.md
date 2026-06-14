# Naylib Manual Visual Check

The naylib adapter is the prioritized real-time Nim renderer. It is not the
source of conformance truth; numeric goldens and Nim-only software-rasterizer
image goldens remain authoritative.

Use this checklist after changing `runtime-nim/src/render/naylib*` or the
`DrawBatch` contract.

## Setup

1. Build the Nim runtime tests on Linux with the project Nimble dependencies.
2. Run the headless smoke tests first:

```bash
cd runtime-nim
nimble test -y --path:~/git/bddy
```

The smoke tests must prove that `DrawBatch` inputs map to the expected raylib
blend, shader, texture, and triangle-submission operations without requiring a
display.

## Visual Cases

Render a simple local harness or example scene with the real raylib bridge and
inspect these cases:

- `normal` straight-alpha texture page over transparent and opaque backgrounds.
- `normal` premultiplied-alpha texture page over transparent and opaque
  backgrounds.
- `additive`, `multiply`, and `screen` batches with partially transparent
  source pixels.
- A batch with non-zero tint-black dark color, proving the tint-black shader
  path is active.
- A pre-clipped mesh batch with a non-empty `clipId`, proving no stencil stack
  is required for the default v1 path.
- Multiple slots drawn in order with different texture pages and blend modes.

## Acceptance

- No PMA page is drawn through the straight `BLEND_ALPHA` path.
- Alpha-observed render-texture output uses separate alpha factors.
- Tint-black output visibly differs from one-color tint when dark color is
  non-zero.
- Clipped geometry appears already clipped; toggling `clipId` alone does not
  change output.
- Visual output is treated as a renderer QA signal only. Do not use naylib
  screenshots as cross-runtime conformance artifacts.
