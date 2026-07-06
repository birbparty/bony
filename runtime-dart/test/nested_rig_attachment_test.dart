import 'dart:typed_data' show Uint8List;

import 'package:bony/bony.dart';
import 'package:test/test.dart';

void _writeVaruint(List<int> out, int value) {
  var v = value;
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
}

void _writeString(List<int> out, String value) {
  final units = value.codeUnits;
  _writeVaruint(out, units.length);
  out.addAll(units);
}

void _writeProp(List<int> out, int key, List<int> payload) {
  _writeVaruint(out, key);
  _writeVaruint(out, payload.length);
  out.addAll(payload);
}

List<int> _str(int index) => [index];

Uint8List _nestedRigBnb() {
  final out = <int>[
    0x42, 0x4f, 0x4e, 0x59, // BONY
    0x00, // version
    0x02, // string table present
    0x00, // empty ToC; semantic loader uses per-property byte lengths.
  ];
  final strings = [
    'host',
    'root',
    'nestedSlot',
    'nested_face',
    'faceRig',
    'neutral',
    'blink',
  ];
  _writeVaruint(out, strings.length);
  for (final value in strings) {
    _writeString(out, value);
  }

  _writeVaruint(out, 1); // skeleton
  _writeProp(out, 1, _str(0)); // name
  out.add(0);

  _writeVaruint(out, 2); // bone
  _writeProp(out, 1, _str(1)); // name
  out.add(0);

  _writeVaruint(out, 1000); // slot
  _writeProp(out, 1, _str(2)); // name
  _writeProp(out, 1012, _str(1)); // bone
  _writeProp(out, 1013, _str(3)); // attachment
  out.add(0);

  _writeVaruint(out, 3005); // nestedRigAttachment
  _writeProp(out, 1, _str(3)); // name
  _writeProp(out, 3012, _str(4)); // nestedSkeleton
  _writeProp(out, 3013, _str(5)); // nestedSkin
  _writeProp(out, 3014, _str(6)); // nestedAnimation
  out.add(0);

  out.add(0); // object stream terminator
  return Uint8List.fromList(out);
}

const _nestedRigJson = '''
{
  "skeleton": {"name": "host", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [{"name": "nestedSlot", "bone": "root", "attachment": "nested_face"}],
  "nestedRigAttachments": [
    {"name": "nested_face", "skeleton": "faceRig", "skin": "neutral", "animation": "blink"}
  ],
  "skins": [
    {
      "name": "default",
      "entries": [
        {"slot": "nestedSlot", "attachment": "nested_face", "target": "nested_face"}
      ]
    }
  ]
}
''';

const double _tol = 1e-4;

void _expectClose(double actual, double expected, String label) {
  expect((actual - expected).abs(), lessThanOrEqualTo(_tol),
      reason: '$label: actual=$actual expected=$expected');
}

BoneData _bone(
  String name, {
  String parent = '',
  double x = 0.0,
  double y = 0.0,
}) =>
    BoneData(
      name: name,
      parent: parent,
      x: x,
      y: y,
      rotation: 0.0,
      scaleX: 1.0,
      scaleY: 1.0,
      shearX: 0.0,
      shearY: 0.0,
      inheritRotation: true,
      inheritScale: true,
      inheritReflection: true,
      transformMode: 'normal',
    );

SlotData _slot(String name, String bone, String attachment) =>
    SlotData(name: name, bone: bone, attachment: attachment);

RegionAttachment _region(String name, double width, double height) =>
    RegionAttachment(name: name, width: width, height: height);

SkeletonData _skeleton({
  required String name,
  required List<BoneData> bones,
  List<SlotData> slots = const [],
  List<RegionAttachment> regions = const [],
  List<ClippingAttachment> clippingAttachments = const [],
  List<NestedRigAttachment> nestedRigAttachments = const [],
  List<SkinData> skins = const [],
}) =>
    SkeletonData(
      header: SkeletonHeader(name: name, version: '1.0.0'),
      bones: bones,
      slots: slots,
      regions: regions,
      paths: const [],
      pathAttachments: const [],
      clippingAttachments: clippingAttachments,
      nestedRigAttachments: nestedRigAttachments,
      skins: skins,
    );

