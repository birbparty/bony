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
    // Counts include the ikConstraint object added to the registry in
    // iteration 120 (typeKey 4002 + bones/mix/bendPositive property keys,
    // defaults, and required properties).
    expect(bonyTypeKeys, hasLength(24));
    expect(bonyPropertyKeys, hasLength(85));
    expect(bonyPropertyDefaults, hasLength(40));
    expect(bonyRequiredProperties, hasLength(62));
  });
}
