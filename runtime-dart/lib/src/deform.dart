// M7 deformer algorithm: warp/rotation deformers with keyform parameter blending.
//
// Ports runtime-nim/src/bony/deform/deformers.nim and keyforms.nim exactly,
// including float32 quantization at every output step for cross-platform
// determinism.

import 'dart:math' as math;
import 'dart:typed_data' show ByteData, Endian;
import 'model.dart';

// Round-trips x through float32 for cross-platform determinism.
// All deformer outputs are quantized through this function to match Nim reference.
double quantizeF32(double x) {
  final bd = ByteData(4);
  bd.setFloat32(0, x, Endian.little);
  final v = bd.getFloat32(0, Endian.little).toDouble();
  // Normalize negative zero to positive zero, matching the Nim reference's
  // quantizeF32 (docs/binary-canonicalization.md; bony-iw6b): a raw .bnb f32
  // encode preserves -0.0's sign bit (0x80000000) while the JSON emitter collapses
  // it to "0", so an un-normalized -0.0 byte-diverges json<->bnb. NOTE: this
  // funnels the anim/deform math f32s; the JSON/.bnb bind-pose load path in
  // loader.dart does not yet route through quantizeF32 (tracked by bony-24up).
  return v == 0.0 ? 0.0 : v;
}

// Binomial coefficient C(n,k).
double _choose(int n, int k) {
  if (k < 0 || k > n) return 0.0;
  final smaller = math.min(k, n - k);
  if (smaller == 0) return 1.0;
  var num = 1.0;
  var den = 1.0;
  for (var i = 1; i <= smaller; i++) {
    num *= (n - smaller + i).toDouble();
    den *= i.toDouble();
  }
  return num / den;
}

// Bernstein basis polynomial B(i, degree, t) = C(degree,i) * t^i * (1-t)^(degree-i).
double _bernstein(int i, int degree, double t) =>
    _choose(degree, i) *
    math.pow(t, i.toDouble()) *
    math.pow(1.0 - t, (degree - i).toDouble());

// Apply warp lattice via Bernstein surface evaluation.
// u,v must be in [0,1]; outside returns vertex unchanged.
// New position is computed entirely from control points — vertex x/y only flows
// through unchanged (texture coords are always preserved).
({double x, double y}) _applyWarpAt(
  double vx,
  double vy,
  WarpLattice lattice,
  double u,
  double v,
) {
  if (u < 0.0 || u > 1.0 || v < 0.0 || v > 1.0) return (x: vx, y: vy);
  final rowDegree = lattice.rows - 1;
  final colDegree = lattice.cols - 1;
  var nx = 0.0;
  var ny = 0.0;
  for (var row = 0; row <= rowDegree; row++) {
    final bv = _bernstein(row, rowDegree, v);
    for (var col = 0; col <= colDegree; col++) {
      final w = bv * _bernstein(col, colDegree, u);
      final pt = lattice.controlPoints[row * lattice.cols + col];
      nx += w * pt.x;
      ny += w * pt.y;
    }
  }
  return (x: quantizeF32(nx), y: quantizeF32(ny));
}

// Apply rotation deformer: rotate-then-opacity-blend vertex position.
({double x, double y}) _applyRotation(
  double vx,
  double vy,
  RotationDeformerData rot,
) {
  final angle = rot.angleDegrees * math.pi / 180.0;
  final c = math.cos(angle);
  final s = math.sin(angle);
  final lx = (vx - rot.pivotX) * rot.scaleX;
  final ly = (vy - rot.pivotY) * rot.scaleY;
  final rx = rot.pivotX + lx * c - ly * s;
  final ry = rot.pivotY + lx * s + ly * c;
  return (
    x: quantizeF32(vx + (rx - vx) * rot.opacity),
    y: quantizeF32(vy + (ry - vy) * rot.opacity),
  );
}

