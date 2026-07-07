// Unit tests for non-scalar MixedPose channels:
// vectors, attachments, inherits, colors, colors2, sequences.
// Ports the Nim test coverage in anim/mixer.nim and anim/timelines.nim.

import 'dart:io';
import 'package:test/test.dart';
import 'package:bony/bony.dart';

const double _tol = 1e-4;

void _expectClose(double actual, double expected, String label) {
  expect(
    (actual - expected).abs(),
    lessThanOrEqualTo(_tol),
    reason:
        '$label: actual=$actual expected=$expected diff=${(actual - expected).abs()}',
  );
}

SkeletonData _skelData({
  List<BoneData> bones = const [],
  List<SlotData> slots = const [],
  List<RegionAttachment> regions = const [],
}) {
  return SkeletonData(
    header: const SkeletonHeader(name: 'test', version: '0.1.0'),
    bones: [
      const BoneData(
        name: 'root',
        parent: '',
        x: 0.0,
        y: 0.0,
        rotation: 0.0,
        scaleX: 1.0,
        scaleY: 1.0,
        shearX: 0.0,
        shearY: 0.0,
        inheritRotation: true,
        inheritScale: true,
        inheritReflection: true,
        transformMode: 'normal',
      ),
      ...bones,
    ],
    slots: [
      const SlotData(name: 'slot1', bone: 'root', attachment: ''),
      ...slots,
    ],
    regions: [
      const RegionAttachment(name: 'r1', width: 10, height: 10),
      const RegionAttachment(name: 'r2', width: 20, height: 20),
      ...regions,
    ],
    paths: [],
    pathAttachments: [],
  );
}

