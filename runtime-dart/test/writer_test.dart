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
            .having((e) => e.message, 'message', 'invalid SkeletonData')
            .having((e) => e.cause, 'cause', isA<FormatException>())
            .having(
              (e) => e.cause.toString(),
              'cause text',
              contains('unknown parent bone: missing'),
            )),
      );
    });

    test('omits default-valued fields from public output', () {
      final data = SkeletonData(
        header: const SkeletonHeader(name: 'defaults', version: '0.1.0'),
        bones: const [
          BoneData(
            name: 'root',
            parent: '',
            x: -0.0,
            y: 0,
            rotation: 0,
            scaleX: 1.00000001,
            scaleY: 1,
            shearX: 0,
            shearY: 0,
            inheritRotation: true,
            inheritScale: true,
            inheritReflection: true,
            transformMode: 'normal',
          ),
        ],
        slots: const [
          SlotData(name: 'slot', bone: 'root', attachment: 'region'),
        ],
        regions: const [
          RegionAttachment(name: 'region', width: 12, height: 34),
        ],
        paths: const [],
        pathAttachments: const [],
      );

      final emitted = writeBonyJson(data);
      expect(emitted, contains('"name": "defaults"'));
      expect(emitted, contains('"width": 12'));
      expect(emitted, contains('"height": 34'));
      expect(emitted, isNot(contains('"version"')));
      expect(emitted, isNot(contains('"parent"')));
      expect(emitted, isNot(contains('"x"')));
      expect(emitted, isNot(contains('"scaleX"')));
      expect(emitted, isNot(contains('"inheritRotation"')));
      expect(emitted, isNot(contains('"transformMode"')));
      expect(emitted, isNot(contains('"texturePage"')));
      expect(emitted, isNot(contains('"u0"')));
      expect(emitted, isNot(contains('"alphaMode"')));
      expect(writeBonyJson(loadBonyJson(emitted)), emitted);
    });

    test('escapes strings and spells numbers canonically in public output', () {
      final data = SkeletonData(
        header: const SkeletonHeader(
          name: 'quote" slash/ backslash\\ line\n tab\t café',
          version: '0.1.0',
        ),
        bones: const [
          BoneData(
            name: 'root',
            parent: '',
            x: 0.0000001,
            y: 1e20,
            rotation: -0.0,
            scaleX: 1,
            scaleY: 1.5,
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

      final emitted = writeBonyJson(data);
      expect(
        emitted,
        contains(
          r'"name": "quote\" slash/ backslash\\ line\n tab\t café"',
        ),
      );
      expect(emitted, contains('"x": 1.0000000116860974e-7'));
      expect(emitted, contains('"y": 100000002004087730000.0'));
      expect(emitted, isNot(contains('"rotation"')));
      expect(emitted, contains('"scaleY": 1.5'));
      expect(writeBonyJson(loadBonyJson(emitted)), emitted);
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
        final emitted = writeBonyJson(loadBonyJson(input));

        expect(emitted, expected, reason: name);
        expect(() => loadBonyJson(emitted), returnsNormally, reason: name);
        expect(writeBonyJson(loadBonyJson(emitted)), emitted, reason: name);
      }
    });

    test('matches Nim canonical JSON for committed .bnb fixtures', () {
      final goldenFiles = Directory('../conformance/goldens/canonical-json/bnb')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.bony'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      expect(goldenFiles, isNotEmpty);
      for (final golden in goldenFiles) {
        final name = golden.uri.pathSegments.last;
        final stem = name.substring(0, name.length - '.bony'.length);
        final input =
            File('../conformance/assets/bnb/$stem.bnb').readAsBytesSync();
        final expected = golden.readAsStringSync();
        final emitted = writeBonyJson(loadBonyBnb(input));

        expect(emitted, expected, reason: name);
        expect(() => loadBonyJson(emitted), returnsNormally, reason: name);
        expect(writeBonyJson(loadBonyJson(emitted)), emitted, reason: name);
      }
    });

    test('quantizes directly constructed f32 constraint values', () {
      final data = SkeletonData(
        header: const SkeletonHeader(name: 'f32', version: '0.1.0'),
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
          BoneData(
            name: 'tip',
            parent: 'root',
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
        paths: const [
          PathConstraintData(
            name: 'path',
            bone: 'tip',
            target: 'root',
            path: 'curve',
            order: 0,
            position: 0.1,
            translateMix: 0.2,
            rotateMix: 0.3,
          ),
        ],
        pathAttachments: const [
          PathAttachment(
            name: 'curve',
            p0x: 0,
            p0y: 0,
            p1x: 1,
            p1y: 0,
            p2x: 1,
            p2y: 1,
            p3x: 2,
            p3y: 1,
          ),
        ],
        ikConstraints: const [
          IkConstraintData(
            name: 'ik',
            bones: ['tip'],
            target: 'root',
            order: 0,
            mix: 0.1,
          ),
        ],
        transformConstraints: const [
          TransformConstraintData(
            name: 'tc',
            bone: 'tip',
            target: 'root',
            order: 0,
            translateMix: 0.1,
            rotateMix: 0.2,
            scaleMix: 0.3,
            shearMix: 0.4,
          ),
        ],
        physicsConstraints: const [
          PhysicsConstraintData(
            name: 'phys',
            bone: 'tip',
            channels: {PhysicsChannel.x},
            inertia: 0.1,
            strength: 0.2,
            damping: 0.3,
            mass: 0.4,
            gravity: 0.5,
            wind: 0.6,
            physicsMix: 0.7,
          ),
        ],
      );

      final emitted = writeBonyJson(data);
      expect(emitted, contains('"position": 0.10000000149011612'));
      expect(emitted, contains('"translateMix": 0.20000000298023224'));
      expect(emitted, contains('"rotateMix": 0.30000001192092896'));
      expect(emitted, contains('"mix": 0.10000000149011612'));
      expect(emitted, contains('"scaleMix": 0.30000001192092896'));
      expect(emitted, contains('"shearMix": 0.4000000059604645'));
      expect(emitted, contains('"inertia": 0.10000000149011612'));
      expect(emitted, contains('"strength": 0.20000000298023224'));
      expect(emitted, contains('"damping": 0.30000001192092896'));
      expect(emitted, contains('"mass": 0.4000000059604645'));
      expect(emitted, contains('"gravity": 0.5'));
      expect(emitted, contains('"wind": 0.6000000238418579'));
      expect(emitted, contains('"physicsMix": 0.699999988079071'));
      expect(writeBonyJson(loadBonyJson(emitted)), emitted);
    });

    test('rejects directly constructed empty state-machine layers', () {
      final data = SkeletonData(
        header: const SkeletonHeader(name: 'bad-sm', version: '0.1.0'),
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
        stateMachines: const [
          StateMachineData(
            name: 'sm',
            layers: [
              StateMachineLayer(name: 'empty', states: [], initialState: ''),
            ],
          ),
        ],
      );

      expect(
        () => writeBonyJson(data),
        throwsA(isA<BonyWriteException>()
            .having((e) => e.cause, 'cause', isA<FormatException>())),
      );
    });
  });
}
