// Dart M6 conformance gate: .bnb binary loader parity with JSON loader.
//
// For each rig with a .bnb file: decode via loadBonyBnb, decode the same rig
// via loadBonyJson, compute world transforms + draw batches for both, and
// confirm the results are numerically identical (abs <= 1e-4).
//
// m7 and m8 rigs contain deformer objects (type keys 6000-6005). Both loaders
// skip them, so parity is expected even though the archived goldens include
// deformer-applied vertices (which are an M7 concern, not M6).
//
// Also validates that forward_compat.bnb (unknown type-key object) decodes
// without throwing — the skeleton + root bone must load correctly.
//
// Tests run from runtime-dart/ so ../conformance/ resolves to repo root.

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

void _expectAffine(Affine2 actual, Affine2 expected, String label) {
  _expectClose(actual.a, expected.a, '$label.a');
  _expectClose(actual.b, expected.b, '$label.b');
  _expectClose(actual.c, expected.c, '$label.c');
  _expectClose(actual.d, expected.d, '$label.d');
  _expectClose(actual.tx, expected.tx, '$label.tx');
  _expectClose(actual.ty, expected.ty, '$label.ty');
}

// Register all parity tests for a rig (bnb decoder == json decoder).
void _checkRig(String rigName) {
  late SkeletonData jsonData;
  late SkeletonData bnbData;
  late List<Affine2> jsonWorlds;
  late List<Affine2> bnbWorlds;
  late List<DrawBatch> jsonBatches;
  late List<DrawBatch> bnbBatches;

  setUpAll(() {
    jsonData = loadBonyJson(
      File('../conformance/assets/$rigName.bony').readAsStringSync(),
    );
    bnbData = loadBonyBnb(
      File('../conformance/assets/bnb/$rigName.bnb').readAsBytesSync(),
    );
    jsonWorlds = computeWorldTransforms(jsonData);
    bnbWorlds = computeWorldTransforms(bnbData);
    jsonBatches = buildDrawBatches(jsonData);
    bnbBatches = buildDrawBatches(bnbData);
  });

  test('skeleton name matches JSON', () {
    expect(bnbData.header.name, jsonData.header.name);
  });

  test('bone count matches JSON', () {
    expect(bnbData.bones, hasLength(jsonData.bones.length));
  });

  test('all bone names match JSON (same order)', () {
    for (var i = 0; i < jsonData.bones.length; i++) {
      expect(bnbData.bones[i].name, jsonData.bones[i].name,
          reason: 'bones[$i].name');
    }
  });

  test('all bone world matrices match JSON (abs <= 1e-4)', () {
    expect(bnbWorlds, hasLength(jsonWorlds.length));
    for (var i = 0; i < jsonWorlds.length; i++) {
      _expectAffine(bnbWorlds[i], jsonWorlds[i],
          '$rigName/bones[${jsonData.bones[i].name}].world');
    }
  });

  test('draw batch count matches JSON', () {
    expect(bnbBatches, hasLength(jsonBatches.length));
  });

  test('draw batch metadata (slot/bone/attachment) matches JSON', () {
    for (var i = 0; i < jsonBatches.length; i++) {
      expect(bnbBatches[i].slot, jsonBatches[i].slot,
          reason: '$rigName batches[$i].slot');
      expect(bnbBatches[i].bone, jsonBatches[i].bone,
          reason: '$rigName batches[$i].bone');
      expect(bnbBatches[i].attachment, jsonBatches[i].attachment,
          reason: '$rigName batches[$i].attachment');
      expect(bnbBatches[i].blendMode, jsonBatches[i].blendMode,
          reason: '$rigName batches[$i].blendMode');
      expect(bnbBatches[i].texturePage, jsonBatches[i].texturePage,
          reason: '$rigName batches[$i].texturePage');
    }
  });

  test('draw batch world matrices match JSON (abs <= 1e-4)', () {
    for (var i = 0; i < jsonBatches.length; i++) {
      _expectAffine(bnbBatches[i].world, jsonBatches[i].world,
          '$rigName drawBatches[$i].world');
    }
  });

  test('draw batch vertices match JSON (abs <= 1e-4)', () {
    for (var i = 0; i < jsonBatches.length; i++) {
      expect(bnbBatches[i].vertices, hasLength(jsonBatches[i].vertices.length),
          reason: '$rigName batches[$i].vertices count');
      for (var j = 0; j < jsonBatches[i].vertices.length; j++) {
        final jv = jsonBatches[i].vertices[j];
        final bv = bnbBatches[i].vertices[j];
        final pfx = '$rigName drawBatches[$i].vertices[$j]';
        _expectClose(bv.x, jv.x, '$pfx.x');
        _expectClose(bv.y, jv.y, '$pfx.y');
        _expectClose(bv.u, jv.u, '$pfx.u');
        _expectClose(bv.v, jv.v, '$pfx.v');
        _expectClose(bv.r, jv.r, '$pfx.r');
        _expectClose(bv.g, jv.g, '$pfx.g');
        _expectClose(bv.b, jv.b, '$pfx.b');
        _expectClose(bv.a, jv.a, '$pfx.a');
      }
    }
  });

  test('draw batch indices match JSON exactly', () {
    for (var i = 0; i < jsonBatches.length; i++) {
      expect(bnbBatches[i].indices, jsonBatches[i].indices,
          reason: '$rigName drawBatches[$i].indices');
    }
  });
}

void main() {
  // --- forward compatibility ---
  group('forward_compat.bnb: unknown type skipped gracefully', () {
    late SkeletonData data;
    setUpAll(() {
      data = loadBonyBnb(
        File('../conformance/assets/bnb/forward_compat.bnb').readAsBytesSync(),
      );
    });
    test('loads without throwing', () {
      expect(data, isNotNull);
    });
    test('skeleton name is m6-compat', () {
      expect(data.header.name, 'm6-compat');
    });
    test('root bone is present', () {
      expect(data.bones.any((b) => b.name == 'root'), isTrue);
    });
  });

  // --- bnb == json parity for all rigs ---
  for (final rigName in [
    'm1_rig',
    'm2_rig',
    'm3_rig',
    'm4_rig',
    'm5_rig',
    'm7_rig',
    'm8_rig',
    'm24_atlas_region_rig',
  ]) {
    group('$rigName.bnb parity with JSON loader', () => _checkRig(rigName));
  }
}
