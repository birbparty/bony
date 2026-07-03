/// M4 clipping of draw-batch geometry against a convex clip polygon:
/// [clipDrawBatchPolygon] clips a region quad as one convex boundary ring, and
/// [clipDrawBatchTriangles] clips a mesh triangle *soup* per-triangle.
///
/// A fresh Dart port of the project-owned Sutherland-Hodgman convex clip
/// specified in `docs/clipping-attachment-contract.md` and implemented in the
/// Nim reference (`runtime-nim/src/bony/mesh/drawbatch_clipping.nim`). It
/// interpolates `u, v, r, g, b, a` at every clip-edge intersection, fan
/// re-triangulates the clipped polygon (pivot on vertex 0), and quantizes to
/// f32 at the output boundary — matching Nim within the `1e-4` tolerance.
library;

import 'deform.dart' show quantizeF32;
import 'model.dart' show DrawVertex;

const double _clipEpsilon = 1e-9;

/// A point of the clip polygon (world space).
class ClipPoint {
  const ClipPoint(this.x, this.y);
  final double x;
  final double y;
}

/// Result of clipping one draw-batch polygon.
///
/// `changed == false` means the subject is fully inside the clip polygon and the
/// caller must keep the batch's original vertices/indices. `changed == true`
/// means the batch was clipped; [vertices]/[indices] are the new (possibly
/// empty, when fully outside) fan-triangulated geometry.
class DrawBatchClip {
  const DrawBatchClip({
    required this.changed,
    this.vertices = const [],
    this.indices = const [],
  });

  final bool changed;
  final List<DrawVertex> vertices;
  final List<int> indices;
}

double _crossZ(double ax, double ay, double bx, double by) => ax * by - ay * bx;

double _signedArea(List<ClipPoint> polygon) {
  var area = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final next = polygon[(i + 1) % polygon.length];
    area += polygon[i].x * next.y - next.x * polygon[i].y;
  }
  return area * 0.5;
}

bool _inside(DrawVertex point, ClipPoint a, ClipPoint b, double orientation) {
  final side = _crossZ(b.x - a.x, b.y - a.y, point.x - a.x, point.y - a.y);
  return orientation > 0.0 ? side >= -_clipEpsilon : side <= _clipEpsilon;
}

DrawVertex _quantized(DrawVertex vtx) => DrawVertex(
      x: quantizeF32(vtx.x),
      y: quantizeF32(vtx.y),
      u: quantizeF32(vtx.u),
      v: quantizeF32(vtx.v),
      r: quantizeF32(vtx.r),
      g: quantizeF32(vtx.g),
      b: quantizeF32(vtx.b),
      a: quantizeF32(vtx.a),
    );

DrawVertex _intersection(
  DrawVertex start,
  DrawVertex finish,
  ClipPoint a,
  ClipPoint b,
) {
  final rx = finish.x - start.x;
  final ry = finish.y - start.y;
  final sx = b.x - a.x;
  final sy = b.y - a.y;
  final denom = _crossZ(rx, ry, sx, sy);
  if (denom.abs() <= _clipEpsilon) return _quantized(finish);
  final t = _crossZ(a.x - start.x, a.y - start.y, sx, sy) / denom;
  return _quantized(DrawVertex(
    x: start.x + rx * t,
    y: start.y + ry * t,
    u: start.u + (finish.u - start.u) * t,
    v: start.v + (finish.v - start.v) * t,
    r: start.r + (finish.r - start.r) * t,
    g: start.g + (finish.g - start.g) * t,
    b: start.b + (finish.b - start.b) * t,
    a: start.a + (finish.a - start.a) * t,
  ));
}

List<DrawVertex> _clipSubject(
  List<DrawVertex> subject,
  List<ClipPoint> clip,
  double orientation,
) {
  var result = List<DrawVertex>.from(subject);
  for (var edgeIndex = 0; edgeIndex < clip.length; edgeIndex++) {
    if (result.isEmpty) break;
    final a = clip[edgeIndex];
    final b = clip[(edgeIndex + 1) % clip.length];
    final input = result;
    result = <DrawVertex>[];
    var previous = input[input.length - 1];
    var previousInside = _inside(previous, a, b, orientation);
    for (final current in input) {
      final currentInside = _inside(current, a, b, orientation);
      if (currentInside) {
        if (!previousInside) result.add(_intersection(previous, current, a, b));
        result.add(_quantized(current));
      } else if (previousInside) {
        result.add(_intersection(previous, current, a, b));
      }
      previous = current;
      previousInside = currentInside;
    }
  }
  return result;
}

