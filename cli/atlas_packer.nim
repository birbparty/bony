## Shelf bin-packing atlas generator for bony CLI.
##
## Packs a set of named images into atlas pages using the shelf/row algorithm
## (sort by height descending, fill rows left-to-right, new page when full).
## Emits packed page images and region placement metadata.
##
## The shelf algorithm is a classic O(n log n) greedy bin packing approach
## documented in textbooks and not encumbered by any third-party license.

import std/algorithm

import pixie


type
  AtlasInputImage* = object
    name*: string
    image*: Image

  PackedRegion* = object
    name*: string
    page*: int
    x*: int
    y*: int
    width*: int
    height*: int

  PackResult* = object
    pages*: seq[Image]
    regions*: seq[PackedRegion]


type
  Shelf = object
    y: int
    rowHeight: int
    x: int


proc packAtlas*(
  inputs: seq[AtlasInputImage];
  pageSize: int;
  padding: int;
): PackResult =
  ## Pack `inputs` into atlas pages of `pageSize x pageSize` pixels.
  ## `padding` pixels of transparent space are added around each region.
  ##
  ## Preconditions:
  ##   - pageSize > 0
  ##   - padding >= 0
  ##   - each image width+height <= pageSize - 2*padding
  if inputs.len == 0:
    return

  let pad2 = 2 * padding
  let innerMax = pageSize - pad2

  # Sort by height descending for packing density; tie-break by name for
  # deterministic output regardless of sort stability or input order.
  var sorted = inputs
  sorted.sort proc(a, b: AtlasInputImage): int =
    let ha = a.image.height
    let hb = b.image.height
    if ha > hb: -1 elif ha < hb: 1 else: cmp(a.name, b.name)

  var currentPage = newImage(pageSize, pageSize)
  var shelf = Shelf(y: padding, rowHeight: 0, x: padding)
  var currentPageIndex = 0

  for inp in sorted:
    let w = inp.image.width
    let h = inp.image.height
    if w > innerMax or h > innerMax:
      raise newException(ValueError,
        "image '" & inp.name & "' (" & $w & "x" & $h &
        ") exceeds innerMax=" & $innerMax & " (pageSize=" & $pageSize &
        " minus 2*padding=" & $pad2 & ")")

    let slotW = w + pad2
    let slotH = h + pad2

    # Try to fit in current shelf row
    if shelf.x + slotW > pageSize:
      # Advance to next shelf row
      shelf.y += shelf.rowHeight
      shelf.x = padding
      shelf.rowHeight = 0

    # If this row doesn't fit on the current page, start a new page
    if shelf.y + slotH > pageSize:
      result.pages.add currentPage
      currentPage = newImage(pageSize, pageSize)
      currentPageIndex += 1
      shelf = Shelf(y: padding, rowHeight: 0, x: padding)

    let px = shelf.x
    let py = shelf.y

    # Blit the image onto the page at (px, py)
    currentPage.draw(inp.image, translate(vec2(px.float32, py.float32)))

    result.regions.add PackedRegion(
      name: inp.name,
      page: currentPageIndex,
      x: px,
      y: py,
      width: w,
      height: h,
    )

    shelf.x += slotW
    if slotH > shelf.rowHeight:
      shelf.rowHeight = slotH

  result.pages.add currentPage


# UVs are in image/texture space (Y-down, v=0 at top). This is independent of
# bony's world-space Y-up convention — texture sampling uses image-space UVs.
proc atlasRegionU0*(region: PackedRegion; pageWidth: int): float64 =
  region.x.float64 / pageWidth.float64

proc atlasRegionV0*(region: PackedRegion; pageHeight: int): float64 =
  region.y.float64 / pageHeight.float64

proc atlasRegionU1*(region: PackedRegion; pageWidth: int): float64 =
  (region.x + region.width).float64 / pageWidth.float64

proc atlasRegionV1*(region: PackedRegion; pageHeight: int): float64 =
  (region.y + region.height).float64 / pageHeight.float64
