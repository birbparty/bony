sealed class Attachment {
  const Attachment();

  String get name;
}

class RegionAttachment implements Attachment {
  const RegionAttachment({
    required this.name,
    required this.width,
    required this.height,
    this.texturePage = '',
    this.u0 = 0.0,
    this.v0 = 0.0,
    this.u1 = 1.0,
    this.v1 = 1.0,
    this.alphaMode = 'straight',
  });

  final String name;
  final double width;
  final double height;
  final String texturePage;
  final double u0;
  final double v0;
  final double u1;
  final double v1;
  final String alphaMode;
}

class PointAttachment implements Attachment {
  const PointAttachment({
    required this.name,
    required this.x,
    required this.y,
    required this.rotation,
  });

  final String name;
  final double x;
  final double y;
  final double rotation;
}

class BoundingBoxAttachment implements Attachment {
  const BoundingBoxAttachment({
    required this.name,
    required this.vertices,
  });

  final String name;

  /// Convex polygon as a flat `[x0, y0, x1, y1, ...]` list in the owning slot's
  /// bone-local space.
  final List<double> vertices;
}

class NestedRigAttachment implements Attachment {
  const NestedRigAttachment({
    required this.name,
    required this.skeleton,
    this.skin = '',
    this.animation = '',
  });

  final String name;
  final String skeleton;
  final String skin;
  final String animation;
}

class PathAttachment implements Attachment {
  const PathAttachment({
    required this.name,
    required this.p0x,
    required this.p0y,
    required this.p1x,
    required this.p1y,
    required this.p2x,
    required this.p2y,
    required this.p3x,
    required this.p3y,
  });

  final String name;
  final double p0x;
  final double p0y;
  final double p1x;
  final double p1y;
  final double p2x;
  final double p2y;
  final double p3x;
  final double p3y;
}

class ClippingAttachment implements Attachment {
  const ClippingAttachment({
    required this.name,
    required this.vertices,
    required this.untilSlot,
  });

  final String name;

  /// Convex polygon as a flat `[x0, y0, x1, y1, ...]` list in the owning slot's
  /// bone-local space.
  final List<double> vertices;

  /// Slot name at which the clip range stops (inclusive); empty clips to the end
  /// of draw order.
  final String untilSlot;
}

/// One bone influence on a weighted mesh vertex: the vertex's bind position in
/// `bone`'s local space and its blend weight. Mirrors the Nim `MeshInfluence`.
class MeshInfluence {
  const MeshInfluence({
    required this.bone,
    required this.bindX,
    required this.bindY,
    required this.weight,
  });

  final String bone;
  final double bindX;
  final double bindY;
  final double weight;
}

/// One mesh vertex: either a flat bone-local position (`x`,`y`, unweighted) or a
/// set of weighted bone `influences`. `weighted` agrees with the owning mesh's
/// `weighted` flag. Mirrors the Nim `MeshVertex`.
class MeshVertex {
  const MeshVertex.unweighted(this.x, this.y)
      : weighted = false,
        influences = const [];

  const MeshVertex.weighted(this.influences)
      : weighted = true,
        x = 0.0,
        y = 0.0;

  final bool weighted;
  final double x;
  final double y;
  final List<MeshInfluence> influences;
}

/// A per-vertex texture coordinate. Mirrors the Nim `MeshUv`.
class MeshUv {
  const MeshUv(this.u, this.v);

  final double u;
  final double v;
}

/// A slot-bound deformable triangle mesh with per-vertex texture coordinates and
/// either flat bone-local positions or per-vertex weighted bone influences
/// (skinning). Mirrors the Nim `MeshAttachment` and the prompt-19 contract.
class MeshAttachment implements Attachment {
  const MeshAttachment({
    required this.name,
    required this.weighted,
    required this.vertices,
    required this.uvs,
    required this.triangles,
  });

  final String name;

  /// Whether vertices carry per-vertex bone influences (skinning) rather than
  /// flat bone-local positions.
  final bool weighted;

  final List<MeshVertex> vertices;

  /// One texture coordinate per vertex (`uvs.length == vertices.length`).
  final List<MeshUv> uvs;

  /// Flat vertex-index triples (`triangles.length` is a multiple of 3).
  final List<int> triangles;
}
