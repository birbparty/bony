import 'dart:io';

import 'package:bony/bony.dart';
import 'package:test/test.dart';

void main() {
  group('writeBonyJson', () {
    test('emits a minimal skeleton canonically', () {
      final data = SkeletonData(
        header: const SkeletonHeader(name: 'mini', version: '0.1.0'),
        bones: const [
          BoneData(
            name: 'root',
            parent: '',
            x: 0,
            y: 0,
            rotation: 0,
            scaleX: 1,
            scaleY: 1,
            shearX: 0,
            shearY: 0,
            inheritRotation: true,
            inheritScale: true,
            inheritReflection: true,
            transformMode: 'normal',
          ),
        ],
        slots: const [],
        regions: const [],
        paths: const [],
        pathAttachments: const [],
      );

      expect(
        writeBonyJson(data),
        '{\n'
        '  "skeleton": {\n'
        '    "name": "mini"\n'
        '  },\n'
        '  "bones": [\n'
        '    {\n'
        '      "name": "root"\n'
        '    }\n'
        '  ],\n'
        '  "slots": [],\n'
        '  "regions": []\n'
        '}\n',
      );
    });

    test('wraps validation failures without emitting output', () {
      final invalid = SkeletonData(
        header: const SkeletonHeader(name: 'bad', version: '0.1.0'),
        bones: const [
          BoneData(
            name: 'child',
            parent: 'missing',
            x: 0,
            y: 0,
            rotation: 0,
            scaleX: 1,
            scaleY: 1,
            shearX: 0,
            shearY: 0,
            inheritRotation: true,
            inheritScale: true,
            inheritReflection: true,
            transformMode: 'normal',
          ),
        ],
        slots: const [],
        regions: const [],
        paths: const [],
        pathAttachments: const [],
      );

      expect(
        () => writeBonyJson(invalid),
        throwsA(isA<BonyWriteException>()
            .having((e) => e.cause, 'cause', isA<FormatException>())),
      );
    });

    test('matches Nim canonical JSON for committed JSON fixtures', () {
      final goldenFiles =
          Directory('../conformance/goldens/canonical-json/json')
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.bony'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      expect(goldenFiles, isNotEmpty);
      for (final golden in goldenFiles) {
        final name = golden.uri.pathSegments.last;
        final input = File('../conformance/assets/$name').readAsStringSync();
        final expected = golden.readAsStringSync();

        expect(writeBonyJson(loadBonyJson(input)), expected, reason: name);
      }
    });
  });
}
