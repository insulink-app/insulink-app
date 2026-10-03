import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/vendor_keys/vendor_keys.dart';

void main() {
  test('a build without the key file names both devices', () {
    expect(VendorKeys.empty().missingDevices, ['Dexcom G7', 'Omnipod DASH']);
  });

  test('a complete key file leaves nothing missing', () {
    final keys = VendorKeys.fromJson('''
      {
        "dexcom": {
          "display_certificates": ["3082", "3083"],
          "display_private_key": "${'ab' * 32}"
        },
        "omnipod": {"milenage_operator": "${'cd' * 16}"}
      }
    ''');
    expect(keys.missingDevices, isEmpty);
    expect(keys.dexcomDisplayCertificates.first, [0x30, 0x82]);
  });

  test('a short key counts as missing, not as loaded', () {
    final keys = VendorKeys.fromJson(
      '{"omnipod": {"milenage_operator": "cdc2"}}',
    );
    expect(keys.missingDevices, ['Dexcom G7', 'Omnipod DASH']);
  });
}
