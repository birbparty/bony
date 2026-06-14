## Headless-testable DrawBatch to naylib/raylib adapter planning.

import std/tables

import bony/model

type
  NaylibAlphaMode* = enum
    straightAlpha,
    premultipliedAlpha

  NaylibBlendFactor* = enum
    nbfZero,
    nbfOne,
    nbfSrcAlpha,
    nbfOneMinusSrcAlpha,
    nbfDstColor,
    nbfOneMinusDstColor

  NaylibBlendEquation* = enum
    nbeAdd

  NaylibBlendPreset* = enum
    nbpAlpha,
    nbpAlphaPremultiply,
    nbpMultiplied

  NaylibShaderKind* = enum
    nskOneColor,
    nskTintBlack,
    nskMultiplyPremultiply,
    nskScreen

  NaylibRenderOpKind* = enum
    nropBlendPreset,
    nropBlendSeparate,
    nropShader,
    nropFlush,
    nropDrawTriangles

  NaylibTexturePage* = object
    id*: string
    textureId*: uint32
    alphaMode*: NaylibAlphaMode

  NaylibVertex* = object
    x*: float64
    y*: float64
    u*: float64
    v*: float64
    r*: float64
    g*: float64
    b*: float64
    a*: float64
    darkR*: float64
    darkG*: float64
    darkB*: float64

  NaylibDrawBatch* = object
    slot*: string
    bone*: string
    attachment*: string
    texturePage*: string
    blendMode*: string
    clipId*: string
    vertices*: seq[NaylibVertex]
    indices*: seq[uint16]

  NaylibBlendSeparate* = object
    srcRgb*: NaylibBlendFactor
    dstRgb*: NaylibBlendFactor
    srcAlpha*: NaylibBlendFactor
    dstAlpha*: NaylibBlendFactor
    rgbEquation*: NaylibBlendEquation
    alphaEquation*: NaylibBlendEquation

  NaylibRenderOp* = object
    kind*: NaylibRenderOpKind
    blendPreset*: NaylibBlendPreset
    blendSeparate*: NaylibBlendSeparate
    shader*: NaylibShaderKind
    requiresCustomVertexLayout*: bool
    pageAlphaMode*: NaylibAlphaMode
    texturePage*: string
    textureId*: uint32
    clipId*: string
    triangleCount*: int
    usesStencil*: bool
    vertices*: seq[NaylibVertex]
    indices*: seq[uint16]

  NaylibRenderOptions* = object
    texturePages*: seq[NaylibTexturePage]
    alphaObserved*: bool


proc naylibTexturePage*(
  id: string;
  textureId: uint32;
  alphaMode = straightAlpha;
): NaylibTexturePage =
  if id.len == 0:
    raise newBonyLoadError(schemaViolation, "naylib texture page id must not be empty")
  NaylibTexturePage(id: id, textureId: textureId, alphaMode: alphaMode)


proc naylibRenderOptions*(
  texturePages: openArray[NaylibTexturePage] = [];
  alphaObserved = false;
): NaylibRenderOptions =
  NaylibRenderOptions(texturePages: @texturePages, alphaObserved: alphaObserved)


proc toNaylibVertex(vertex: DrawVertex): NaylibVertex =
  NaylibVertex(
    x: vertex.x,
    y: vertex.y,
    u: vertex.u,
    v: vertex.v,
    r: vertex.r,
    g: vertex.g,
    b: vertex.b,
    a: vertex.a,
  )


proc toNaylibBatch*(batch: DrawBatch): NaylibDrawBatch =
  result = NaylibDrawBatch(
    slot: batch.slot,
    bone: batch.bone,
    attachment: batch.attachment,
    texturePage: batch.texturePage,
    blendMode: batch.blendMode,
    clipId: batch.clipId,
    indices: batch.indices,
  )
  for vertex in batch.vertices:
    result.vertices.add vertex.toNaylibVertex()


proc hasDarkColor(batch: NaylibDrawBatch): bool =
  for vertex in batch.vertices:
    if vertex.darkR != 0.0 or vertex.darkG != 0.0 or vertex.darkB != 0.0:
      return true
  false


proc validateBlendMode(mode: string) =
  case mode
  of "normal", "additive", "multiply", "screen":
    discard
  else:
    raise newBonyLoadError(schemaViolation, "unknown naylib blend mode: " & mode)


proc pageTable(pages: openArray[NaylibTexturePage]): Table[string, NaylibTexturePage] =
  result = initTable[string, NaylibTexturePage]()
  for page in pages:
    if page.id in result:
      raise newBonyLoadError(duplicateKey, "duplicate naylib texture page: " & page.id)
    result[page.id] = page


proc defaultSeparate(
  srcRgb, dstRgb, srcAlpha, dstAlpha: NaylibBlendFactor;
): NaylibBlendSeparate =
  NaylibBlendSeparate(
    srcRgb: srcRgb,
    dstRgb: dstRgb,
    srcAlpha: srcAlpha,
    dstAlpha: dstAlpha,
    rgbEquation: nbeAdd,
    alphaEquation: nbeAdd,
  )


