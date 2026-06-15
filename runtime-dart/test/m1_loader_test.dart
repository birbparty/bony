// Dart M1 conformance gate: SkeletonData loader gated against m1_rig.bony.
//
// Verifies that loadBonyJson parses the committed M1 conformance asset into
// the correct SkeletonData model. Values are checked against the committed
// asset (conformance/assets/m1_rig.bony) and the committed M1 golden
// (conformance/goldens/m1_rig_t0.json) which records the reference poses.
//
// Tests run from runtime-dart/ so ../conformance/ resolves to repo root.

import 'dart:io';
import 'package:test/test.dart';
import 'package:bony/bony.dart';

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
  });
}
