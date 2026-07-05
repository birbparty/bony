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
    // property keys, and required name/slot/attachment/target entries).
    expect(bonyTypeKeys, hasLength(32));
    expect(bonyTypeKeys.any((t) => t.id == 'skin' && t.key == 3003), isTrue);
    expect(
        bonyTypeKeys.any((t) => t.id == 'skinEntry' && t.key == 3004), isTrue);
    expect(bonyPropertyKeys, hasLength(108));
    expect(
        bonyPropertyKeys.any((p) => p.id == 'skinAttachment' && p.key == 3010),
        isTrue);
    expect(bonyPropertyKeys.any((p) => p.id == 'skinTarget' && p.key == 3011),
        isTrue);
    expect(bonyPropertyDefaults, hasLength(55));
    expect(bonyRequiredProperties, hasLength(84));
  });
}
