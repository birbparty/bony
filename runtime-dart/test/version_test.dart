import 'package:test/test.dart';
import 'package:bony/bony.dart';

void main() {
  test('exposes version', () {
    expect(bonyVersion, '0.1.0');
  });

  test('exports generated registry metadata', () {
    expect(bonyRegistryVersion, 1);
    expect(bonyBackingTypes, hasLength(8));
    expect(bonyBackingTypes.first.id, 'varuint');
    // Counts include the transformConstraint object added in iteration 152
    // (typeKey 4003 + scaleMix/shearMix property keys 4017/4018, 5 defaults
    // order+4 mixes, and 3 required properties name/bone/target), plus the
    // physicsConstraint object added by the M5 physics milestone: typeKey 4004,
    // 8 property keys (inertia/strength/damping/mass/gravity/wind/physicsMix/
    // channels, 4019..4026), 8 defaults (order + the 7 f32 params), and 3
    // required properties (name/bone/channels), plus the M4 clippingAttachment
    // object (typeKey 3000, property keys vertices/untilSlot 3000/3001, 1 default
    // untilSlot, 2 required name/vertices), plus the M4 meshAttachment object
    // (typeKey 3001, property keys meshWeighted/meshVertices/meshUvs/meshTriangles
    // 3002..3005, 1 default meshWeighted, 4 required name/meshVertices/meshUvs/
    // meshTriangles), plus the M4 deformTimeline object (typeKey 3002, property
    // keys deformSkin/deformAttachment/deformVertexCount/deformKeys 3006..3009
    // — slot reuses the shared 1011, no defaults, 5 required deformSkin/slot/
    // deformAttachment/deformVertexCount/deformKeys), plus the M3 event-timeline
    // milestone eventTimeline object (typeKey 2003, property key eventKeys 2005 —
    // no defaults, 1 required eventKeys; the record's only property packs the
    // whole keyframe list per docs/event-timeline-contract.md), plus M20 skin
    // attachment sets (skin/skinEntry type keys, skinAttachment/skinTarget
    // property keys, and required name/slot/attachment/target entries), plus
    // helper geometry point/boundingBox attachments (type keys 1002/1003, no
    // new property keys because they reuse name/x/y/rotation/vertices, and 6
    // required properties), plus pointer helper listener fields (7 appended M8
    // property keys 7064..7070, 8 default-table entries including
    // listenerLayerIndex, and listenerLayerIndex moved out of unconditional
    // requiredProperties), plus nestedRigAttachment (type key 3005, property
    // keys 3012..3014, 2 defaults, and 2 required properties), plus
    // skinRequired activation (property keys 4027..4032 and 10 default-table
    // entries), plus atlas-backed region texture metadata (property keys
    // 8000..8005 and 6 default-table entries).
    expect(bonyTypeKeys, hasLength(35));
    expect(bonyTypeKeys.any((t) => t.id == 'pointAttachment' && t.key == 1002),
        isTrue);
    expect(
        bonyTypeKeys
            .any((t) => t.id == 'boundingBoxAttachment' && t.key == 1003),
        isTrue);
    expect(bonyTypeKeys.any((t) => t.id == 'skin' && t.key == 3003), isTrue);
    expect(
        bonyTypeKeys.any((t) => t.id == 'skinEntry' && t.key == 3004), isTrue);
    expect(
        bonyTypeKeys.any((t) => t.id == 'nestedRigAttachment' && t.key == 3005),
        isTrue);
    expect(bonyPropertyKeys, hasLength(130));
    expect(
        bonyPropertyKeys.any((p) => p.id == 'skinAttachment' && p.key == 3010),
        isTrue);
    expect(bonyPropertyKeys.any((p) => p.id == 'skinTarget' && p.key == 3011),
        isTrue);
    expect(
        bonyPropertyKeys.any((p) => p.id == 'nestedSkeleton' && p.key == 3012),
        isTrue);
    expect(bonyPropertyKeys.any((p) => p.id == 'nestedSkin' && p.key == 3013),
        isTrue);
    expect(
        bonyPropertyKeys.any((p) => p.id == 'nestedAnimation' && p.key == 3014),
        isTrue);
    expect(bonyPropertyKeys.any((p) => p.id == 'skinRequired' && p.key == 4027),
        isTrue);
    expect(bonyPropertyKeys.any((p) => p.id == 'skinBones' && p.key == 4028),
        isTrue);
    expect(
        bonyPropertyKeys
            .any((p) => p.id == 'skinPhysicsConstraints' && p.key == 4032),
        isTrue);
    expect(
        bonyPropertyKeys
            .any((p) => p.id == 'listenerSlotIndex' && p.key == 7064),
        isTrue);
    expect(
        bonyPropertyKeys
            .any((p) => p.id == 'listenerHitRadius' && p.key == 7070),
        isTrue);
    expect(bonyPropertyKeys.any((p) => p.id == 'texturePage' && p.key == 8000),
        isTrue);
    expect(bonyPropertyKeys.any((p) => p.id == 'u0' && p.key == 8001), isTrue);
    expect(bonyPropertyKeys.any((p) => p.id == 'v0' && p.key == 8002), isTrue);
    expect(bonyPropertyKeys.any((p) => p.id == 'u1' && p.key == 8003), isTrue);
    expect(bonyPropertyKeys.any((p) => p.id == 'v1' && p.key == 8004), isTrue);
    expect(bonyPropertyKeys.any((p) => p.id == 'alphaMode' && p.key == 8005),
        isTrue);
    expect(bonyPropertyDefaults, hasLength(81));
    expect(
        bonyPropertyDefaults.any((d) =>
            d.objectId == 'region' &&
            d.propertyId == 'texturePage' &&
            d.value == '""'),
        isTrue);
    expect(
        bonyPropertyDefaults.any((d) =>
            d.objectId == 'region' && d.propertyId == 'u0' && d.value == '0.0'),
        isTrue);
    expect(
        bonyPropertyDefaults.any((d) =>
            d.objectId == 'region' && d.propertyId == 'v0' && d.value == '0.0'),
        isTrue);
    expect(
        bonyPropertyDefaults.any((d) =>
            d.objectId == 'region' && d.propertyId == 'u1' && d.value == '1.0'),
        isTrue);
    expect(
        bonyPropertyDefaults.any((d) =>
            d.objectId == 'region' && d.propertyId == 'v1' && d.value == '1.0'),
        isTrue);
    expect(
        bonyPropertyDefaults.any((d) =>
            d.objectId == 'region' &&
            d.propertyId == 'alphaMode' &&
            d.value == '"straight"'),
        isTrue);
    expect(bonyRequiredProperties, hasLength(91));
  });
}
