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
    // Counts include the transformConstraint object added to the registry in
    // iteration 152 (typeKey 4003 + scaleMix/shearMix property keys 4017/4018,
    // 5 defaults order+4 mixes, and 3 required properties name/bone/target).
    expect(bonyTypeKeys, hasLength(25));
    expect(bonyPropertyKeys, hasLength(87));
    expect(bonyPropertyDefaults, hasLength(45));
    expect(bonyRequiredProperties, hasLength(65));
  });
}
