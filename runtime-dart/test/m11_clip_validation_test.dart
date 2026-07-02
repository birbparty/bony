import 'package:bony/bony.dart';
import 'package:test/test.dart';

/// Load-time validation parity for clipping attachments (mirrors the Nim loader
/// checks in runtime-nim/src/bony/model.nim). A rig that Nim rejects at load
/// must also be rejected by the Dart loader with a clean [FormatException],
/// not an opaque runtime error later in buildDrawBatches.
String _rig(String clipVertices, String untilSlot,
    {String extra = ''}) {
  return '''
{
  "skeleton": {"name": "clip-val", "version": "1.0.0"},
  "bones": [{"name": "root"}],
  "regions": [{"name": "panel", "width": 100, "height": 100}],
  "slots": [
    {"name": "clip_slot", "bone": "root", "attachment": "mask"},
    {"name": "panel_slot", "bone": "root", "attachment": "panel"},
    {"name": "tail_slot", "bone": "root"}
    $extra
  ],
  "clippingAttachments": [
    {"name": "mask", "vertices": [$clipVertices], "untilSlot": "$untilSlot"}
  ]
}
''';
}

void main() {
  test('accepts a slot whose attachment names a clipping attachment', () {
    final data = loadBonyJson(_rig('-200, -200, 230, -200, -200, 230', 'panel_slot'));
    expect(data.clippingAttachments, hasLength(1));
    expect(data.clippingAttachments.single.name, 'mask');
  });

  test('rejects a non-convex clip polygon', () {
    expect(
      () => loadBonyJson(_rig('0, 0, 2, 0, 0.5, 0.5, 0, 2', 'panel_slot')),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a clip polygon with fewer than three vertices', () {
    expect(
      () => loadBonyJson(_rig('0, 0, 1, 1', 'panel_slot')),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects an unknown untilSlot with a clean FormatException', () {
    expect(
      () => loadBonyJson(_rig('-200, -200, 230, -200, -200, 230', 'nope')),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects an untilSlot at or before the clip\'s own slot', () {
    // Move the clip's own slot after panel_slot so untilSlot=panel_slot is behind.
    final rig = '''
{
  "skeleton": {"name": "clip-val", "version": "1.0.0"},
  "bones": [{"name": "root"}],
  "regions": [{"name": "panel", "width": 100, "height": 100}],
  "slots": [
    {"name": "panel_slot", "bone": "root", "attachment": "panel"},
    {"name": "clip_slot", "bone": "root", "attachment": "mask"}
  ],
  "clippingAttachments": [
    {"name": "mask", "vertices": [-200, -200, 230, -200, -200, 230], "untilSlot": "panel_slot"}
  ]
}
''';
    expect(() => loadBonyJson(rig), throwsA(isA<FormatException>()));
  });

  test('rejects overlapping clip ranges', () {
    final rig = '''
{
  "skeleton": {"name": "clip-val", "version": "1.0.0"},
  "bones": [{"name": "root"}],
  "regions": [{"name": "panel", "width": 100, "height": 100}],
  "slots": [
    {"name": "clip_a", "bone": "root", "attachment": "m1"},
    {"name": "clip_b", "bone": "root", "attachment": "m2"},
    {"name": "s_c", "bone": "root", "attachment": "panel"},
    {"name": "s_d", "bone": "root", "attachment": "panel"}
  ],
  "clippingAttachments": [
    {"name": "m1", "vertices": [-200, -200, 230, -200, -200, 230], "untilSlot": "s_c"},
    {"name": "m2", "vertices": [-200, -200, 230, -200, -200, 230], "untilSlot": "s_d"}
  ]
}
''';
    expect(() => loadBonyJson(rig), throwsA(isA<FormatException>()));
  });

  test('rejects a clip name that collides with a region name', () {
    final rig = '''
{
  "skeleton": {"name": "clip-val", "version": "1.0.0"},
  "bones": [{"name": "root"}],
  "regions": [{"name": "shared", "width": 100, "height": 100}],
  "slots": [
    {"name": "clip_slot", "bone": "root", "attachment": "shared"},
    {"name": "panel_slot", "bone": "root"}
  ],
  "clippingAttachments": [
    {"name": "shared", "vertices": [-200, -200, 230, -200, -200, 230], "untilSlot": "panel_slot"}
  ]
}
''';
    expect(() => loadBonyJson(rig), throwsA(isA<FormatException>()));
  });
}