proc blendOps(mode: string; alphaMode: NaylibAlphaMode; alphaObserved: bool): seq[NaylibRenderOp] =
  case mode
  of "normal", "":
    if alphaMode == premultipliedAlpha and not alphaObserved:
      result.add NaylibRenderOp(kind: nropBlendPreset, blendPreset: nbpAlphaPremultiply)
    elif not alphaObserved:
      result.add NaylibRenderOp(kind: nropBlendPreset, blendPreset: nbpAlpha)
    elif alphaMode == premultipliedAlpha:
      result.add NaylibRenderOp(
        kind: nropBlendSeparate,
        blendSeparate: defaultSeparate(nbfOne, nbfOneMinusSrcAlpha, nbfOne, nbfOneMinusSrcAlpha),
      )
    else:
      result.add NaylibRenderOp(
        kind: nropBlendSeparate,
        blendSeparate: defaultSeparate(nbfSrcAlpha, nbfOneMinusSrcAlpha, nbfOne, nbfOneMinusSrcAlpha),
      )
  of "additive":
    let srcRgb = if alphaMode == premultipliedAlpha: nbfOne else: nbfSrcAlpha
    result.add NaylibRenderOp(
      kind: nropBlendSeparate,
      blendSeparate: defaultSeparate(srcRgb, nbfOne, nbfOne, nbfOne),
    )
  of "multiply":
    result.add NaylibRenderOp(kind: nropShader, shader: nskMultiplyPremultiply, pageAlphaMode: alphaMode)
    if alphaMode == premultipliedAlpha:
      result.add NaylibRenderOp(
        kind: nropBlendSeparate,
        blendSeparate: defaultSeparate(nbfDstColor, nbfOneMinusSrcAlpha, nbfOne, nbfOneMinusSrcAlpha),
      )
    elif alphaObserved:
      result.add NaylibRenderOp(
        kind: nropBlendSeparate,
        blendSeparate: defaultSeparate(nbfDstColor, nbfOneMinusSrcAlpha, nbfOne, nbfOneMinusSrcAlpha),
      )
    else:
      result.add NaylibRenderOp(kind: nropBlendPreset, blendPreset: nbpMultiplied)
  of "screen":
    result.add NaylibRenderOp(kind: nropShader, shader: nskScreen, pageAlphaMode: alphaMode)
    result.add NaylibRenderOp(
      kind: nropBlendSeparate,
      blendSeparate: defaultSeparate(nbfOneMinusDstColor, nbfOne, nbfOne, nbfOneMinusSrcAlpha),
    )
  else:
    raise newBonyLoadError(schemaViolation, "unknown naylib blend mode: " & mode)


proc validateIndices(batch: NaylibDrawBatch) =
  if batch.indices.len mod 3 != 0:
    raise newBonyLoadError(schemaViolation, "naylib draw batch indices must contain triangles")
  for index in batch.indices:
    if int(index) >= batch.vertices.len:
      raise newBonyLoadError(unknownRequiredReference, "naylib draw batch index out of range")


proc buildNaylibRenderPlan*(batches: openArray[NaylibDrawBatch]; options: NaylibRenderOptions): seq[NaylibRenderOp] =
  let pages = pageTable(options.texturePages)
  for batch in batches:
    validateBlendMode(batch.blendMode)
    validateIndices(batch)
    var page = NaylibTexturePage(alphaMode: straightAlpha)
    if batch.texturePage.len > 0:
      if batch.texturePage notin pages:
        raise newBonyLoadError(unknownRequiredReference, "unknown naylib texture page: " & batch.texturePage)
      page = pages[batch.texturePage]
    if batch.indices.len == 0:
      continue

    let hasDark = batch.hasDarkColor()
    let shader = if hasDark: nskTintBlack else: nskOneColor
    result.add NaylibRenderOp(
      kind: nropShader,
      shader: shader,
      requiresCustomVertexLayout: hasDark,
      pageAlphaMode: page.alphaMode,
    )
    for op in blendOps(batch.blendMode, page.alphaMode, options.alphaObserved):
      result.add op
    result.add NaylibRenderOp(
      kind: nropDrawTriangles,
      texturePage: batch.texturePage,
      textureId: page.textureId,
      clipId: batch.clipId,
      triangleCount: batch.indices.len div 3,
      usesStencil: false,
      vertices: batch.vertices,
      indices: batch.indices,
    )


proc buildNaylibRenderPlan*(batches: openArray[DrawBatch]; options: NaylibRenderOptions): seq[NaylibRenderOp] =
  var converted: seq[NaylibDrawBatch]
  for batch in batches:
    converted.add batch.toNaylibBatch()
  buildNaylibRenderPlan(converted, options)


proc buildNaylibRenderPlan*(batches: openArray[DrawBatch]): seq[NaylibRenderOp] =
  buildNaylibRenderPlan(batches, naylibRenderOptions())