void main() {
  group('nested rig attachments', () {
    test('loads from JSON and remains invisible to draw batches', () {
      final data = loadBonyJson(_nestedRigJson);
      expect(data.nestedRigAttachments, hasLength(1));
      final nested = data.nestedRigAttachments.single;
      expect(nested.name, 'nested_face');
      expect(nested.skeleton, 'faceRig');
      expect(nested.skin, 'neutral');
      expect(nested.animation, 'blink');
      expect(buildDrawBatches(data), isEmpty);
    });

    test('loads from .bnb', () {
      final data = loadBonyBnb(_nestedRigBnb());
      expect(data.nestedRigAttachments, hasLength(1));
      final nested = data.nestedRigAttachments.single;
      expect(nested.name, 'nested_face');
      expect(nested.skeleton, 'faceRig');
      expect(nested.skin, 'neutral');
      expect(nested.animation, 'blink');
      expect(buildDrawBatches(data), isEmpty);
    });

    test('rejects malformed nested rig attachments', () {
      const base =
          '{"skeleton":{"name":"host"},"bones":[{"name":"root"}],"slots":[{"name":"nestedSlot","bone":"root","attachment":"nested_face"}],"nestedRigAttachments":[REPLACE]}';
      expect(
        () => loadBonyJson(
            base.replaceFirst('REPLACE', '{"name":"","skeleton":"faceRig"}')),
        throwsFormatException,
      );
      expect(
        () => loadBonyJson(base.replaceFirst(
            'REPLACE', '{"name":"nested_face","skeleton":""}')),
        throwsFormatException,
      );
      expect(
        () => loadBonyJson(base.replaceFirst('REPLACE',
            '{"name":"nested_face","skeleton":"a"},{"name":"nested_face","skeleton":"b"}')),
        throwsFormatException,
      );
      expect(
        () => loadBonyJson(
            '{"skeleton":{"name":"host"},"bones":[{"name":"root"}],"slots":[{"name":"slot","bone":"root","attachment":"shared"}],"regions":[{"name":"shared","width":1,"height":1}],"nestedRigAttachments":[{"name":"shared","skeleton":"faceRig"}]}'),
        throwsFormatException,
      );
    });

    test('composes host-resolved nested rig setup draw batches', () {
      final host = _skeleton(
        name: 'host',
        bones: [_bone('root', x: 10.0, y: 20.0)],
        slots: [_slot('nestedSlot', 'root', 'nested_face')],
        nestedRigAttachments: const [
          NestedRigAttachment(name: 'nested_face', skeleton: 'faceRig'),
        ],
      );
      final child = _skeleton(
        name: 'child',
        bones: [_bone('root', x: 1.0)],
        slots: [_slot('childSlot', 'root', 'face')],
        regions: [_region('face', 2.0, 2.0)],
      );
      final childOnly = buildDrawBatches(child);
      final batches = buildNestedDrawBatches(host, {'faceRig': child});

      expect(buildDrawBatches(host), isEmpty);
      expect(childOnly, hasLength(1));
      expect(batches, hasLength(1));
      expect(batches[0].slot, 'childSlot');
      expect(batches[0].bone, 'root');
      expect(batches[0].attachment, 'face');
      _expectClose(batches[0].world.tx, 11.0, 'composed world.tx');
      _expectClose(batches[0].world.ty, 20.0, 'composed world.ty');
      _expectClose(batches[0].vertices[0].x, 10.0, 'v0.x');
      _expectClose(batches[0].vertices[0].y, 19.0, 'v0.y');
      _expectClose(batches[0].vertices[2].x, 12.0, 'v2.x');
      _expectClose(batches[0].vertices[2].y, 21.0, 'v2.y');
      expect((batches[0].vertices[0].x - childOnly[0].vertices[0].x).abs(),
          greaterThan(1e-4));
    });

    test('uses default and explicit nested child skins', () {
      final child = _skeleton(
        name: 'child',
        bones: [_bone('root')],
        slots: [_slot('face', 'root', 'face')],
        regions: [
          _region('defaultFace', 2.0, 2.0),
          _region('fancyFace', 4.0, 2.0),
        ],
        skins: const [
          SkinData(name: 'default', entries: [
            SkinEntryData(
                slot: 'face', attachment: 'face', target: 'defaultFace'),
          ]),
          SkinData(name: 'fancy', entries: [
            SkinEntryData(
                slot: 'face', attachment: 'face', target: 'fancyFace'),
          ]),
        ],
      );
      final host = _skeleton(
        name: 'host',
        bones: [_bone('root')],
        slots: [
          _slot('defaultSlot', 'root', 'nested_default'),
          _slot('fancySlot', 'root', 'nested_fancy'),
        ],
        nestedRigAttachments: const [
          NestedRigAttachment(name: 'nested_default', skeleton: 'faceRig'),
          NestedRigAttachment(
              name: 'nested_fancy', skeleton: 'faceRig', skin: 'fancy'),
        ],
        skins: const [
          SkinData(name: 'default', entries: [
            SkinEntryData(
                slot: 'defaultSlot',
                attachment: 'nested_default',
                target: 'nested_default'),
            SkinEntryData(
                slot: 'fancySlot',
                attachment: 'nested_fancy',
                target: 'nested_fancy'),
          ]),
        ],
      );
      final batches = buildNestedDrawBatches(host, {'faceRig': child});

      expect(batches, hasLength(2));
      expect(batches[0].attachment, 'defaultFace');
      _expectClose(batches[0].vertices[0].x, -1.0, 'default v0.x');
      _expectClose(batches[0].vertices[2].x, 1.0, 'default v2.x');
      expect(batches[1].attachment, 'fancyFace');
      _expectClose(batches[1].vertices[0].x, -2.0, 'fancy v0.x');
      _expectClose(batches[1].vertices[2].x, 2.0, 'fancy v2.x');
    });

    test('rejects missing child skeletons, unknown child skins, and cycles',
        () {
      final missingHost = _skeleton(
        name: 'host',
        bones: [_bone('root')],
        slots: [_slot('nestedSlot', 'root', 'nested_face')],
        nestedRigAttachments: const [
          NestedRigAttachment(name: 'nested_face', skeleton: 'faceRig'),
        ],
      );
      final missingSkinHost = _skeleton(
        name: 'host',
        bones: [_bone('root')],
        slots: [_slot('nestedSlot', 'root', 'nested_face')],
        nestedRigAttachments: const [
          NestedRigAttachment(
              name: 'nested_face', skeleton: 'faceRig', skin: 'missing'),
        ],
      );
      final plainChild = _skeleton(
        name: 'child',
        bones: [_bone('root')],
        slots: [_slot('childSlot', 'root', 'face')],
        regions: [_region('face', 2.0, 2.0)],
      );
      final recursiveChild = _skeleton(
        name: 'recursive',
        bones: [_bone('root')],
        slots: [_slot('selfSlot', 'root', 'nested_self')],
        nestedRigAttachments: const [
          NestedRigAttachment(name: 'nested_self', skeleton: 'faceRig'),
        ],
      );

      expect(() => buildNestedDrawBatches(missingHost, const {}),
          throwsFormatException);
      expect(
        () => buildNestedDrawBatches(missingSkinHost, {'faceRig': plainChild}),
        throwsFormatException,
      );
      expect(
        () => buildNestedDrawBatches(missingHost, {'faceRig': recursiveChild}),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('cycleDetected'))),
      );
    });

    test('clips composed nested child batches through host clipping ranges',
        () {
      final child = _skeleton(
        name: 'child',
        bones: [_bone('root')],
        slots: [_slot('childSlot', 'root', 'face')],
        regions: [_region('face', 4.0, 4.0)],
      );
      final host = _skeleton(
        name: 'host',
        bones: [_bone('root')],
        slots: [
          _slot('clipSlot', 'root', 'host_clip'),
          _slot('nestedSlot', 'root', 'nested_face'),
        ],
        clippingAttachments: const [
          ClippingAttachment(
            name: 'host_clip',
            vertices: [0.0, -10.0, 100.0, -10.0, 100.0, 10.0, 0.0, 10.0],
            untilSlot: '',
          ),
        ],
        nestedRigAttachments: const [
          NestedRigAttachment(name: 'nested_face', skeleton: 'faceRig'),
        ],
      );
      final batches = buildNestedDrawBatches(host, {'faceRig': child});

      expect(batches, hasLength(1));
      expect(batches[0].clipId, 'host_clip');
      expect(batches[0].vertices.length, greaterThanOrEqualTo(4));
      expect(batches[0].indices.length, greaterThanOrEqualTo(6));
      expect(batches[0].vertices.every((v) => v.x >= -1e-9), isTrue);
      expect(batches[0].vertices.any((v) => (v.x - 0.0).abs() <= 1e-9), isTrue);
    });
  });
}
