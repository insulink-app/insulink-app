import 'dart:io';

import 'package:insulink/src/vendor_keys/vendor_keys.dart';

/// Installs the local, gitignored vendor keys for the tests that replay
/// captured pod sessions, which cannot run without the Omnipod operator
/// constant. Returns the skip reason when they are missing, so a checkout
/// without them reports those tests as skipped rather than failed.
String? installOmnipodVendorKeys() {
  final file = File(VendorKeys.assetPath);
  if (file.existsSync()) {
    VendorKeys.current = VendorKeys.fromJson(file.readAsStringSync());
  }
  if (VendorKeys.current.hasOmnipod) {
    return null;
  }
  return 'Omnipod vendor keys missing, see docs/VENDOR_KEYS.md';
}
