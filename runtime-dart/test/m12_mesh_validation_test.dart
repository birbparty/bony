import 'package:bony/bony.dart';
import 'package:test/test.dart';

/// Load-time validation parity for mesh attachments (mirrors the Nim
/// validateMeshAttachment (a)-(g) checks in runtime-nim/src/bony/model.nim). A
/// rig that Nim rejects at load must also be rejected by the Dart loader with a
/// clean [FormatException], not accepted silently or crashed on later inside
/// buildDrawBatches / _skinMeshVertices.
String _rig(String meshBody) {
  return '''
{
  "skeleton": {"name": "mesh-val", "version": "1.0.0"},
  "bones": [
    {"name": "root"},
    {"name": "boneA", "parent": "root", "x": 10, "y": 0},
    {"name": "boneB", "parent": "root", "x": 0, "y": 10}
  ],
  "slots": [
    {"name": "mesh_slot", "bone": "root", "attachment": "mesh"}
  ],
  "meshAttachments": [$meshBody]
}
''';
}

void main() {
  test('accepts a well-formed weighted mesh', () {
    final data = loadBonyJson(_rig('''
      {"name": "mesh", "weighted": true,
       "vertices": [
         {"influences": [{"bone": "boneA", "bindX": 0, "bindY": 0, "weight": 0.5},
                         {"bone": "boneB", "bindX": 0, "bindY": 0, "weight": 0.5}]}
       ],
       "uvs": [0, 0], "triangles": [0, 0, 0]}'''));
    expect(data.meshAttachments, hasLength(1));
    expect(data.meshAttachments.single.weighted, isTrue);
  });

  test('rejects uvs count that does not match vertex count', () {
    expect(
      () => loadBonyJson(_rig('''
        {"name": "mesh", "weighted": false,
         "vertices": [{"x": 0, "y": 0}, {"x": 1, "y": 0}],
         "uvs": [0, 0], "triangles": [0, 1, 0]}''')),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a triangle count that is not a multiple of three', () {
    expect(
      () => loadBonyJson(_rig('''
        {"name": "mesh", "weighted": false,
         "vertices": [{"x": 0, "y": 0}],
         "uvs": [0, 0], "triangles": [0, 0]}''')),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a triangle index out of range', () {
    expect(
      () => loadBonyJson(_rig('''
        {"name": "mesh", "weighted": false,
         "vertices": [{"x": 0, "y": 0}],
         "uvs": [0, 0], "triangles": [0, 5, 0]}''')),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a weighted influence naming an unknown bone', () {
    expect(
      () => loadBonyJson(_rig('''
        {"name": "mesh", "weighted": true,
         "vertices": [{"influences": [{"bone": "ghost", "bindX": 0, "bindY": 0, "weight": 1.0}]}],
         "uvs": [0, 0], "triangles": [0, 0, 0]}''')),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects weighted influences that do not sum to one', () {
    expect(
      () => loadBonyJson(_rig('''
        {"name": "mesh", "weighted": true,
         "vertices": [{"influences": [{"bone": "boneA", "bindX": 0, "bindY": 0, "weight": 0.25},
                                      {"bone": "boneB", "bindX": 0, "bindY": 0, "weight": 0.25}]}],
         "uvs": [0, 0], "triangles": [0, 0, 0]}''')),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a vertex whose shape disagrees with the mesh weighted flag', () {
    // mesh.weighted = true but the vertex is unweighted (x/y).
    expect(
      () => loadBonyJson(_rig('''
        {"name": "mesh", "weighted": true,
         "vertices": [{"x": 0, "y": 0}],
         "uvs": [0, 0], "triangles": [0, 0, 0]}''')),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a uv coordinate outside 0..1', () {
    expect(
      () => loadBonyJson(_rig('''
        {"name": "mesh", "weighted": false,
         "vertices": [{"x": 0, "y": 0}],
         "uvs": [0, 2], "triangles": [0, 0, 0]}''')),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a mesh name that collides with a region name', () {
    final rig = '''
{
  "skeleton": {"name": "mesh-val", "version": "1.0.0"},
  "bones": [{"name": "root"}],
  "regions": [{"name": "dup", "width": 2, "height": 2}],
  "slots": [{"name": "s", "bone": "root", "attachment": "dup"}],
  "meshAttachments": [
    {"name": "dup", "weighted": false,
     "vertices": [{"x": 0, "y": 0}], "uvs": [0, 0], "triangles": [0, 0, 0]}
  ]
}
''';
    expect(() => loadBonyJson(rig), throwsA(isA<FormatException>()));
  });
}
