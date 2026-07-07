## Atlas packing command.

import std/[algorithm, json, os, sets, strutils]

import bony
import pixie

import ../argparse
import ../atlas_packer
import ../cli_common

proc packAtlasCmd*(args: seq[string]; usageText: string) =
  if args.len < 1:
    quit(usageText, QuitFailure)
  let imagesDir = args[0]
  var outDir = ""
  var pageSize = 2048
  var padding = 2
  var cursor = initArgCursor(args, usageText)
  cursor.index = 1
  while not cursor.done:
    case cursor.current
    of "--out-dir":
      outDir = cursor.requireValue("--out-dir")
    of "--page-size":
      pageSize = parsePositiveIntArg(cursor.requireValue("--page-size"), "--page-size")
    of "--padding":
      padding = parseNonNegativeIntArg(cursor.requireValue("--padding"), "--padding")
    else:
      cursor.failUsage()

  if outDir.len == 0:
    raise newBonyLoadError(schemaViolation, "pack-atlas requires --out-dir")
  if not dirExists(imagesDir):
    raise newBonyLoadError(schemaViolation, "images-dir not found: " & imagesDir)
  if 2 * padding >= pageSize:
    raise newBonyLoadError(schemaViolation,
      "--padding " & $padding & " leaves no usable space in --page-size " & $pageSize)

  # Collect PNG files from images-dir
  var inputs: seq[AtlasInputImage] = @[]
  var seen = initHashSet[string]()
  for kind, path in walkDir(imagesDir):
    if kind == pcFile and path.toLowerAscii.endsWith(".png"):
      let name = changeFileExt(extractFilename(path), "")
      if name in seen:
        raise newBonyLoadError(schemaViolation,
          "duplicate region name '" & name & "' from: " & path)
      seen.incl(name)
      var img: Image
      try:
        img = decodeImage(readFile(path))
      except PixieError as exc:
        raise newBonyLoadError(schemaViolation,
          "failed to decode PNG '" & path & "': " & exc.msg)
      inputs.add AtlasInputImage(name: name, image: img)
  if inputs.len == 0:
    raise newBonyLoadError(schemaViolation, "no PNG images found in: " & imagesDir)

  # Sort by name for deterministic output independent of filesystem traversal order
  inputs.sort proc(a, b: AtlasInputImage): int = cmp(a.name, b.name)

  let packed = packAtlas(inputs, pageSize, padding)

  createDir(outDir)

  # Write page images
  var pagesJson = newJArray()
  for i, page in packed.pages:
    let pageName = "atlas_" & $i & ".png"
    let pagePath = outDir / pageName
    page.writeFile(pagePath)
    var pageNode = newJObject()
    pageNode["name"] = newJString(pageName)
    pageNode["width"] = newJInt(page.width)
    pageNode["height"] = newJInt(page.height)
    pagesJson.add pageNode

  # Build regions JSON with UV coordinates
  var regionsJson = newJArray()
  for region in packed.regions:
    let pageW = packed.pages[region.page].width
    let pageH = packed.pages[region.page].height
    var rNode = newJObject()
    rNode["name"] = newJString(region.name)
    rNode["page"] = newJInt(region.page)
    rNode["x"] = newJInt(region.x)
    rNode["y"] = newJInt(region.y)
    rNode["width"] = newJInt(region.width)
    rNode["height"] = newJInt(region.height)
    rNode["u0"] = newJFloat(atlasRegionU0(region, pageW))
    rNode["v0"] = newJFloat(atlasRegionV0(region, pageH))
    rNode["u1"] = newJFloat(atlasRegionU1(region, pageW))
    rNode["v1"] = newJFloat(atlasRegionV1(region, pageH))
    regionsJson.add rNode

  var root = newJObject()
  root["format"] = newJString("bony.atlas.v1")
  root["pageSize"] = newJInt(pageSize)
  root["padding"] = newJInt(padding)
  root["pages"] = pagesJson
  root["regions"] = regionsJson

  writeFile(outDir / "atlas.json", pretty(root) & "\n")
  echo "bony: packed ", inputs.len, " image(s) into ", packed.pages.len, " page(s) -> ", outDir
