// --- M7 deformer types ---

class ParameterAxis {
  const ParameterAxis({
    required this.name,
    required this.minValue,
    required this.maxValue,
    this.defaultValue = 0.0,
  });
  final String name;
  final double minValue;
  final double maxValue;
  final double defaultValue;
}

class ParameterSample {
  const ParameterSample({required this.name, required this.value});
  final String name;
  final double value;
}

class DeformerPoint {
  const DeformerPoint({required this.x, required this.y});
  final double x;
  final double y;
}

class WarpLattice {
  const WarpLattice({
    required this.rows,
    required this.cols,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.controlPoints,
  });
  final int rows;
  final int cols;
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;
  final List<DeformerPoint> controlPoints;

  WarpLattice copyWith({
    int? rows,
    int? cols,
    double? minX,
    double? minY,
    double? maxX,
    double? maxY,
    List<DeformerPoint>? controlPoints,
  }) =>
      WarpLattice(
        rows: rows ?? this.rows,
        cols: cols ?? this.cols,
        minX: minX ?? this.minX,
        minY: minY ?? this.minY,
        maxX: maxX ?? this.maxX,
        maxY: maxY ?? this.maxY,
        controlPoints: controlPoints ?? this.controlPoints,
      );
}

class RotationDeformerData {
  const RotationDeformerData({
    required this.pivotX,
    required this.pivotY,
    required this.angleDegrees,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.opacity = 1.0,
  });
  final double pivotX;
  final double pivotY;
  final double angleDegrees;
  final double scaleX;
  final double scaleY;
  final double opacity;

  RotationDeformerData copyWith({
    double? pivotX,
    double? pivotY,
    double? angleDegrees,
    double? scaleX,
    double? scaleY,
    double? opacity,
  }) =>
      RotationDeformerData(
        pivotX: pivotX ?? this.pivotX,
        pivotY: pivotY ?? this.pivotY,
        angleDegrees: angleDegrees ?? this.angleDegrees,
        scaleX: scaleX ?? this.scaleX,
        scaleY: scaleY ?? this.scaleY,
        opacity: opacity ?? this.opacity,
      );
}

enum DeformerKind { warp, rotation }

sealed class DeformerData {
  const DeformerData({
    required this.id,
    this.parent = '',
    required this.order,
  });
  final String id;
  final String parent;
  final int order;
  DeformerKind get kind;
}

class WarpDeformer extends DeformerData {
  const WarpDeformer({
    required super.id,
    super.parent = '',
    required super.order,
    required this.warp,
  });
  final WarpLattice warp;

  @override
  DeformerKind get kind => DeformerKind.warp;

  WarpDeformer copyWith({
    String? id,
    String? parent,
    int? order,
    WarpLattice? warp,
  }) =>
      WarpDeformer(
        id: id ?? this.id,
        parent: parent ?? this.parent,
        order: order ?? this.order,
        warp: warp ?? this.warp,
      );
}

class RotationDeformer extends DeformerData {
  const RotationDeformer({
    required super.id,
    super.parent = '',
    required super.order,
    required this.rotation,
  });
  final RotationDeformerData rotation;

  @override
  DeformerKind get kind => DeformerKind.rotation;

  RotationDeformer copyWith({
    String? id,
    String? parent,
    int? order,
    RotationDeformerData? rotation,
  }) =>
      RotationDeformer(
        id: id ?? this.id,
        parent: parent ?? this.parent,
        order: order ?? this.order,
        rotation: rotation ?? this.rotation,
      );
}

class Keyform {
  const Keyform({required this.coordinates, required this.values});
  final List<ParameterSample> coordinates;
  final List<double> values;
}

class KeyformBlend {
  const KeyformBlend({
    this.axes = const [],
    this.valueCount = 0,
    this.keyforms = const [],
  });
  final List<ParameterAxis> axes;
  final int valueCount;
  final List<Keyform> keyforms;
}

class DeformerRecord {
  const DeformerRecord({required this.deformer, required this.keyformBlend});
  final DeformerData deformer;
  final KeyformBlend keyformBlend;
}
