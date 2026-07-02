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
    // meshTriangles).
    expect(bonyTypeKeys, hasLength(28));
    expect(bonyPropertyKeys, hasLength(101));
    expect(bonyPropertyDefaults, hasLength(55));
    expect(bonyRequiredProperties, hasLength(74));
  });
}
