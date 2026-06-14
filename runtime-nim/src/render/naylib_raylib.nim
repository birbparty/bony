## Real naylib/raylib bridge for DrawBatch render plans.

import raylib
import rlgl

import bony/model
import render/naylib_adapter

type
  NaylibShaderPrograms* = object
    tintBlack*: uint32
    multiplyPremultiply*: uint32
    screen*: uint32


proc toRaylibFactor(factor: NaylibBlendFactor): BlendFactor =
  case factor
  of nbfZero: Zero
  of nbfOne: One
  of nbfSrcAlpha: SrcAlpha
  of nbfOneMinusSrcAlpha: OneMinusSrcAlpha
  of nbfDstColor: DstColor


proc toRaylibEquation(equation: NaylibBlendEquation): BlendFuncOrEq =
  case equation
  of nbeAdd: FuncAdd


proc applyBlendPreset(preset: NaylibBlendPreset) =
  case preset
  of nbpAlpha:
    beginBlendMode(Alpha)
  of nbpAlphaPremultiply:
    beginBlendMode(AlphaPremultiply)
  of nbpMultiplied:
    beginBlendMode(Multiplied)


proc applyBlendSeparate(blend: NaylibBlendSeparate) =
  beginBlendMode(CustomSeparate)
  setBlendFactorsSeparate(
    blend.srcRgb.toRaylibFactor(),
    blend.dstRgb.toRaylibFactor(),
    blend.srcAlpha.toRaylibFactor(),
    blend.dstAlpha.toRaylibFactor(),
    blend.rgbEquation.toRaylibEquation(),
    blend.alphaEquation.toRaylibEquation(),
  )


proc colorByte(value: float64): uint8 =
  if value <= 0.0:
    0'u8
  elif value >= 1.0:
    255'u8
  else:
    uint8(value * 255.0 + 0.5)


proc applyShader(shader: NaylibShaderKind; programs: NaylibShaderPrograms) =
  case shader
  of nskOneColor:
    disableShader()
  of nskTintBlack:
    if programs.tintBlack == 0:
      raise newBonyLoadError(schemaViolation, "naylib tint-black shader program is required")
    enableShader(programs.tintBlack)
  of nskMultiplyPremultiply:
    if programs.multiplyPremultiply == 0:
      raise newBonyLoadError(schemaViolation, "naylib multiply shader program is required")
    enableShader(programs.multiplyPremultiply)
  of nskScreen:
    if programs.screen == 0:
      raise newBonyLoadError(schemaViolation, "naylib screen shader program is required")
    enableShader(programs.screen)


proc drawTriangles(op: NaylibRenderOp) =
  setTexture(op.textureId)
  drawMode(Triangles):
    for index in op.indices:
      let vertex = op.vertices[int(index)]
      texCoord2f(float32(vertex.u), float32(vertex.v))
      color4ub(vertex.r.colorByte(), vertex.g.colorByte(), vertex.b.colorByte(), vertex.a.colorByte())
      vertex2f(float32(vertex.x), float32(vertex.y))
  setTexture(0)


proc applyNaylibRenderPlan*(plan: openArray[NaylibRenderOp]; programs = NaylibShaderPrograms()) =
  for op in plan:
    case op.kind
    of nropBlendPreset:
      applyBlendPreset(op.blendPreset)
    of nropBlendSeparate:
      applyBlendSeparate(op.blendSeparate)
    of nropShader:
      applyShader(op.shader, programs)
    of nropDrawTriangles:
      drawTriangles(op)
  disableShader()
  endBlendMode()
