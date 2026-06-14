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
    expect(bonyTypeKeys, hasLength(6));
    expect(bonyPropertyKeys, hasLength(30));
    expect(bonyPropertyDefaults, hasLength(15));
    expect(bonyRequiredProperties, hasLength(20));
  });
}