bool _allInside(
  List<DrawVertex> subject,
  List<ClipPoint> clip,
  double orientation,
) {
  for (var edgeIndex = 0; edgeIndex < clip.length; edgeIndex++) {
    final a = clip[edgeIndex];
    final b = clip[(edgeIndex + 1) % clip.length];
    for (final vertex in subject) {
      if (!_inside(vertex, a, b, orientation)) return false;
    }
  }
  return true;
}

// True when a single vertex is inside *every* clip edge (the whole convex clip
// polygon). Distinct from [_allInside], which tests every vertex of a subject.
bool _vertexInsideClip(DrawVertex vertex, List<ClipPoint> clip, double orientation) {
  for (var edgeIndex = 0; edgeIndex < clip.length; edgeIndex++) {
    final a = clip[edgeIndex];
    final b = clip[(edgeIndex + 1) % clip.length];
    if (!_inside(vertex, a, b, orientation)) return false;
  }
  return true;
}

/// Clip a convex draw-batch polygon (boundary order) against a convex clip
/// polygon in the same (world) space. See [DrawBatchClip].
DrawBatchClip clipDrawBatchPolygon(
  List<DrawVertex> subject,
  List<ClipPoint> clip,
) {
  if (clip.length < 3 || subject.length < 3) {
    return const DrawBatchClip(changed: false);
  }
  final orientation = _signedArea(clip);
  if (_allInside(subject, clip, orientation)) {
    return const DrawBatchClip(changed: false);
  }
  final polygon = _clipSubject(subject, clip, orientation);
  if (polygon.length < 3) return const DrawBatchClip(changed: true);
  final indices = <int>[];
  for (var fanIndex = 1; fanIndex < polygon.length - 1; fanIndex++) {
    indices
      ..add(0)
      ..add(fanIndex)
      ..add(fanIndex + 1);
  }
  return DrawBatchClip(changed: true, vertices: polygon, indices: indices);
}

/// Clip a triangle-*soup* draw batch (an explicit [indices] triangle list, e.g.
/// a skinned mesh) against a convex clip polygon in the same (world) space.
///
/// Unlike [clipDrawBatchPolygon], which reinterprets [subject] as a single
/// convex boundary ring, this clips **each triangle independently** so shared /
/// interior vertices and non-boundary index order are preserved. Each referenced
/// triangle is Sutherland-Hodgman clipped; each surviving clipped convex polygon
/// is fan-triangulated (pivot on its own clipped vertex 0) and appended to the
/// output with `u, v, r, g, b, a` interpolated at every clip-edge intersection
/// and quantized at the output boundary.
///
/// `changed == false` (caller keeps the original vertices/indices) iff every
/// referenced vertex is inside the clip polygon — no triangle would be cut.
/// Otherwise [vertices]/[indices] are the freshly re-triangulated per-triangle
/// geometry (each triangle emits its own vertices, so shared vertices are
/// duplicated across the triangles that use them). A batch entirely outside the
/// clip yields an empty (0-vertex / 0-index) `changed` result. Matches the Nim
/// reference `clipDrawBatchTriangles` within the `1e-4` tolerance.
DrawBatchClip clipDrawBatchTriangles(
  List<DrawVertex> subject,
  List<int> indices,
  List<ClipPoint> clip,
) {
  if (clip.length < 3 || indices.length < 3) {
    return const DrawBatchClip(changed: false);
  }
  final orientation = _signedArea(clip);
  // Fully-inside fast path: if no referenced vertex crosses the clip, no triangle
  // is cut, so the caller must keep the original vertices/indices untouched.
  var anyOutside = false;
  for (var triangle = 0; triangle + 2 < indices.length; triangle += 3) {
    for (var corner = 0; corner < 3; corner++) {
      if (!_vertexInsideClip(subject[indices[triangle + corner]], clip, orientation)) {
        anyOutside = true;
        break;
      }
    }
    if (anyOutside) break;
  }
  if (!anyOutside) return const DrawBatchClip(changed: false);
  final outVertices = <DrawVertex>[];
  final outIndices = <int>[];
  for (var triangle = 0; triangle + 2 < indices.length; triangle += 3) {
    final tri = <DrawVertex>[
      subject[indices[triangle]],
      subject[indices[triangle + 1]],
      subject[indices[triangle + 2]],
    ];
    final polygon = _clipSubject(tri, clip, orientation);
    if (polygon.length < 3) continue;
    final base = outVertices.length;
    outVertices.addAll(polygon);
    for (var fanIndex = 1; fanIndex < polygon.length - 1; fanIndex++) {
      outIndices
        ..add(base)
        ..add(base + fanIndex)
        ..add(base + fanIndex + 1);
    }
  }
  return DrawBatchClip(changed: true, vertices: outVertices, indices: outIndices);
}
