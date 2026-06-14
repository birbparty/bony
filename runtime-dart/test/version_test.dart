import 'package:test/test.dart';
import 'package:bony/bony.dart';

void main() {
  test('exposes version', () {
    expect(bonyVersion, '0.1.0');
  });

  test('exports generated registry metadata', () {
    expect(bonyRegistryVersion, 1);
    expect(bonyBackingTypes, hasLength(7));
    expect(bonyBackingTypes.first.id, 'varuint');
    expect(bonyPropertyDefaults, isEmpty);
    expect(bonyRequiredProperties, isEmpty);
  });
}
