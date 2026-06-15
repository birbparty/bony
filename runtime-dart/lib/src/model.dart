// Bony SkeletonData model: M1 static skeleton types.

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
