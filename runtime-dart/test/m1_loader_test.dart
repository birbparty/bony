// Dart M1 conformance gate: SkeletonData loader gated against m1_rig.bony.
//
// Verifies that loadBonyJson parses the committed M1 conformance asset
// (conformance/assets/m1_rig.bony) into the correct SkeletonData model.
// World-matrix pose goldens require the M2 world-transform pass; those are
// covered by bony-65j (Dart M2).
//
// Tests run from runtime-dart/ so ../conformance/ resolves to repo root.

import 'dart:io';
import 'dart:typed_data' show ByteData, Endian;
import 'package:test/test.dart';
import 'package:bony/bony.dart';

int _f32Bits(double x) {
  final bd = ByteData(4);
  bd.setFloat32(0, x, Endian.little);
  return bd.getUint32(0, Endian.little);
}

void main() {
  late SkeletonData data;

  setUpAll(() {
    final text = File('../conformance/assets/m1_rig.bony').readAsStringSync();
    data = loadBonyJson(text);
  });

  group('M1 skeleton header', () {
    test('name is m1-rig', () => expect(data.header.name, 'm1-rig'));
    test('version is 1.0.0', () => expect(data.header.version, '1.0.0'));
  });

  group('M1 bones', () {
    test('has 5 bones', () => expect(data.bones, hasLength(5)));

    test('root bone has no parent', () {
      final bone = data.bones.firstWhere((b) => b.name == 'root');
      expect(bone.parent, '');
      expect(bone.x, closeTo(0.0, 1e-9));
      expect(bone.y, closeTo(0.0, 1e-9));
      expect(bone.rotation, closeTo(0.0, 1e-9));
      expect(bone.scaleX, closeTo(1.0, 1e-9));
      expect(bone.scaleY, closeTo(1.0, 1e-9));
      expect(bone.inheritRotation, isTrue);
      expect(bone.inheritScale, isTrue);
      expect(bone.inheritReflection, isTrue);
      expect(bone.transformMode, 'normal');
    });

    test('torso bone', () {
      final bone = data.bones.firstWhere((b) => b.name == 'torso');
      expect(bone.parent, 'root');
      expect(bone.x, closeTo(0.0, 1e-9));
      expect(bone.y, closeTo(-50.0, 1e-9));
      expect(bone.rotation, closeTo(0.0, 1e-9));
    });

    test('head bone', () {
      final bone = data.bones.firstWhere((b) => b.name == 'head');
      expect(bone.parent, 'torso');
      expect(bone.y, closeTo(-80.0, 1e-9));
      expect(bone.rotation, closeTo(15.0, 1e-9));
    });

    test('arm_r bone — noScale transform mode', () {
      final bone = data.bones.firstWhere((b) => b.name == 'arm_r');
      expect(bone.parent, 'torso');
      expect(bone.x, closeTo(-45.0, 1e-9));
      expect(bone.y, closeTo(-20.0, 1e-9));
      expect(bone.rotation, closeTo(-30.0, 1e-9));
      expect(bone.inheritScale, isFalse);
      expect(bone.transformMode, 'noScale');
    });

    test('arm_l bone — onlyTranslation transform mode', () {
      final bone = data.bones.firstWhere((b) => b.name == 'arm_l');
      expect(bone.parent, 'torso');
      expect(bone.x, closeTo(45.0, 1e-9));
      expect(bone.y, closeTo(-20.0, 1e-9));
      expect(bone.rotation, closeTo(30.0, 1e-9));
      expect(bone.inheritRotation, isFalse);
      expect(bone.inheritScale, isFalse);
      expect(bone.inheritReflection, isFalse);
      expect(bone.transformMode, 'onlyTranslation');
    });
  });

  group('M1 slots', () {
    test('has 4 slots', () => expect(data.slots, hasLength(4)));

    test('arm_l_slot', () {
      final slot = data.slots.firstWhere((s) => s.name == 'arm_l_slot');
      expect(slot.bone, 'arm_l');
      expect(slot.attachment, 'arm_l');
    });

    test('arm_r_slot', () {
      final slot = data.slots.firstWhere((s) => s.name == 'arm_r_slot');
      expect(slot.bone, 'arm_r');
      expect(slot.attachment, 'arm_r');
    });

    test('torso_slot', () {
      final slot = data.slots.firstWhere((s) => s.name == 'torso_slot');
      expect(slot.bone, 'torso');
      expect(slot.attachment, 'torso');
    });

    test('head_slot', () {
      final slot = data.slots.firstWhere((s) => s.name == 'head_slot');
      expect(slot.bone, 'head');
      expect(slot.attachment, 'head');
    });
  });

  group('M1 regions', () {
    test('has 4 regions', () => expect(data.regions, hasLength(4)));

    test('arm_l region dimensions', () {
      final r = data.regions.firstWhere((r) => r.name == 'arm_l');
      expect(r.width, closeTo(30.0, 1e-9));
      expect(r.height, closeTo(80.0, 1e-9));
    });

    test('torso region dimensions', () {
      final r = data.regions.firstWhere((r) => r.name == 'torso');
      expect(r.width, closeTo(80.0, 1e-9));
      expect(r.height, closeTo(120.0, 1e-9));
    });

    test('head region dimensions', () {
      final r = data.regions.firstWhere((r) => r.name == 'head');
      expect(r.width, closeTo(60.0, 1e-9));
      expect(r.height, closeTo(60.0, 1e-9));
    });
  });

  group('M1 paths and pathAttachments', () {
    test('no path constraints', () => expect(data.paths, isEmpty));
    test('no path attachments', () => expect(data.pathAttachments, isEmpty));
  });

  group('loadBonyJson error handling', () {
    test('rejects non-object JSON', () {
      expect(() => loadBonyJson('"not an object"'), throwsFormatException);
    });

    test('rejects missing skeleton', () {
      expect(() => loadBonyJson('{"bones":[]}'), throwsFormatException);
    });

    test('rejects missing skeleton.name', () {
      expect(
        () => loadBonyJson('{"skeleton":{},"bones":[]}'),
        throwsFormatException,
      );
    });

    test('rejects missing bones', () {
      expect(
        () => loadBonyJson('{"skeleton":{"name":"x"}}'),
        throwsFormatException,
      );
    });

    test('applies skeleton.version default', () {
      final d = loadBonyJson('{"skeleton":{"name":"x"},"bones":[]}');
      expect(d.header.version, '0.1.0');
    });

    test('applies bone defaults', () {
      final d = loadBonyJson(
        '{"skeleton":{"name":"x"},"bones":[{"name":"b"}]}',
      );
      final bone = d.bones.first;
      expect(bone.parent, '');
      expect(bone.x, closeTo(0.0, 1e-9));
      expect(bone.scaleX, closeTo(1.0, 1e-9));
      expect(bone.inheritRotation, isTrue);
      expect(bone.transformMode, 'normal');
    });

    test('f32-quantizes bone transform fields on load', () {
      final d = loadBonyJson(
        '{"skeleton":{"name":"x"},"bones":[{'
        '"name":"b",'
        '"x":0.1,'
        '"y":0.2,'
        '"rotation":0.3,'
        '"scaleX":1.1,'
        '"scaleY":1.2,'
        '"shearX":0.4,'
        '"shearY":0.5'
        '}]}',
      );
      final bone = d.bones.single;
      expect(bone.x, quantizeF32(0.1));
      expect(bone.y, quantizeF32(0.2));
      expect(bone.rotation, quantizeF32(0.3));
      expect(bone.scaleX, quantizeF32(1.1));
      expect(bone.scaleY, quantizeF32(1.2));
      expect(bone.shearX, quantizeF32(0.4));
      expect(bone.shearY, quantizeF32(0.5));
    });

    test('normalizes negative zero in bone transform fields on load', () {
      final d = loadBonyJson(
        '{"skeleton":{"name":"x"},"bones":[{'
        '"name":"b",'
        '"x":-0.0,'
        '"y":-0.0,'
        '"rotation":-0.0,'
        '"scaleX":-0.0,'
        '"scaleY":-0.0,'
        '"shearX":-0.0,'
        '"shearY":-0.0'
        '}]}',
      );
      final bone = d.bones.single;
      expect(_f32Bits(bone.x), 0);
      expect(_f32Bits(bone.y), 0);
      expect(_f32Bits(bone.rotation), 0);
      expect(_f32Bits(bone.scaleX), 0);
      expect(_f32Bits(bone.scaleY), 0);
      expect(_f32Bits(bone.shearX), 0);
      expect(_f32Bits(bone.shearY), 0);
    });

    test('rejects wrong type for name field', () {
      // _required<T> must throw FormatException, not TypeError, on type mismatch.
      expect(
        () => loadBonyJson('{"skeleton":{"name":42},"bones":[]}'),
        throwsFormatException,
      );
    });

    test('accepts order as double (e.g. 0.0)', () {
      // JSON numbers without a decimal point are int; with one are double.
      // toInt() must handle both.
      final d = loadBonyJson('{'
          '"skeleton":{"name":"x"},'
          '"bones":[{"name":"b"},{"name":"c","parent":"b"}],'
          '"pathAttachments":[{"name":"p","p0x":0,"p0y":0,"p1x":0,"p1y":0,"p2x":0,"p2y":0,"p3x":0,"p3y":0}],'
          '"paths":[{"name":"pc","bone":"b","target":"c","path":"p","order":0.0}]'
          '}');
      expect(d.paths.first.order, 0);
    });
  });

  group('loadBonyJson structural validation', () {
    test('rejects duplicate bone names', () {
      expect(
        () => loadBonyJson(
          '{"skeleton":{"name":"x"},"bones":[{"name":"b"},{"name":"b"}]}',
        ),
        throwsFormatException,
      );
    });

    test('rejects unknown parent bone', () {
      expect(
        () => loadBonyJson(
          '{"skeleton":{"name":"x"},"bones":[{"name":"b","parent":"missing"}]}',
        ),
        throwsFormatException,
      );
    });

    test('rejects child before parent', () {
      // "child" appears first but references "root" which appears second.
      expect(
        () => loadBonyJson(
          '{"skeleton":{"name":"x"},"bones":['
          '{"name":"child","parent":"root"},'
          '{"name":"root"}'
          ']}',
        ),
        throwsFormatException,
      );
    });

    test('rejects slot referencing unknown bone', () {
      expect(
        () => loadBonyJson(
          '{"skeleton":{"name":"x"},"bones":[{"name":"b"}],'
          '"slots":[{"name":"s","bone":"missing"}]}',
        ),
        throwsFormatException,
      );
    });

    test('rejects slot referencing unknown attachment', () {
      expect(
        () => loadBonyJson(
          '{"skeleton":{"name":"x"},"bones":[{"name":"b"}],'
          '"slots":[{"name":"s","bone":"b","attachment":"no_such_region"}]}',
        ),
        throwsFormatException,
      );
    });

    test('accepts slot with empty attachment (omitted)', () {
      final d = loadBonyJson(
        '{"skeleton":{"name":"x"},"bones":[{"name":"b"}],'
        '"slots":[{"name":"s","bone":"b"}]}',
      );
      expect(d.slots.first.attachment, '');
    });

    test('rejects negative region dimensions', () {
      expect(
        () => loadBonyJson(
          '{"skeleton":{"name":"x"},"bones":[{"name":"b"}],'
          '"regions":[{"name":"r","width":-1,"height":10}]}',
        ),
        throwsFormatException,
      );
    });
  });
}
