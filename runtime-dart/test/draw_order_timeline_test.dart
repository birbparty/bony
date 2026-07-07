import 'dart:typed_data' show ByteData, Endian, Uint8List;

import 'package:bony/bony.dart';
import 'package:test/test.dart';

const _baseJson = '{"skeleton":{"name":"draw_order"},'
    '"bones":[{"name":"root"}],'
    '"slots":['
    '{"name":"back","bone":"root","attachment":"back_region"},'
    '{"name":"middle","bone":"root","attachment":"middle_region"},'
    '{"name":"front","bone":"root","attachment":"front_region"}'
    '],'
    '"regions":['
    '{"name":"back_region","width":10,"height":10},'
    '{"name":"middle_region","width":10,"height":10},'
    '{"name":"front_region","width":10,"height":10}'
    ']';

String _jsonWithAnimation(String animation) =>
    '$_baseJson,"animations":[$animation]}';

String _validAnimation({String timeline = ''}) =>
    '{"name":"swap","drawOrderTimeline":$timeline}';

void _writeVaruint(List<int> out, int value) {
  var v = value;
  while (true) {
    var byte = v & 0x7f;
    v >>= 7;
    if (v != 0) byte |= 0x80;
    out.add(byte);
    if (v == 0) break;
  }
}

List<int> _varuintBytes(int value) {
  final out = <int>[];
  _writeVaruint(out, value);
  return out;
}

List<int> _varintBytes(int value) {
  final encoded = value < 0 ? ((-value - 1) << 1) | 1 : value << 1;
  return _varuintBytes(encoded);
}

List<int> _f32Bytes(double value) {
  final bytes = ByteData(4)..setFloat32(0, value, Endian.little);
  return bytes.buffer.asUint8List().toList();
}

void _writeProp(List<int> out, int key, List<int> payload) {
  _writeVaruint(out, key);
  _writeVaruint(out, payload.length);
  out.addAll(payload);
}

List<int> _str(int index) => _varuintBytes(index);

List<int> _drawOrderPayload({
  int firstSlotIndex = 0,
  int firstOffset = 2,
}) {
  final out = <int>[];
  _writeVaruint(out, 2);
  out.addAll(_f32Bytes(0.25));
  _writeVaruint(out, 2);
  _writeVaruint(out, firstSlotIndex);
  out.addAll(_varintBytes(firstOffset));
  _writeVaruint(out, 2);
  out.addAll(_varintBytes(-2));
  out.addAll(_f32Bytes(0.75));
  _writeVaruint(out, 0);
  return out;
}

