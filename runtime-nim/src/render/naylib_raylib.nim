## Real naylib/raylib bridge for DrawBatch render plans.

import std/strutils

import raylib
import rlgl

import bony/model
import render/naylib_adapter

type
  NaylibShaderPrograms* = object
    tintBlack*: uint32
    multiplyPremultiplyStraight*: uint32
    multiplyPremultiplyPma*: uint32
    screenStraight*: uint32
    screenPma*: uint32

  NaylibCallKind* = enum
    nckFlush,
    nckBlendPreset,
    nckBlendSeparate,
    nckShader,
    nckSetTexture,
    nckVertex,
    nckEndBlend,
    nckDisableShader

  NaylibCall* = object
    kind*: NaylibCallKind
    blendPreset*: NaylibBlendPreset
    blendSeparate*: NaylibBlendSeparate
    shader*: NaylibShaderKind
    textureId*: uint32
    vertex*: NaylibVertex


proc toRaylibFactor(factor: NaylibBlendFactor): BlendFactor =
  case factor
  of nbfZero: Zero
  of nbfOne: One
  of nbfSrcAlpha: SrcAlpha
  of nbfOneMinusSrcAlpha: OneMinusSrcAlpha
  of nbfDstColor: DstColor
  of nbfOneMinusDstColor: OneMinusDstColor


proc toRaylibEquation(equation: NaylibBlendEquation): BlendFuncOrEq =
  case equation
  of nbeAdd: FuncAdd


proc colorByte(value: float64): uint8 =
  if value <= 0.0:
    0'u8
  elif value >= 1.0:
    255'u8
  else:
    uint8(value * 255.0 + 0.5)


proc shaderProgram(shader: NaylibShaderKind; alphaMode: NaylibAlphaMode; programs: NaylibShaderPrograms): uint32 =
  case shader
  of nskOneColor:
    0'u32
  of nskTintBlack:
    programs.tintBlack
  of nskMultiplyPremultiply:
    if alphaMode == premultipliedAlpha:
      programs.multiplyPremultiplyPma
    else:
      programs.multiplyPremultiplyStraight
  of nskScreen:
    if alphaMode == premultipliedAlpha:
      programs.screenPma
    else:
      programs.screenStraight


proc requireShaderProgram(shader: NaylibShaderKind; alphaMode: NaylibAlphaMode; programs: NaylibShaderPrograms): uint32 =
  result = shader.shaderProgram(alphaMode, programs)
  if result == 0 and shader != nskOneColor:
    raise newBonyLoadError(
      schemaViolation,
      "naylib " & ($shader).replace("nsk", "").toLowerAscii() & " shader program is required",
    )


proc validateRenderable(op: NaylibRenderOp; programs: NaylibShaderPrograms) =
  if op.kind == nropShader:
    if op.requiresCustomVertexLayout:
      raise newBonyLoadError(
        schemaViolation,
        "naylib tint-black requires a custom vertex layout before real raylib submission",
      )
    discard op.shader.requireShaderProgram(op.pageAlphaMode, programs)


proc recordCall(calls: var seq[NaylibCall]; call: NaylibCall) =
  calls.add call


proc applyBlendPreset(op: NaylibRenderOp; calls: var seq[NaylibCall]) =
  drawRenderBatchActive()
  calls.recordCall(NaylibCall(kind: nckFlush))
  case op.blendPreset
  of nbpAlpha:
    beginBlendMode(Alpha)
  of nbpAlphaPremultiply:
    beginBlendMode(AlphaPremultiply)
  of nbpMultiplied:
    beginBlendMode(Multiplied)
  calls.recordCall(NaylibCall(kind: nckBlendPreset, blendPreset: op.blendPreset))


