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
  });
}
