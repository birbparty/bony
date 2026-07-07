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
    this.skinRequired = false,
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
  final bool skinRequired;

  BoneData copyWith({
    String? name,
    String? parent,
    double? x,
    double? y,
    double? rotation,
    double? scaleX,
    double? scaleY,
    double? shearX,
    double? shearY,
    bool? inheritRotation,
    bool? inheritScale,
    bool? inheritReflection,
    String? transformMode,
    bool? skinRequired,
  }) {
    return BoneData(
      name: name ?? this.name,
      parent: parent ?? this.parent,
      x: x ?? this.x,
      y: y ?? this.y,
      rotation: rotation ?? this.rotation,
      scaleX: scaleX ?? this.scaleX,
      scaleY: scaleY ?? this.scaleY,
      shearX: shearX ?? this.shearX,
      shearY: shearY ?? this.shearY,
      inheritRotation: inheritRotation ?? this.inheritRotation,
      inheritScale: inheritScale ?? this.inheritScale,
      inheritReflection: inheritReflection ?? this.inheritReflection,
      transformMode: transformMode ?? this.transformMode,
      skinRequired: skinRequired ?? this.skinRequired,
    );
  }
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