proc applyBlendSeparate(op: NaylibRenderOp; calls: var seq[NaylibCall]) =
  drawRenderBatchActive()
  calls.recordCall(NaylibCall(kind: nckFlush))
  let blend = op.blendSeparate
  setBlendFactorsSeparate(
    blend.srcRgb.toRaylibFactor(),
    blend.dstRgb.toRaylibFactor(),
    blend.srcAlpha.toRaylibFactor(),
    blend.dstAlpha.toRaylibFactor(),
    blend.rgbEquation.toRaylibEquation(),
    blend.alphaEquation.toRaylibEquation(),
  )
  beginBlendMode(CustomSeparate)
  calls.recordCall(NaylibCall(kind: nckBlendSeparate, blendSeparate: blend))


proc applyShader(op: NaylibRenderOp; programs: NaylibShaderPrograms; calls: var seq[NaylibCall]) =
  validateRenderable(op, programs)
  drawRenderBatchActive()
  calls.recordCall(NaylibCall(kind: nckFlush))
  let program = op.shader.shaderProgram(op.pageAlphaMode, programs)
  if program == 0:
    disableShader()
  else:
    enableShader(program)
  calls.recordCall(NaylibCall(kind: nckShader, shader: op.shader))


proc drawTriangles(op: NaylibRenderOp; calls: var seq[NaylibCall]) =
  setTexture(op.textureId)
  calls.recordCall(NaylibCall(kind: nckSetTexture, textureId: op.textureId))
  drawMode(Triangles):
    for index in op.indices:
      let vertex = op.vertices[int(index)]
      texCoord2f(float32(vertex.u), float32(vertex.v))
      color4ub(vertex.r.colorByte(), vertex.g.colorByte(), vertex.b.colorByte(), vertex.a.colorByte())
      vertex2f(float32(vertex.x), float32(vertex.y))
      calls.recordCall(NaylibCall(kind: nckVertex, vertex: vertex))
  setTexture(0)
  calls.recordCall(NaylibCall(kind: nckSetTexture, textureId: 0'u32))


proc traceNaylibRenderPlan*(plan: openArray[NaylibRenderOp]; programs = NaylibShaderPrograms()): seq[NaylibCall] =
  for op in plan:
    case op.kind
    of nropBlendPreset:
      result.recordCall(NaylibCall(kind: nckFlush))
      result.recordCall(NaylibCall(kind: nckBlendPreset, blendPreset: op.blendPreset))
    of nropBlendSeparate:
      result.recordCall(NaylibCall(kind: nckFlush))
      result.recordCall(NaylibCall(kind: nckBlendSeparate, blendSeparate: op.blendSeparate))
    of nropShader:
      validateRenderable(op, programs)
      result.recordCall(NaylibCall(kind: nckFlush))
      result.recordCall(NaylibCall(kind: nckShader, shader: op.shader))
    of nropFlush:
      result.recordCall(NaylibCall(kind: nckFlush))
    of nropDrawTriangles:
      result.recordCall(NaylibCall(kind: nckSetTexture, textureId: op.textureId))
      for index in op.indices:
        result.recordCall(NaylibCall(kind: nckVertex, vertex: op.vertices[int(index)]))
      result.recordCall(NaylibCall(kind: nckSetTexture, textureId: 0'u32))
  result.recordCall(NaylibCall(kind: nckDisableShader))
  result.recordCall(NaylibCall(kind: nckEndBlend))


proc applyNaylibRenderPlan*(plan: openArray[NaylibRenderOp]; programs = NaylibShaderPrograms()): seq[NaylibCall] =
  for op in plan:
    case op.kind
    of nropBlendPreset:
      applyBlendPreset(op, result)
    of nropBlendSeparate:
      applyBlendSeparate(op, result)
    of nropShader:
      applyShader(op, programs, result)
    of nropFlush:
      drawRenderBatchActive()
      result.recordCall(NaylibCall(kind: nckFlush))
    of nropDrawTriangles:
      drawTriangles(op, result)
  disableShader()
  result.recordCall(NaylibCall(kind: nckDisableShader))
  endBlendMode()
  result.recordCall(NaylibCall(kind: nckEndBlend))
