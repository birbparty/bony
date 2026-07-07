part of 'loader.dart';

ParameterAxis _parseParameter(Map<String, dynamic> j) {
  return ParameterAxis(
    name: _required<String>(j['name'], 'parameter.name'),
    minValue: _required<num>(j['min'], 'parameter.min').toDouble(),
    maxValue: _required<num>(j['max'], 'parameter.max').toDouble(),
    defaultValue: (j['default'] as num?)?.toDouble() ?? 0.0,
  );
}

DeformerRecord _parseDeformer(
  Map<String, dynamic> j,
  Map<String, ParameterAxis> paramsByName,
) {
  final id = _required<String>(j['id'], 'deformer.id');
  final parent = (j['parent'] as String?) ?? '';
  final order = (j['order'] as num?)?.toInt() ?? 0;
  final kindStr = _required<String>(j['kind'], 'deformer.kind');

  DeformerData deformerData;
  if (kindStr == 'warp') {
    final wj = _required<Map<String, dynamic>>(j['warp'], 'deformer.warp');
    final rows = (_required<num>(wj['rows'], 'warp.rows')).toInt();
    final cols = (_required<num>(wj['cols'], 'warp.cols')).toInt();
    final cpRaw =
        _required<List<dynamic>>(wj['controlPoints'], 'warp.controlPoints');
    final controlPoints = cpRaw.map((p) {
      final pm = p as Map<String, dynamic>;
      return DeformerPoint(
        x: _required<num>(pm['x'], 'warp.controlPoint.x').toDouble(),
        y: _required<num>(pm['y'], 'warp.controlPoint.y').toDouble(),
      );
    }).toList();
    deformerData = WarpDeformer(
      id: id,
      parent: parent,
      order: order,
      warp: WarpLattice(
        rows: rows,
        cols: cols,
        minX: _required<num>(wj['minX'], 'warp.minX').toDouble(),
        minY: _required<num>(wj['minY'], 'warp.minY').toDouble(),
        maxX: _required<num>(wj['maxX'], 'warp.maxX').toDouble(),
        maxY: _required<num>(wj['maxY'], 'warp.maxY').toDouble(),
        controlPoints: controlPoints,
      ),
    );
  } else if (kindStr == 'rotation') {
    final rj =
        _required<Map<String, dynamic>>(j['rotation'], 'deformer.rotation');
    deformerData = RotationDeformer(
      id: id,
      parent: parent,
      order: order,
      rotation: RotationDeformerData(
        pivotX: _required<num>(rj['pivotX'], 'rotation.pivotX').toDouble(),
        pivotY: _required<num>(rj['pivotY'], 'rotation.pivotY').toDouble(),
        angleDegrees:
            _required<num>(rj['angleDegrees'], 'rotation.angleDegrees')
                .toDouble(),
        scaleX: (rj['scaleX'] as num?)?.toDouble() ?? 1.0,
        scaleY: (rj['scaleY'] as num?)?.toDouble() ?? 1.0,
        opacity: (rj['opacity'] as num?)?.toDouble() ?? 1.0,
      ),
    );
  } else {
    throw FormatException('deformer.kind unknown: $kindStr');
  }

  final kbj = j['keyformBlend'] as Map<String, dynamic>?;
  if (kbj == null) {
    return DeformerRecord(
        deformer: deformerData, keyformBlend: const KeyformBlend());
  }

  final axisNames = _required<List<dynamic>>(kbj['axes'], 'keyformBlend.axes');
  final axes = axisNames.map((n) {
    final name = n as String;
    final axis = paramsByName[name];
    if (axis == null)
      throw FormatException('keyformBlend references unknown parameter: $name');
    return axis;
  }).toList();

  final kfList =
      _required<List<dynamic>>(kbj['keyforms'], 'keyformBlend.keyforms');
  final keyforms = kfList.map((kf) {
    final kfm = kf as Map<String, dynamic>;
    final coordMap = _required<Map<String, dynamic>>(
        kfm['coordinates'], 'keyform.coordinates');
    final coordinates = axes.map((a) {
      final v = coordMap[a.name];
      if (v == null)
        throw FormatException('keyform missing coordinate: ${a.name}');
      return ParameterSample(name: a.name, value: (v as num).toDouble());
    }).toList();
    final vals = _required<List<dynamic>>(kfm['values'], 'keyform.values');
    return Keyform(
      coordinates: coordinates,
      values: vals.map((v) => (v as num).toDouble()).toList(),
    );
  }).toList();

  final valueCount = keyforms.isEmpty ? 0 : keyforms[0].values.length;
  return DeformerRecord(
    deformer: deformerData,
    keyformBlend:
        KeyformBlend(axes: axes, valueCount: valueCount, keyforms: keyforms),
  );
}

PathAttachment _parsePathAttachment(Map<String, dynamic> j) {
  return PathAttachment(
    name: _required<String>(j['name'], 'pathAttachment.name'),
    p0x: _required<num>(j['p0x'], 'pathAttachment.p0x').toDouble(),
    p0y: _required<num>(j['p0y'], 'pathAttachment.p0y').toDouble(),
    p1x: _required<num>(j['p1x'], 'pathAttachment.p1x').toDouble(),
    p1y: _required<num>(j['p1y'], 'pathAttachment.p1y').toDouble(),
    p2x: _required<num>(j['p2x'], 'pathAttachment.p2x').toDouble(),
    p2y: _required<num>(j['p2y'], 'pathAttachment.p2y').toDouble(),
    p3x: _required<num>(j['p3x'], 'pathAttachment.p3x').toDouble(),
    p3y: _required<num>(j['p3y'], 'pathAttachment.p3y').toDouble(),
  );
}