// Apply a deformer to a single point (used for control point transformation).
// Warp path uses current-point coords for u,v lookup (not setup-vertex invariant).
({double x, double y}) _applyToPoint(
  double px,
  double py,
  DeformerData deformer,
) {
  if (deformer.kind == DeformerKind.rotation) {
    return _applyRotation(px, py, deformer.rotation!);
  }
  final w = deformer.warp!;
  final u = (px - w.minX) / (w.maxX - w.minX);
  final v = (py - w.minY) / (w.maxY - w.minY);
  return _applyWarpAt(px, py, w, u, v);
}

// Compute AABB of the four lattice-corner points after transformation by parent.
({double minX, double minY, double maxX, double maxY}) _transformedBounds(
  WarpLattice lattice,
  DeformerData parent,
) {
  final corners = [
    _applyToPoint(quantizeF32(lattice.minX), quantizeF32(lattice.minY), parent),
    _applyToPoint(quantizeF32(lattice.maxX), quantizeF32(lattice.minY), parent),
    _applyToPoint(quantizeF32(lattice.maxX), quantizeF32(lattice.maxY), parent),
    _applyToPoint(quantizeF32(lattice.minX), quantizeF32(lattice.maxY), parent),
  ];
  var minX = corners[0].x, minY = corners[0].y;
  var maxX = corners[0].x, maxY = corners[0].y;
  for (var i = 1; i < 4; i++) {
    if (corners[i].x < minX) minX = corners[i].x;
    if (corners[i].y < minY) minY = corners[i].y;
    if (corners[i].x > maxX) maxX = corners[i].x;
    if (corners[i].y > maxY) maxY = corners[i].y;
  }
  return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

// Transform a child deformer's geometry into the effective parent's frame.
// For warp: transform every control point and recompute AABB.
// For rotation: transform only the pivot point; angle/scale/opacity unchanged.
DeformerData _transformFrame(DeformerData deformer, DeformerData parent) {
  if (deformer.kind == DeformerKind.warp) {
    final w = deformer.warp!;
    final pts = w.controlPoints.map((p) {
      final r = _applyToPoint(p.x, p.y, parent);
      return DeformerPoint(x: quantizeF32(r.x), y: quantizeF32(r.y));
    }).toList();
    final b = _transformedBounds(w, parent);
    return DeformerData(
      id: deformer.id,
      parent: deformer.parent,
      order: deformer.order,
      kind: DeformerKind.warp,
      warp: WarpLattice(
        rows: w.rows,
        cols: w.cols,
        minX: b.minX,
        minY: b.minY,
        maxX: b.maxX,
        maxY: b.maxY,
        controlPoints: pts,
      ),
    );
  } else {
    final rot = deformer.rotation!;
    final p = _applyToPoint(rot.pivotX, rot.pivotY, parent);
    return DeformerData(
      id: deformer.id,
      parent: deformer.parent,
      order: deformer.order,
      kind: DeformerKind.rotation,
      rotation: RotationDeformerData(
        pivotX: quantizeF32(p.x),
        pivotY: quantizeF32(p.y),
        angleDegrees: rot.angleDegrees,
        scaleX: rot.scaleX,
        scaleY: rot.scaleY,
        opacity: rot.opacity,
      ),
    );
  }
}

// Build a lookup key from axis names + coordinate values, null-byte delimited.
String _coordinateKey(List<ParameterAxis> axes, List<double> coords) {
  final buf = StringBuffer();
  for (var i = 0; i < axes.length; i++) {
    buf.write(axes[i].name);
    buf.write('=');
    buf.write(coords[i]);
    buf.write('\x00');
  }
  return buf.toString();
}

// Bracket [value] between adjacent entries in [values] (must be sorted).
// Returns (low, high, t) where t ∈ [0,1].
({double low, double high, double t}) _bracket(List<double> values, double value) {
  if (values.isEmpty) {
    throw const FormatException('keyform axis has no coordinate values');
  }
  if (value <= values[0]) return (low: values[0], high: values[0], t: 0.0);
  for (var i = 0; i < values.length - 1; i++) {
    if (value <= values[i + 1]) {
      final lo = values[i], hi = values[i + 1];
      if (hi == lo) return (low: lo, high: hi, t: 0.0);
      return (low: lo, high: hi, t: (value - lo) / (hi - lo));
    }
  }
  final last = values.last;
  return (low: last, high: last, t: 0.0);
}

// Sample blended float values from [blend] at the given [samples].
// Returns blend.valueCount values, each quantized through float32.
List<double> sampleKeyformValues(
  KeyformBlend blend,
  List<ParameterSample> samples,
) {
  // Collect unique sorted coordinate values per axis.
  final valuesByAxis =
      List<List<double>>.generate(blend.axes.length, (_) => []);
  for (final kf in blend.keyforms) {
    for (var ai = 0; ai < blend.axes.length; ai++) {
      final axisName = blend.axes[ai].name;
      final coordSample = kf.coordinates.where((s) => s.name == axisName).firstOrNull;
      if (coordSample == null) {
        throw FormatException('keyform missing coordinate for axis "$axisName"');
      }
      final coord = coordSample.value;
      if (!valuesByAxis[ai].contains(coord)) valuesByAxis[ai].add(coord);
    }
  }
  for (final vs in valuesByAxis) {
    vs.sort();
  }

  // Build keyform table: coordinate-key → Keyform.
  final keyformTable = <String, Keyform>{};
  for (final kf in blend.keyforms) {
    final coords = blend.axes.map((a) {
      final s = kf.coordinates.where((s) => s.name == a.name).firstOrNull;
      if (s == null) throw FormatException('keyform missing coordinate for axis "${a.name}"');
      return s.value;
    }).toList();
    keyformTable[_coordinateKey(blend.axes, coords)] = kf;
  }

  // Bracket each axis value.
  final lows = List<double>.filled(blend.axes.length, 0.0);
  final activeAxes =
      <({int axisIndex, double low, double high, double t})>[];

  for (var ai = 0; ai < blend.axes.length; ai++) {
    final axisName = blend.axes[ai].name;
    final sample = samples.where((s) => s.name == axisName).firstOrNull;
    if (sample == null) {
      throw FormatException('keyformBlend: missing sample for axis "$axisName"');
    }
    final value = sample.value;
    final br = _bracket(valuesByAxis[ai], value);
    lows[ai] = br.low;
    if (br.low != br.high) {
      activeAxes.add((
        axisIndex: ai,
        low: br.low,
        high: br.high,
        t: br.t,
      ));
    }
  }

  const maxVaryingAxes = 20;
  if (activeAxes.length > maxVaryingAxes) {
    throw FormatException(
      'keyformBlend: too many varying axes (${activeAxes.length} > $maxVaryingAxes)',
    );
  }

  final result = List<double>.filled(blend.valueCount, 0.0);
  final cornerCount = 1 << activeAxes.length;
  for (var mask = 0; mask < cornerCount; mask++) {
    final corner = List<double>.from(lows);
    var weight = 1.0;
    for (var ai = 0; ai < activeAxes.length; ai++) {
      final axis = activeAxes[ai];
      if ((mask >> ai) & 1 == 0) {
        corner[axis.axisIndex] = axis.low;
        weight *= 1.0 - axis.t;
      } else {
        corner[axis.axisIndex] = axis.high;
        weight *= axis.t;
      }
    }
    if (weight == 0.0) continue;
    final key = _coordinateKey(blend.axes, corner);
    final kf = keyformTable[key];
    if (kf == null) throw FormatException('missing keyform corner: $key');
    for (var vi = 0; vi < blend.valueCount; vi++) {
      result[vi] += kf.values[vi] * weight;
    }
  }
  for (var vi = 0; vi < result.length; vi++) {
    result[vi] = quantizeF32(result[vi]);
  }
  return result;
}

// Convert flat blended float list to DeformerPoint list (x,y pairs).
List<DeformerPoint> sampleKeyformPoints(
  KeyformBlend blend,
  List<ParameterSample> samples,
) {
  final values = sampleKeyformValues(blend, samples);
  final pts = <DeformerPoint>[];
  for (var i = 0; i < values.length; i += 2) {
    pts.add(DeformerPoint(
      x: quantizeF32(values[i]),
      y: quantizeF32(values[i + 1]),
    ));
  }
  return pts;
}

// Build effective (parameter-sampled) deformers from DeformerRecords.
// Warp deformers with a keyformBlend get their control points replaced by the
// blend output at [samples]. Rotation deformers (and blendless warps) pass through.
List<DeformerData> effectiveDeformers(
  List<DeformerRecord> records,
  List<ParameterSample> samples,
) {
  final result = <DeformerData>[];
  for (final rec in records) {
    final blend = rec.keyformBlend;
    if (blend.axes.isNotEmpty &&
        blend.keyforms.isNotEmpty &&
        rec.deformer.kind == DeformerKind.warp) {
      final pts = sampleKeyformPoints(blend, samples);
      final w = rec.deformer.warp!;
      result.add(DeformerData(
        id: rec.deformer.id,
        parent: rec.deformer.parent,
        order: rec.deformer.order,
        kind: DeformerKind.warp,
        warp: WarpLattice(
          rows: w.rows,
          cols: w.cols,
          minX: w.minX,
          minY: w.minY,
          maxX: w.maxX,
          maxY: w.maxY,
          controlPoints: pts,
        ),
      ));
    } else {
      result.add(rec.deformer);
    }
  }
  return result;
}

// Apply a list of deformers (in order of the order field) to vertex positions.
// setup: the original (pre-deformation) positions — used for u,v warp lookup.
// result: the current positions, updated in-place across deformers.
//
// Key invariant from Nim reference: u,v for warp lookup always come from the
// SETUP (original) vertex positions using the ORIGINAL deformer bounds, while
// the Bernstein is applied to the CURRENT (already-deformed) vertex using the
// EFFECTIVE (possibly parent-transformed) control points.
List<({double x, double y})> applyDeformers(
  List<({double x, double y})> vertices,
  List<DeformerData> deformers,
) {
  if (deformers.isEmpty) return vertices;
  final ordered = List<DeformerData>.from(deformers)
    ..sort((a, b) => a.order.compareTo(b.order));
  final setup = List<({double x, double y})>.from(vertices);
  var result = List<({double x, double y})>.from(vertices);
  final effectiveById = <String, DeformerData>{};

  for (final deformer in ordered) {
    final DeformerData effective;
    if (deformer.parent.isEmpty) {
      effective = deformer;
    } else {
      final parentEffective = effectiveById[deformer.parent];
      if (parentEffective == null) {
        throw FormatException(
          'applyDeformers: parent "${deformer.parent}" not found for deformer "${deformer.id}"',
        );
      }
      effective = _transformFrame(deformer, parentEffective);
    }

    if (effective.kind == DeformerKind.warp) {
      final ew = effective.warp!;
      // u,v from ORIGINAL deformer bounds + SETUP vertex positions.
      final dw = deformer.warp!;
      final rangeX = dw.maxX - dw.minX;
      final rangeY = dw.maxY - dw.minY;
      for (var i = 0; i < result.length; i++) {
        final u = (setup[i].x - dw.minX) / rangeX;
        final v = (setup[i].y - dw.minY) / rangeY;
        final r = _applyWarpAt(result[i].x, result[i].y, ew, u, v);
        result[i] = r;
      }
    } else {
      final rot = effective.rotation!;
      for (var i = 0; i < result.length; i++) {
        result[i] = _applyRotation(result[i].x, result[i].y, rot);
      }
    }
    effectiveById[deformer.id] = effective;
  }
  return result;
}