Uint8List _drawOrderBnb({
  bool includeDrawOrderKeys = true,
  bool duplicateDrawOrderTimeline = false,
  int firstSlotIndex = 0,
}) {
  final strings = [
    'draw_order',
    'root',
    'back',
    'middle',
    'front',
    'back_region',
    'middle_region',
    'front_region',
    'swap',
  ];
  final out = <int>[0x42, 0x4f, 0x4e, 0x59];
  _writeVaruint(out, 0); // version 0.0
  _writeVaruint(out, 2); // string table flag
  final toc = [
    (key: bonyPropertyKeyName, backing: 5),
    (key: bonyPropertyKeyBone, backing: 5),
    (key: bonyPropertyKeyAttachment, backing: 5),
    (key: bonyPropertyKeyWidth, backing: 3),
    (key: bonyPropertyKeyHeight, backing: 3),
    (key: bonyPropertyKeyDrawOrderKeys, backing: 7),
  ];
  _writeVaruint(out, toc.length);
  for (final entry in toc) {
    _writeVaruint(out, entry.key);
    out.add(entry.backing);
  }
  _writeVaruint(out, strings.length);
  for (final s in strings) {
    final units = s.codeUnits;
    _writeVaruint(out, units.length);
    out.addAll(units);
  }

  void object(int typeKey, void Function(List<int>) props) {
    _writeVaruint(out, typeKey);
    props(out);
    _writeVaruint(out, 0);
  }

  object(
      bonyTypeKeySkeleton, (o) => _writeProp(o, bonyPropertyKeyName, _str(0)));
  object(bonyTypeKeyBone, (o) => _writeProp(o, bonyPropertyKeyName, _str(1)));
  object(bonyTypeKeySlot, (o) {
    _writeProp(o, bonyPropertyKeyName, _str(2));
    _writeProp(o, bonyPropertyKeyBone, _str(1));
    _writeProp(o, bonyPropertyKeyAttachment, _str(5));
  });
  object(bonyTypeKeySlot, (o) {
    _writeProp(o, bonyPropertyKeyName, _str(3));
    _writeProp(o, bonyPropertyKeyBone, _str(1));
    _writeProp(o, bonyPropertyKeyAttachment, _str(6));
  });
  object(bonyTypeKeySlot, (o) {
    _writeProp(o, bonyPropertyKeyName, _str(4));
    _writeProp(o, bonyPropertyKeyBone, _str(1));
    _writeProp(o, bonyPropertyKeyAttachment, _str(7));
  });
  for (var i = 0; i < 3; i++) {
    object(bonyTypeKeyRegion, (o) {
      _writeProp(o, bonyPropertyKeyName, _str(5 + i));
      _writeProp(o, bonyPropertyKeyWidth, _f32Bytes(10));
      _writeProp(o, bonyPropertyKeyHeight, _f32Bytes(10));
    });
  }
  object(bonyTypeKeyAnimationClip,
      (o) => _writeProp(o, bonyPropertyKeyName, _str(8)));
  void drawOrderObject() {
    object(bonyTypeKeyDrawOrderTimeline, (o) {
      if (includeDrawOrderKeys) {
        _writeProp(
          o,
          bonyPropertyKeyDrawOrderKeys,
          _drawOrderPayload(firstSlotIndex: firstSlotIndex),
        );
      }
    });
  }

  drawOrderObject();
  if (duplicateDrawOrderTimeline) drawOrderObject();
  _writeVaruint(out, 0);
  return Uint8List.fromList(out);
}

