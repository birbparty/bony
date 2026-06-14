## Pixie-backed software reference rasterizer for DrawBatch image goldens.

import std/[math, tables]

import pixie

import bony/model

const rasterEpsilon = 1e-12

type
  SoftwareTexturePage* = object
    id*: string
    image*: Image
    premultipliedAlpha*: bool

  SoftwareRasterOptions* = object
    width*: int
    height*: int
    clear*: ColorRGBA
    texturePages*: seq[SoftwareTexturePage]

  FloatColor = object
    r: float64
    g: float64
    b: float64
    a: float64


proc softwareRasterOptions*(
  width, height: int;
  clear = rgba(0, 0, 0, 0);
  texturePages: openArray[SoftwareTexturePage] = [];
): SoftwareRasterOptions =
  if width <= 0 or height <= 0:
    raise newBonyLoadError(schemaViolation, "software rasterizer dimensions must be positive")
  SoftwareRasterOptions(width: width, height: height, clear: clear, texturePages: @texturePages)


proc softwareTexturePage*(id: string; image: Image; premultipliedAlpha = false): SoftwareTexturePage =
  if id.len == 0:
    raise newBonyLoadError(schemaViolation, "software texture page id must not be empty")
  if image.isNil:
    raise newBonyLoadError(schemaViolation, "software texture page image must not be nil")
  SoftwareTexturePage(id: id, image: image, premultipliedAlpha: premultipliedAlpha)


proc clamp01(value: float64): float64 =
  min(1.0, max(0.0, value))


proc toFloatColor(color: ColorRGBA): FloatColor =
  let alpha = float64(color.a) / 255.0
  if alpha <= rasterEpsilon:
    return FloatColor()
  FloatColor(
    r: clamp01((float64(color.r) / 255.0) / alpha),
    g: clamp01((float64(color.g) / 255.0) / alpha),
    b: clamp01((float64(color.b) / 255.0) / alpha),
    a: alpha,
  )


proc toByte(value: float64): uint8 =
  uint8(floor(clamp01(value) * 255.0 + 0.5))


proc toColorRGBA(color: FloatColor): ColorRGBA =
  rgba(toByte(color.r), toByte(color.g), toByte(color.b), toByte(color.a))


proc blendNormal(source, dest: FloatColor): FloatColor =
  let outA = source.a + dest.a * (1.0 - source.a)
  let outPremulR = source.r * source.a + dest.r * dest.a * (1.0 - source.a)
  let outPremulG = source.g * source.a + dest.g * dest.a * (1.0 - source.a)
  let outPremulB = source.b * source.a + dest.b * dest.a * (1.0 - source.a)
  if outA <= rasterEpsilon:
    return FloatColor()
  FloatColor(r: outPremulR / outA, g: outPremulG / outA, b: outPremulB / outA, a: outA)


proc blendAdditive(source, dest: FloatColor): FloatColor =
  let outA = min(1.0, source.a + dest.a)
  let outPremulR = source.r * source.a + dest.r * dest.a
  let outPremulG = source.g * source.a + dest.g * dest.a
  let outPremulB = source.b * source.a + dest.b * dest.a
  if outA <= rasterEpsilon:
    return FloatColor()
  FloatColor(r: outPremulR / outA, g: outPremulG / outA, b: outPremulB / outA, a: outA)


proc blendMultiply(source, dest: FloatColor): FloatColor =
  FloatColor(
    r: dest.r * (source.r * source.a + (1.0 - source.a)),
    g: dest.g * (source.g * source.a + (1.0 - source.a)),
    b: dest.b * (source.b * source.a + (1.0 - source.a)),
    a: source.a + dest.a * (1.0 - source.a),
  )


proc blendScreen(source, dest: FloatColor): FloatColor =
  FloatColor(
    r: dest.r + (source.r * source.a) * (1.0 - dest.r),
    g: dest.g + (source.g * source.a) * (1.0 - dest.g),
    b: dest.b + (source.b * source.a) * (1.0 - dest.b),
    a: source.a + dest.a * (1.0 - source.a),
  )


proc blend(source, dest: FloatColor; mode: string): FloatColor =
  case mode
  of "normal", "":
    blendNormal(source, dest)
  of "additive":
    blendAdditive(source, dest)
  of "multiply":
    blendMultiply(source, dest)
  of "screen":
    blendScreen(source, dest)
  else:
    raise newBonyLoadError(schemaViolation, "unknown software blend mode: " & mode)


proc validateBlendMode(mode: string) =
  case mode
  of "normal", "", "additive", "multiply", "screen":
    discard
  else:
    raise newBonyLoadError(schemaViolation, "unknown software blend mode: " & mode)


proc edge(a, b: DrawVertex; x, y: float64): float64 =
  (x - a.x) * (b.y - a.y) - (y - a.y) * (b.x - a.x)


proc isTopLeftEdge(a, b: DrawVertex): bool =
  (b.y < a.y) or (b.y == a.y and b.x > a.x)


proc includesEdge(value: float64; a, b: DrawVertex): bool =
  value > rasterEpsilon or (abs(value) <= rasterEpsilon and isTopLeftEdge(a, b))


proc interpolate(a, b, c: float64; w0, w1, w2: float64): float64 =
  a * w0 + b * w1 + c * w2