void main() {
  // ---------------------------------------------------------------- Sampling

  group('sampleBoneVectorTimeline', () {
    test('single vector keyframe returns that pair at any time', () {
      final tl = BoneTimeline(
        bone: 'root',
        kind: BoneTimelineKind.translate,
        vectorKeys: [const Vector2Keyframe(time: 0.0, x: 3.0, y: 4.0)],
      );
      final (x, y) = sampleBoneVectorTimeline(tl, 0.0);
      _expectClose(x, 3.0, 'x');
      _expectClose(y, 4.0, 'y');
      final (x2, y2) = sampleBoneVectorTimeline(tl, 9.0);
      _expectClose(x2, 3.0, 'x clamped');
      _expectClose(y2, 4.0, 'y clamped');
    });

    test('linear interpolation between two vector keyframes', () {
      final tl = BoneTimeline(
        bone: 'root',
        kind: BoneTimelineKind.translate,
        vectorKeys: [
          const Vector2Keyframe(time: 0.0, x: 0.0, y: 0.0),
          const Vector2Keyframe(time: 1.0, x: 10.0, y: 20.0),
        ],
      );
      final (x, y) = sampleBoneVectorTimeline(tl, 0.5);
      _expectClose(x, 5.0, 'x mid');
      _expectClose(y, 10.0, 'y mid');
    });

    test('separate curveX and curveY — stepped X, linear Y', () {
      final tl = BoneTimeline(
        bone: 'root',
        kind: BoneTimelineKind.translate,
        vectorKeys: [
          Vector2Keyframe(
            time: 0.0,
            x: 0.0,
            y: 0.0,
            curveX: TimelineCurve.stepped, // X holds at 0 until next key
            curveY: TimelineCurve.linear,
          ),
          const Vector2Keyframe(time: 1.0, x: 10.0, y: 10.0),
        ],
      );
      final (x, y) = sampleBoneVectorTimeline(tl, 0.5);
      _expectClose(x, 0.0, 'stepped x at 0.5'); // stepped: holds first
      _expectClose(y, 5.0, 'linear y at 0.5');
    });
  });

  group('sampleBoneInheritTimeline', () {
    test('stepped — returns key at or before sample time', () {
      final tl = BoneTimeline(
        bone: 'root',
        kind: BoneTimelineKind.inherit,
        inheritKeys: [
          const InheritKeyframe(
            time: 0.0,
            inheritRotation: true,
            inheritScale: true,
            inheritReflection: true,
            transformMode: 'normal',
          ),
          const InheritKeyframe(
            time: 1.0,
            inheritRotation: false,
            inheritScale: false,
            inheritReflection: false,
            transformMode: 'noScale',
          ),
        ],
      );
      final k0 = sampleBoneInheritTimeline(tl, 0.4);
      expect(k0.transformMode, 'normal');
      expect(k0.inheritRotation, isTrue);

      final k1 = sampleBoneInheritTimeline(tl, 1.0);
      expect(k1.transformMode, 'noScale');
      expect(k1.inheritRotation, isFalse);
    });
  });

  group('sampleSlotAttachment', () {
    test('stepped — returns attachment at or before sample time', () {
      final tl = SlotTimeline(
        slot: 'slot1',
        kind: SlotTimelineKind.attachment,
        attachmentKeys: [
          const AttachmentKeyframe(time: 0.0, attachment: 'r1'),
          const AttachmentKeyframe(time: 1.0, attachment: 'r2'),
        ],
      );
      expect(sampleSlotAttachment(tl, 0.5), 'r1');
      expect(sampleSlotAttachment(tl, 1.0), 'r2');
    });
  });

  group('sampleSlotColor', () {
    test('linear interpolation between two rgba keyframes', () {
      final tl = SlotTimeline(
        slot: 'slot1',
        kind: SlotTimelineKind.rgba,
        colorKeys: [
          const ColorKeyframe(
              time: 0.0, color: ColorRgba(r: 1.0, g: 0.0, b: 0.0, a: 1.0)),
          const ColorKeyframe(
              time: 1.0, color: ColorRgba(r: 0.0, g: 1.0, b: 0.0, a: 0.5)),
        ],
      );
      final c = sampleSlotColor(tl, 0.5);
      _expectClose(c.r, 0.5, 'r mid');
      _expectClose(c.g, 0.5, 'g mid');
      _expectClose(c.b, 0.0, 'b mid');
      _expectClose(c.a, 0.75, 'a mid');
    });

    test('single keyframe returns that color at any time', () {
      final tl = SlotTimeline(
        slot: 'slot1',
        kind: SlotTimelineKind.alpha,
        colorKeys: [
          const ColorKeyframe(
              time: 0.0, color: ColorRgba(r: 1.0, g: 1.0, b: 1.0, a: 0.5)),
        ],
      );
      final c = sampleSlotColor(tl, 5.0);
      _expectClose(c.a, 0.5, 'alpha clamped');
    });
  });

  group('sampleSlotColor2', () {
    test('interpolates light and dark channels independently', () {
      final tl = SlotTimeline(
        slot: 'slot1',
        kind: SlotTimelineKind.rgba2,
        color2Keys: [
          const Color2Keyframe(
            time: 0.0,
            color: ColorRgba2(
              light: ColorRgba(r: 0.0, g: 0.0, b: 0.0, a: 0.0),
              darkR: 0.0,
              darkG: 0.0,
              darkB: 0.0,
            ),
          ),
          const Color2Keyframe(
            time: 1.0,
            color: ColorRgba2(
              light: ColorRgba(r: 1.0, g: 1.0, b: 1.0, a: 1.0),
              darkR: 1.0,
              darkG: 1.0,
              darkB: 1.0,
            ),
          ),
        ],
      );
      final c = sampleSlotColor2(tl, 0.5);
      _expectClose(c.light.r, 0.5, 'light.r');
      _expectClose(c.light.a, 0.5, 'light.a');
      _expectClose(c.darkR, 0.5, 'darkR');
    });
  });

  group('sampleSlotSequence', () {
    test('stepped — returns keyframe at or before sample time', () {
      final tl = SlotTimeline(
        slot: 'slot1',
        kind: SlotTimelineKind.sequence,
        sequenceKeys: [
          const SequenceKeyframe(
              time: 0.0, index: 0, delay: 0.1, mode: SequenceMode.loop),
          const SequenceKeyframe(
              time: 1.0, index: 4, delay: 0.1, mode: SequenceMode.hold),
        ],
      );
      expect(sampleSlotSequence(tl, 0.5).index, 0);
      expect(sampleSlotSequence(tl, 1.0).index, 4);
      expect(sampleSlotSequence(tl, 1.0).mode, SequenceMode.hold);
    });
  });

  // --------------------------------------------------------- Mixer / MixedPose

  group('AnimationState non-scalar channels', () {
    late SkeletonData data;
    late AnimationClip clip;

    setUp(() {
      data = _skelData();
      // Clip: vector translate, attachment swap, inherit, rgba color.
      clip = AnimationClip(
        name: 'test',
        duration: 1.0,
        boneTimelines: [
          BoneTimeline(
            bone: 'root',
            kind: BoneTimelineKind.translate,
            vectorKeys: [
              const Vector2Keyframe(time: 0.0, x: 0.0, y: 0.0),
              const Vector2Keyframe(time: 1.0, x: 10.0, y: 20.0),
            ],
          ),
          BoneTimeline(
            bone: 'root',
            kind: BoneTimelineKind.inherit,
            inheritKeys: [
              const InheritKeyframe(
                time: 0.0,
                inheritRotation: true,
                inheritScale: true,
                inheritReflection: true,
                transformMode: 'normal',
              ),
              const InheritKeyframe(
                time: 1.0,
                inheritRotation: false,
                inheritScale: false,
                inheritReflection: false,
                transformMode: 'noScale',
              ),
            ],
          ),
        ],
        slotTimelines: [
          SlotTimeline(
            slot: 'slot1',
            kind: SlotTimelineKind.attachment,
            attachmentKeys: [
              const AttachmentKeyframe(time: 0.0, attachment: 'r1'),
              const AttachmentKeyframe(time: 0.6, attachment: 'r2'),
            ],
          ),
          SlotTimeline(
            slot: 'slot1',
            kind: SlotTimelineKind.rgba,
            colorKeys: [
              const ColorKeyframe(
                  time: 0.0, color: ColorRgba(r: 1.0, g: 1.0, b: 1.0, a: 1.0)),
              const ColorKeyframe(
                  time: 1.0, color: ColorRgba(r: 0.0, g: 0.0, b: 0.0, a: 0.5)),
            ],
          ),
        ],
      );
    });

    test('vectors populated at t=0.5', () {
      final state = AnimationState(data)
        ..setAnimation(0, clip)
        ..update(0.5);
      final pose = state.sample();
      expect(pose.vectors, hasLength(1));
      _expectClose(pose.vectors.first.x, 5.0, 'translate.x at 0.5');
      _expectClose(pose.vectors.first.y, 10.0, 'translate.y at 0.5');
    });

    test('inherits populated and stepped', () {
      final state = AnimationState(data)
        ..setAnimation(0, clip)
        ..update(0.5);
      final pose = state.sample();
      expect(pose.inherits, hasLength(1));
      // At t=0.5, stepped: key at t=0 (normal) is active.
      expect(pose.inherits.first.value.transformMode, 'normal');

      // At t=1.0, key at t=1.0 (noScale) takes over.
      final state2 = AnimationState(data)
        ..setAnimation(0, clip)
        ..update(1.0);
      final pose2 = state2.sample();
      expect(pose2.inherits.first.value.transformMode, 'noScale');
    });

    test('attachments populated and stepped', () {
      final state = AnimationState(data)
        ..setAnimation(0, clip)
        ..update(0.5);
      final pose = state.sample();
      expect(pose.attachments, hasLength(1));
      expect(pose.attachments.first.attachment, 'r1'); // before t=0.6

      final state2 = AnimationState(data)
        ..setAnimation(0, clip)
        ..update(0.8);
      final pose2 = state2.sample();
      expect(pose2.attachments.first.attachment, 'r2'); // after t=0.6
    });

    test('colors populated and interpolated', () {
      final state = AnimationState(data)
        ..setAnimation(0, clip)
        ..update(0.5);
      final pose = state.sample();
      expect(pose.colors, hasLength(1));
      _expectClose(pose.colors.first.color.a, 0.75, 'rgba.a at 0.5');
    });
  });

  // --------------------------------------------------------- applyPose

  group('applyPose non-scalar channels', () {
    test('applies vector translate channel to bones', () {
      final data = _skelData();
      final pose = MixedPose(
        scalars: const [],
        vectors: [
          (bone: 'root', kind: BoneTimelineKind.translate, x: 5.0, y: 8.0)
        ],
        attachments: const [],
        inherits: const [],
        colors: const [],
        colors2: const [],
        sequences: const [],
        deforms: const [],
      );
      final result = applyPose(data, pose);
      _expectClose(result.bones.first.x, 5.0, 'bone.x');
      _expectClose(result.bones.first.y, 8.0, 'bone.y');
    });

    test('applies inherit channel to bones', () {
      final data = _skelData();
      final pose = MixedPose(
        scalars: const [],
        vectors: const [],
        attachments: const [],
        inherits: [
          (
            bone: 'root',
            value: const InheritKeyframe(
              time: 0.0,
              inheritRotation: false,
              inheritScale: false,
              inheritReflection: false,
              transformMode: 'noScale',
            ),
          )
        ],
        colors: const [],
        colors2: const [],
        sequences: const [],
        deforms: const [],
      );
      final result = applyPose(data, pose);
      expect(result.bones.first.inheritRotation, isFalse);
      expect(result.bones.first.transformMode, 'noScale');
    });

    test('applies attachment channel to slots', () {
      final data = _skelData();
      final pose = MixedPose(
        scalars: const [],
        vectors: const [],
        attachments: [(slot: 'slot1', attachment: 'r2')],
        inherits: const [],
        colors: const [],
        colors2: const [],
        sequences: const [],
        deforms: const [],
      );
      final result = applyPose(data, pose);
      expect(result.slots.first.attachment, 'r2');
    });

    test('vector translate overrides paired scalar translateX/Y', () {
      final data = _skelData();
      // Both a vector AND a scalar for the same bone — vector wins.
      final pose = MixedPose(
        scalars: [
          (bone: 'root', kind: BoneTimelineKind.translateX, value: 99.0)
        ],
        vectors: [
          (bone: 'root', kind: BoneTimelineKind.translate, x: 7.0, y: 3.0)
        ],
        attachments: const [],
        inherits: const [],
        colors: const [],
        colors2: const [],
        sequences: const [],
        deforms: const [],
      );
      final result = applyPose(data, pose);
      // Vector takes precedence for x/y.
      _expectClose(result.bones.first.x, 7.0, 'bone.x from vector');
      _expectClose(result.bones.first.y, 3.0, 'bone.y from vector');
    });
  });

  // --------------------------------------------------------- JSON loader

  group('Loader non-scalar timelines', () {
    const String _skelBase = '{"skeleton":{"name":"ns"},'
        '"bones":[{"name":"root"}],'
        '"slots":[{"name":"s1","bone":"root"}],'
        '"regions":[{"name":"r1","width":10,"height":10},'
        '{"name":"r2","width":20,"height":20}],';

    test('translate (vector) bone timeline loads and samples correctly', () {
      final json = _skelBase +
          '"animations":[{"name":"a","boneTimelines":[{'
              '"bone":"root","property":"translate",'
              '"keyframes":[{"t":0.0,"x":0.0,"y":0.0},{"t":1.0,"x":10.0,"y":5.0}]}]}]}';
      final data = loadBonyJson(json);
      final clip = data.animations[0];
      expect(clip.boneTimelines[0].kind, BoneTimelineKind.translate);
      expect(clip.boneTimelines[0].vectorKeys, hasLength(2));
      final (x, y) = sampleBoneVectorTimeline(clip.boneTimelines[0], 0.5);
      _expectClose(x, 5.0, 'x@0.5');
      _expectClose(y, 2.5, 'y@0.5');
    });

    test('inherit bone timeline loads and samples correctly', () {
      final json = _skelBase +
          '"animations":[{"name":"a","boneTimelines":[{'
              '"bone":"root","property":"inherit",'
              '"keyframes":[{"t":0.0,"inheritRotation":true,"inheritScale":true,'
              '"inheritReflection":true,"transformMode":"normal"},'
              '{"t":1.0,"inheritRotation":false,"inheritScale":false,'
              '"inheritReflection":false,"transformMode":"noScale"}]}]}]}';
      final data = loadBonyJson(json);
      final clip = data.animations[0];
      expect(clip.boneTimelines[0].kind, BoneTimelineKind.inherit);
      final k0 = sampleBoneInheritTimeline(clip.boneTimelines[0], 0.5);
      expect(k0.transformMode, 'normal');
      final k1 = sampleBoneInheritTimeline(clip.boneTimelines[0], 1.0);
      expect(k1.transformMode, 'noScale');
    });

    test('attachment slot timeline loads and samples correctly', () {
      final json = _skelBase +
          '"animations":[{"name":"a","slotTimelines":[{'
              '"slot":"s1","property":"attachment",'
              '"keyframes":[{"t":0.0,"attachment":"r1"},{"t":1.0,"attachment":"r2"}]}]}]}';
      final data = loadBonyJson(json);
      final clip = data.animations[0];
      expect(clip.slotTimelines[0].kind, SlotTimelineKind.attachment);
      expect(sampleSlotAttachment(clip.slotTimelines[0], 0.5), 'r1');
      expect(sampleSlotAttachment(clip.slotTimelines[0], 1.0), 'r2');
    });

    test('rgba slot timeline loads and samples correctly', () {
      final json = _skelBase +
          '"animations":[{"name":"a","slotTimelines":[{'
              '"slot":"s1","property":"rgba",'
              '"keyframes":[{"t":0.0,"r":1.0,"g":0.0,"b":0.0,"a":1.0},'
              '{"t":1.0,"r":0.0,"g":1.0,"b":0.0,"a":0.5}]}]}]}';
      final data = loadBonyJson(json);
      final clip = data.animations[0];
      final c = sampleSlotColor(clip.slotTimelines[0], 0.5);
      _expectClose(c.r, 0.5, 'r@0.5');
      _expectClose(c.g, 0.5, 'g@0.5');
      _expectClose(c.a, 0.75, 'a@0.5');
    });

    test('rgba2 slot timeline loads and samples correctly', () {
      final json = _skelBase +
          '"animations":[{"name":"a","slotTimelines":[{'
              '"slot":"s1","property":"rgba2",'
              '"keyframes":[{"t":0.0,"r":0.0,"g":0.0,"b":0.0,"a":0.0,"dr":0.0,"dg":0.0,"db":0.0},'
              '{"t":1.0,"r":1.0,"g":1.0,"b":1.0,"a":1.0,"dr":1.0,"dg":1.0,"db":1.0}]}]}]}';
      final data = loadBonyJson(json);
      final clip = data.animations[0];
      final c = sampleSlotColor2(clip.slotTimelines[0], 0.5);
      _expectClose(c.light.r, 0.5, 'light.r@0.5');
      _expectClose(c.darkG, 0.5, 'darkG@0.5');
    });

    test('sequence slot timeline loads and samples correctly', () {
      final json = _skelBase +
          '"animations":[{"name":"a","slotTimelines":[{'
              '"slot":"s1","property":"sequence",'
              '"keyframes":[{"t":0.0,"index":2,"delay":0.1,"mode":"loop"},'
              '{"t":1.0,"index":5,"delay":0.05,"mode":"hold"}]}]}]}';
      final data = loadBonyJson(json);
      final clip = data.animations[0];
      final k0 = sampleSlotSequence(clip.slotTimelines[0], 0.5);
      expect(k0.index, 2);
      expect(k0.mode, SequenceMode.loop);
      final k1 = sampleSlotSequence(clip.slotTimelines[0], 1.0);
      expect(k1.index, 5);
      expect(k1.mode, SequenceMode.hold);
    });

    test('loader rejects unknown slot in slot timeline', () {
      final json = _skelBase +
          '"animations":[{"name":"a","slotTimelines":[{'
              '"slot":"nonexistent","property":"attachment",'
              '"keyframes":[{"t":0.0,"attachment":""}]}]}]}';
      expect(() => loadBonyJson(json), throwsA(isA<FormatException>()));
    });

    test('loader rejects unknown slot timeline property', () {
      final json = _skelBase +
          '"animations":[{"name":"a","slotTimelines":[{'
              '"slot":"s1","property":"unknown",'
              '"keyframes":[{"t":0.0}]}]}]}';
      expect(() => loadBonyJson(json), throwsA(isA<FormatException>()));
    });
  });

  // --------------------------------------------------------- MixedPose order

  group('MixedPose channel ordering', () {
    test('vectors sorted by bone name then kind index', () {
      final data = _skelData(
        bones: [
          const BoneData(
            name: 'arm',
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
      );
      final clip = AnimationClip(
        name: 'test',
        duration: 1.0,
        boneTimelines: [
          BoneTimeline(
            bone: 'root',
            kind: BoneTimelineKind.scale,
            vectorKeys: [const Vector2Keyframe(time: 0.0, x: 2.0, y: 3.0)],
          ),
          BoneTimeline(
            bone: 'arm',
            kind: BoneTimelineKind.translate,
            vectorKeys: [const Vector2Keyframe(time: 0.0, x: 5.0, y: 0.0)],
          ),
        ],
      );
      final state = AnimationState(data)..setAnimation(0, clip);
      final pose = state.sample();
      expect(pose.vectors, hasLength(2));
      // 'arm' sorts before 'root'.
      expect(pose.vectors[0].bone, 'arm');
      expect(pose.vectors[1].bone, 'root');
    });
  });

  // --------------------------------------------------------- Conformance asset

  group('m9_non_scalar_rig.bony conformance round-trip', () {
    late SkeletonData data;

    setUpAll(() {
      final text = File('../conformance/assets/m9_non_scalar_rig.bony')
          .readAsStringSync();
      data = loadBonyJson(text);
    });

    test('skeleton name', () => expect(data.header.name, 'm9-non-scalar-rig'));

    test('has 3 bones', () => expect(data.bones, hasLength(3)));

    test('has 3 slots', () => expect(data.slots, hasLength(3)));

    test('has 6 regions', () => expect(data.regions, hasLength(6)));

    test('has 11 animations', () => expect(data.animations, hasLength(11)));

    test('slide — translate vector timeline', () {
      final clip = data.animations.firstWhere((a) => a.name == 'slide');
      expect(clip.boneTimelines, hasLength(1));
      expect(clip.boneTimelines[0].kind, BoneTimelineKind.translate);
      expect(clip.boneTimelines[0].vectorKeys, hasLength(2));
      final (x, y) = sampleBoneVectorTimeline(clip.boneTimelines[0], 0.5);
      _expectClose(x, 25.0, 'x@0.5');
      _expectClose(y, 0.0, 'y@0.5');
    });

    test('grow — scale vector timeline', () {
      final clip = data.animations.firstWhere((a) => a.name == 'grow');
      expect(clip.boneTimelines[0].kind, BoneTimelineKind.scale);
      final (x, y) = sampleBoneVectorTimeline(clip.boneTimelines[0], 0.5);
      _expectClose(x, 1.5, 'scaleX@0.5');
      _expectClose(y, 1.5, 'scaleY@0.5');
    });

    test('lean — shear vector timeline', () {
      final clip = data.animations.firstWhere((a) => a.name == 'lean');
      expect(clip.boneTimelines[0].kind, BoneTimelineKind.shear);
      final (x, _) = sampleBoneVectorTimeline(clip.boneTimelines[0], 0.5);
      _expectClose(x, 10.0, 'shearX@0.5');
    });

    test('inherit_switch — inherit timeline stepped', () {
      final clip =
          data.animations.firstWhere((a) => a.name == 'inherit_switch');
      expect(clip.boneTimelines[0].kind, BoneTimelineKind.inherit);
      final k0 = sampleBoneInheritTimeline(clip.boneTimelines[0], 0.5);
      expect(k0.transformMode, 'normal');
      final k1 = sampleBoneInheritTimeline(clip.boneTimelines[0], 1.0);
      expect(k1.transformMode, 'noScale');
    });

    test('blink — attachment slot timeline', () {
      final clip = data.animations.firstWhere((a) => a.name == 'blink');
      expect(clip.slotTimelines, hasLength(1));
      expect(clip.slotTimelines[0].kind, SlotTimelineKind.attachment);
      expect(sampleSlotAttachment(clip.slotTimelines[0], 0.0), 'head_a');
      expect(sampleSlotAttachment(clip.slotTimelines[0], 0.15), 'head_b');
      expect(sampleSlotAttachment(clip.slotTimelines[0], 0.25), 'head_a');
    });

    test('fade — rgba slot timeline', () {
      final clip = data.animations.firstWhere((a) => a.name == 'fade');
      expect(clip.slotTimelines[0].kind, SlotTimelineKind.rgba);
      final c = sampleSlotColor(clip.slotTimelines[0], 0.5);
      _expectClose(c.a, 0.5, 'alpha@0.5');
    });

    test('tint — rgb slot timeline', () {
      final clip = data.animations.firstWhere((a) => a.name == 'tint');
      expect(clip.slotTimelines[0].kind, SlotTimelineKind.rgb);
    });

    test('alpha_pulse — alpha slot timeline', () {
      final clip = data.animations.firstWhere((a) => a.name == 'alpha_pulse');
      expect(clip.slotTimelines[0].kind, SlotTimelineKind.alpha);
      final c = sampleSlotColor(clip.slotTimelines[0], 0.5);
      _expectClose(c.a, 0.2, 'alpha@0.5');
    });

    test('two_color — rgba2 slot timeline', () {
      final clip = data.animations.firstWhere((a) => a.name == 'two_color');
      expect(clip.slotTimelines[0].kind, SlotTimelineKind.rgba2);
      final c = sampleSlotColor2(clip.slotTimelines[0], 0.5);
      _expectClose(c.light.r, 0.9, 'light.r@0.5');
      _expectClose(c.darkR, 0.05, 'darkR@0.5');
    });

    test('fx_sequence — sequence slot timeline', () {
      final clip = data.animations.firstWhere((a) => a.name == 'fx_sequence');
      expect(clip.slotTimelines[0].kind, SlotTimelineKind.sequence);
      final k0 = sampleSlotSequence(clip.slotTimelines[0], 0.0);
      expect(k0.index, 0);
      expect(k0.mode, SequenceMode.loop);
      final k1 = sampleSlotSequence(clip.slotTimelines[0], 0.3);
      expect(k1.index, 1);
    });

    test('combo — mixed bone and slot timelines', () {
      final clip = data.animations.firstWhere((a) => a.name == 'combo');
      expect(clip.boneTimelines, hasLength(3));
      expect(clip.slotTimelines, hasLength(2));
      // translate: torso
      final translateTl = clip.boneTimelines.firstWhere(
        (t) => t.kind == BoneTimelineKind.translate,
      );
      final (x, y) = sampleBoneVectorTimeline(translateTl, 0.5);
      _expectClose(x, 25.0, 'combo translate.x@0.5');
      _expectClose(y, 10.0, 'combo translate.y@0.5');
      // attachment: head_slot
      final attachTl = clip.slotTimelines.firstWhere(
        (t) => t.kind == SlotTimelineKind.attachment,
      );
      expect(sampleSlotAttachment(attachTl, 0.5), 'head_b');
    });

    test('applyPose from combo animation at t=0.5', () {
      final clip = data.animations.firstWhere((a) => a.name == 'combo');
      final state = AnimationState(data)
        ..setAnimation(0, clip)
        ..update(0.5);
      final pose = state.sample();
      final applied = applyPose(data, pose);

      // torso translate from vector channel — animation values replace base transform
      final torso = applied.bones.firstWhere((b) => b.name == 'torso');
      _expectClose(torso.x, 25.0, 'torso.x');
      _expectClose(torso.y, 10.0, 'torso.y');

      // head_slot attachment from attachment channel
      final headSlot = applied.slots.firstWhere((s) => s.name == 'head_slot');
      expect(headSlot.attachment, 'head_b');
    });
  });

  // --------------------------------------------------------- Review fix regressions

  group('Review fix regressions', () {
    const String _skelBase = '{"skeleton":{"name":"ns"},'
        '"bones":[{"name":"root"}],'
        '"slots":[{"name":"s1","bone":"root"}],'
        '"regions":[{"name":"r1","width":10,"height":10}],';

    test('[loader] curveX overrides top-level curve on vector keyframe', () {
      // If j has both "curve":"linear" and "curveX":"stepped", curveX must win.
      final json = _skelBase +
          '"animations":[{"name":"a","boneTimelines":[{'
              '"bone":"root","property":"translate",'
              '"keyframes":['
              '{"t":0.0,"x":0.0,"y":0.0,"curve":"linear","curveX":"stepped"},'
              '{"t":1.0,"x":10.0,"y":10.0}]}]}]}';
      final data = loadBonyJson(json);
      final tl = data.animations[0].boneTimelines[0];
      // curveX should be stepped (overrides "curve":"linear")
      expect(tl.vectorKeys[0].curveX.kind, TimelineCurveKind.stepped);
      // curveY falls back to "curve":"linear"
      expect(tl.vectorKeys[0].curveY.kind, TimelineCurveKind.linear);
      // Sampling: stepped X stays at 0 at t=0.5; linear Y interpolates.
      final (x, y) = sampleBoneVectorTimeline(tl, 0.5);
      _expectClose(x, 0.0, 'stepped x at 0.5');
      _expectClose(y, 5.0, 'linear y at 0.5');
    });

    test('[applyPose] preserves parameters, deformers, stateMachines', () {
      // Use m8_rig.bony which has stateMachines; after applyPose they must survive.
      final text = File('../conformance/assets/m8_rig.bony').readAsStringSync();
      final data = loadBonyJson(text);
      expect(data.stateMachines, isNotEmpty);

      final pose = const MixedPose.empty();
      final result = applyPose(data, pose);
      // Empty pose returns data unchanged — but also test a non-empty pose.
      expect(result.stateMachines, hasLength(data.stateMachines.length));

      // Non-empty pose (rotate bone) — stateMachines must survive.
      final pose2 = MixedPose(
        scalars: [(bone: 'root', kind: BoneTimelineKind.rotate, value: 45.0)],
        vectors: const [],
        attachments: const [],
        inherits: const [],
        colors: const [],
        colors2: const [],
        sequences: const [],
        deforms: const [],
      );
      final result2 = applyPose(data, pose2);
      expect(result2.stateMachines, hasLength(data.stateMachines.length));
      expect(result2.stateMachines.first.name, data.stateMachines.first.name);
    });
  });
}
