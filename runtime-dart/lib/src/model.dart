// Bony SkeletonData model: M1 static skeleton types + M2 world transform types.

class SkeletonHeader {
  const SkeletonHeader({required this.name, required this.version});
  final String name;
  final String version;
}

class BoneData {
  const BoneData({
    required this.name,
    required this.parent,
    required this.x,
    required this.y,
    required this.rotation,
    required this.scaleX,
    required this.scaleY,
    required this.shearX,
    required this.shearY,
    required this.inheritRotation,
    required this.inheritScale,
    required this.inheritReflection,
    required this.transformMode,
  });

  final String name;
  final String parent;
  final double x;
  final double y;
  final double rotation;
  final double scaleX;
  final double scaleY;
  final double shearX;
  final double shearY;
  final bool inheritRotation;
  final bool inheritScale;
  final bool inheritReflection;
  final String transformMode;
}

class SlotData {
  const SlotData({
    required this.name,
    required this.bone,
    required this.attachment,
  });

  final String name;
  final String bone;
  final String attachment;
}

class RegionAttachment {
  const RegionAttachment({
    required this.name,
    required this.width,
    required this.height,
  });

  final String name;
  final double width;
  final double height;
}

class PathConstraintData {
  const PathConstraintData({
    required this.name,
    required this.bone,
    required this.target,
    required this.path,
    required this.order,
  });

  final String name;
  final String bone;
  final String target;
  final String path;
  final int order;
}

class PathAttachment {
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

class SkeletonData {
  const SkeletonData({
    required this.header,
    required this.bones,
    required this.slots,
    required this.regions,
    required this.paths,
    required this.pathAttachments,
  });

  final SkeletonHeader header;
  final List<BoneData> bones;
  final List<SlotData> slots;
  final List<RegionAttachment> regions;
  final List<PathConstraintData> paths;
  final List<PathAttachment> pathAttachments;
}

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
