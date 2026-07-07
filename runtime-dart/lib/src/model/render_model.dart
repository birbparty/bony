/// 2D affine world transform matrix (column-major: [a c tx / b d ty / 0 0 1]).
class Affine2 {
  const Affine2({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.tx,
    required this.ty,
  });

  final double a;
  final double b;
  final double c;
  final double d;
  final double tx;
  final double ty;
}

class DrawVertex {
  const DrawVertex({
    required this.x,
    required this.y,
    required this.u,
    required this.v,
    required this.r,
    required this.g,
    required this.b,
    required this.a,
  });

  final double x;
  final double y;
  final double u;
  final double v;
  final double r;
  final double g;
  final double b;
  final double a;
}

class DrawBatch {
  const DrawBatch({
    required this.slot,
    required this.bone,
    required this.attachment,
    required this.blendMode,
    required this.texturePage,
    required this.clipId,
    required this.world,
    required this.vertices,
    required this.indices,
  });

  final String slot;
  final String bone;
  final String attachment;
  final String blendMode;
  final String texturePage;
  final String clipId;
  final Affine2 world;
  final List<DrawVertex> vertices;
  final List<int> indices;
}