void main() {
  group('draw-order JSON loader and validation', () {
    test(
        'loads a valid timeline, normalizes zero offsets, and computes duration',
        () {
      final data = loadBonyJson(_jsonWithAnimation(_validAnimation(
        timeline: '{"keyframes":['
            '{"t":0.25,"offsets":['
            '{"slot":"back","offset":2},'
            '{"slot":"middle","offset":0},'
            '{"slot":"front","offset":-2}]},'
            '{"t":0.75,"offsets":[]}]}',
      )));

      final clip = data.animations.single;
      expect(clip.duration, 0.75);
      final timeline = clip.drawOrderTimeline!;
      expect(timeline.keys, hasLength(2));
      expect(timeline.keys.first.offsets.map((o) => o.slot), ['back', 'front']);
      expect(timeline.keys.last.offsets, isEmpty);
    });

    test('rejects unknown slots with drawOrderTimeline context', () {
      expect(
        () => loadBonyJson(_jsonWithAnimation(_validAnimation(
          timeline: '{"keyframes":[{"t":0.0,"offsets":['
              '{"slot":"missing","offset":1}]}]}',
        ))),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('drawOrderTimeline'))
            .having((e) => e.message, 'message', contains('unknown slot'))),
      );
    });

    test('rejects duplicate offset slots after zero normalization', () {
      expect(
        () => loadBonyJson(_jsonWithAnimation(_validAnimation(
          timeline: '{"keyframes":[{"t":0.0,"offsets":['
              '{"slot":"back","offset":1},'
              '{"slot":"back","offset":2}]}]}',
        ))),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('duplicate slot'))),
      );
    });

    test('rejects negative and out-of-range target indices', () {
      expect(
        () => loadBonyJson(_jsonWithAnimation(_validAnimation(
          timeline: '{"keyframes":[{"t":0.0,"offsets":['
              '{"slot":"back","offset":-1}]}]}',
        ))),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('target index out of range'))),
      );
      expect(
        () => loadBonyJson(_jsonWithAnimation(_validAnimation(
          timeline: '{"keyframes":[{"t":0.0,"offsets":['
              '{"slot":"front","offset":1}]}]}',
        ))),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('target index out of range'))),
      );
    });

    test('rejects duplicate target indices caused by implicit zero offsets',
        () {
      expect(
        () => loadBonyJson(_jsonWithAnimation(_validAnimation(
          timeline: '{"keyframes":[{"t":0.0,"offsets":['
              '{"slot":"back","offset":1}]}]}',
        ))),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('duplicate target index'))),
      );
    });

    test('rejects empty timelines and non-strict key times', () {
      expect(
        () => loadBonyJson(
            _jsonWithAnimation(_validAnimation(timeline: '{"keyframes":[]}'))),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('must not be empty'))),
      );
      expect(
        () => loadBonyJson(_jsonWithAnimation(_validAnimation(
          timeline: '{"keyframes":[{"t":0.5},{"t":0.5}]}',
        ))),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('strictly increasing'))),
      );
    });

    test('rejects dynamic clipping ranges made invalid by sampled draw order',
        () {
      const clipped = '{"skeleton":{"name":"clip_draw_order"},'
          '"bones":[{"name":"root"}],'
          '"slots":['
          '{"name":"clip","bone":"root","attachment":"mask"},'
          '{"name":"panel","bone":"root","attachment":"panel_region"},'
          '{"name":"end","bone":"root","attachment":"end_region"}'
          '],'
          '"regions":['
          '{"name":"panel_region","width":10,"height":10},'
          '{"name":"end_region","width":10,"height":10}'
          '],'
          '"clippingAttachments":['
          '{"name":"mask","vertices":[-10,-10,10,-10,0,10],"untilSlot":"end"}'
          '],'
          '"animations":[{"name":"bad","drawOrderTimeline":{"keyframes":[{'
          '"t":0.1,"offsets":['
          '{"slot":"clip","offset":2},{"slot":"end","offset":-2}'
          ']}]}}]}';
      expect(
        () => loadBonyJson(clipped),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('clipping slot clip'))),
      );
    });
  });

  group('draw-order sampler, mixer, and pose application', () {
    late SkeletonData data;
    late AnimationClip clip;

    setUp(() {
      data = loadBonyJson(_jsonWithAnimation(_validAnimation(
        timeline: '{"keyframes":['
            '{"t":0.25,"offsets":['
            '{"slot":"back","offset":2},'
            '{"slot":"front","offset":-2}]},'
            '{"t":0.75,"offsets":[]}]}',
      )));
      clip = data.animations.single;
    });

    test(
        'sampleDrawOrderTimeline uses setup before first key, hold, and restore',
        () {
      final timeline = clip.drawOrderTimeline!;
      expect(sampleDrawOrderTimeline(timeline, data.slots, 0.0),
          ['back', 'middle', 'front']);
      expect(sampleDrawOrderTimeline(timeline, data.slots, 0.25),
          ['front', 'middle', 'back']);
      expect(sampleDrawOrderTimeline(timeline, data.slots, 0.5),
          ['front', 'middle', 'back']);
      expect(sampleDrawOrderTimeline(timeline, data.slots, 0.75),
          ['back', 'middle', 'front']);
    });

    test('AnimationState samples draw order under mixAttachmentThreshold', () {
      final state = AnimationState(data)..setAnimation(0, clip);
      state.update(0.5);
      expect(state.sample().drawOrder, ['front', 'middle', 'back']);

      final blocked = AnimationState(data);
      blocked.setAnimation(0, clip);
      final track = blocked.tracks.single;
      track.mixAttachmentThreshold = 0.75;
      track.alpha = 0.5;
      blocked.update(0.5);
      expect(blocked.sample().drawOrder, isNull);
    });

    test('applyPose reorders slots and buildDrawBatches follows sampled order',
        () {
      final state = AnimationState(data)..setAnimation(0, clip);
      state.update(0.5);
      final posed = applyPose(data, state.sample());

      expect(posed.slots.map((s) => s.name), ['front', 'middle', 'back']);
      expect(buildDrawBatches(posed).map((b) => b.slot),
          ['front', 'middle', 'back']);
    });

    test('draw-order-only applyPose preserves other SkeletonData fields', () {
      final posed = applyPose(
        data,
        const MixedPose(
          scalars: [],
          vectors: [],
          attachments: [],
          inherits: [],
          colors: [],
          colors2: [],
          sequences: [],
          deforms: [],
          drawOrder: ['front', 'middle', 'back'],
        ),
      );

      expect(posed.bones, same(data.bones));
      expect(posed.regions, same(data.regions));
      expect(posed.animations, same(data.animations));
      expect(posed.deformOverrides, isEmpty);
      expect(posed.slots.map((s) => s.name), ['front', 'middle', 'back']);
    });

    test('clipping ranges use sampled slot order after applyPose', () {
      const clipped = '{"skeleton":{"name":"clip_sampled_order"},'
          '"bones":[{"name":"root"}],'
          '"slots":['
          '{"name":"left","bone":"root","attachment":"left_region"},'
          '{"name":"clip","bone":"root","attachment":"mask"},'
          '{"name":"middle","bone":"root","attachment":"middle_region"},'
          '{"name":"end","bone":"root","attachment":"end_region"}'
          '],'
          '"regions":['
          '{"name":"left_region","width":10,"height":10},'
          '{"name":"middle_region","width":10,"height":10},'
          '{"name":"end_region","width":10,"height":10}'
          '],'
          '"clippingAttachments":['
          '{"name":"mask","vertices":[-20,-20,20,-20,0,20],"untilSlot":"end"}'
          '],'
          '"animations":[{"name":"swap_clip","drawOrderTimeline":{"keyframes":[{'
          '"t":0.1,"offsets":['
          '{"slot":"left","offset":2},{"slot":"middle","offset":-2}'
          ']}]}}]}';
      final clipData = loadBonyJson(clipped);
      final state = AnimationState(clipData)
        ..setAnimation(0, clipData.animations.single)
        ..update(0.1);
      final posed = applyPose(clipData, state.sample());
      expect(posed.slots.map((s) => s.name), ['middle', 'clip', 'left', 'end']);

      final clipIdBySlot = {
        for (final batch in buildDrawBatches(posed)) batch.slot: batch.clipId,
      };
      expect(clipIdBySlot['middle'], '');
      expect(clipIdBySlot['left'], 'mask');
      expect(clipIdBySlot['end'], 'mask');
    });
  });

  group('draw-order .bnb decoder', () {
    test('decodes drawOrderKeys payload equivalent to JSON', () {
      final data = loadBonyBnb(_drawOrderBnb());
      final clip = data.animations.single;

      expect(clip.duration, 0.75);
      expect(sampleDrawOrderTimeline(clip.drawOrderTimeline!, data.slots, 0.5),
          ['front', 'middle', 'back']);
    });

    test('rejects missing drawOrderKeys', () {
      expect(
        () => loadBonyBnb(_drawOrderBnb(includeDrawOrderKeys: false)),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('drawOrderTimeline.drawOrderKeys is required'))),
      );
    });

    test('rejects duplicate drawOrderTimeline child records', () {
      expect(
        () => loadBonyBnb(_drawOrderBnb(duplicateDrawOrderTimeline: true)),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('duplicate drawOrderTimeline'))),
      );
    });

    test('rejects out-of-range draw-order slot indices', () {
      expect(
        () => loadBonyBnb(_drawOrderBnb(firstSlotIndex: 3)),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('slotIndex is out of range'))),
      );
    });
  });
}