proc sampleWhite(): FloatColor =
  FloatColor(r: 1.0, g: 1.0, b: 1.0, a: 1.0)


proc sampleTexture(page: SoftwareTexturePage; u, v: float64): FloatColor =
  if page.image.isNil:
    return sampleWhite()
  let x = int(floor(clamp01(u) * float64(page.image.width - 1) + 0.5))
  let y = int(floor(clamp01(v) * float64(page.image.height - 1) + 0.5))
  result = page.image[x, y].toFloatColor()
  if page.premultipliedAlpha:
    if result.a > rasterEpsilon:
      result.r = clamp01(result.r / result.a)
      result.g = clamp01(result.g / result.a)
      result.b = clamp01(result.b / result.a)
    else:
      result.r = 0.0
      result.g = 0.0
      result.b = 0.0


proc sourceColor(
  batch: DrawBatch;
  page: SoftwareTexturePage;
  w0, w1, w2: float64;
  i0, i1, i2: int;
): FloatColor =
  let a = batch.vertices[i0]
  let b = batch.vertices[i1]
  let c = batch.vertices[i2]
  let texture =
    if batch.texturePage.len == 0:
      sampleWhite()
    else:
      sampleTexture(
        page,
        interpolate(a.u, b.u, c.u, w0, w1, w2),
        interpolate(a.v, b.v, c.v, w0, w1, w2),
      )
  let lightR = interpolate(a.r, b.r, c.r, w0, w1, w2)
  let lightG = interpolate(a.g, b.g, c.g, w0, w1, w2)
  let lightB = interpolate(a.b, b.b, c.b, w0, w1, w2)
  let lightA = interpolate(a.a, b.a, c.a, w0, w1, w2)
  FloatColor(
    r: clamp01(texture.r * lightR),
    g: clamp01(texture.g * lightG),
    b: clamp01(texture.b * lightB),
    a: clamp01(texture.a * lightA),
  )


proc drawTriangle(
  image: Image;
  batch: DrawBatch;
  page: SoftwareTexturePage;
  i0, i1, i2: int;
) =
  let v0 = batch.vertices[i0]
  var v1 = batch.vertices[i1]
  var v2 = batch.vertices[i2]
  var j1 = i1
  var j2 = i2
  var area = edge(v0, v1, v2.x, v2.y)
  if abs(area) <= rasterEpsilon:
    return
  if area < 0.0:
    swap(v1, v2)
    swap(j1, j2)
    area = -area

  let minX = max(0, int(floor(min(v0.x, min(v1.x, v2.x)))))
  let maxX = min(image.width - 1, int(ceil(max(v0.x, max(v1.x, v2.x))) - 1.0))
  let minY = max(0, int(floor(min(v0.y, min(v1.y, v2.y)))))
  let maxY = min(image.height - 1, int(ceil(max(v0.y, max(v1.y, v2.y))) - 1.0))
  if minX > maxX or minY > maxY:
    return

  let invArea = 1.0 / area

  for y in minY .. maxY:
    for x in minX .. maxX:
      let px = float64(x) + 0.5
      let py = float64(y) + 0.5
      let e0 = edge(v1, v2, px, py)
      let e1 = edge(v2, v0, px, py)
      let e2 = edge(v0, v1, px, py)
      if e0.includesEdge(v1, v2) and e1.includesEdge(v2, v0) and e2.includesEdge(v0, v1):
        let w0 = e0 * invArea
        let w1 = e1 * invArea
        let w2 = e2 * invArea
        let source = sourceColor(batch, page, w0, w1, w2, i0, j1, j2)
        let dest = image[x, y].toFloatColor()
        image[x, y] = blend(source, dest, batch.blendMode).toColorRGBA()


proc pageTable(pages: openArray[SoftwareTexturePage]): Table[string, SoftwareTexturePage] =
  result = initTable[string, SoftwareTexturePage]()
  for page in pages:
    if page.id in result:
      raise newBonyLoadError(duplicateKey, "duplicate software texture page: " & page.id)
    result[page.id] = page


proc renderSoftware*(batches: openArray[DrawBatch]; options: SoftwareRasterOptions): Image =
  result = newImage(options.width, options.height)
  result.fill(options.clear)
  let pages = pageTable(options.texturePages)
  for batch in batches:
    validateBlendMode(batch.blendMode)
    if batch.indices.len == 0:
      continue
    if batch.indices.len mod 3 != 0:
      raise newBonyLoadError(schemaViolation, "software draw batch indices must contain triangles")
    var page = SoftwareTexturePage()
    if batch.texturePage.len > 0:
      if batch.texturePage notin pages:
        raise newBonyLoadError(unknownRequiredReference, "unknown software texture page: " & batch.texturePage)
      page = pages[batch.texturePage]
    for triangle in countup(0, batch.indices.len - 1, 3):
      let i0 = int(batch.indices[triangle])
      let i1 = int(batch.indices[triangle + 1])
      let i2 = int(batch.indices[triangle + 2])
      if i0 >= batch.vertices.len or i1 >= batch.vertices.len or i2 >= batch.vertices.len:
        raise newBonyLoadError(unknownRequiredReference, "software draw batch index out of range")
      result.drawTriangle(batch, page, i0, i1, i2)


proc renderSoftware*(batches: openArray[DrawBatch]; width, height: int): Image =
  renderSoftware(batches, softwareRasterOptions(width, height))
