import 'dart:convert';

import 'package:flutter/services.dart';

/// Decodes the bundle bytes in place, like the locale loaders (never
/// `loadString`, see `docs/LOCALIZATION.md`).
String _utf8(ByteData data) => utf8.decode(
  data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
);

/// Decodes a lowercase or uppercase hex string into bytes.
Uint8List _hex(String hex) => Uint8List.fromList([
  for (var index = 0; index + 1 < hex.length; index += 2)
    int.parse(hex.substring(index, index + 2), radix: 16),
]);

/// The manufacturers' key material: the Dexcom G7 display certificate chain and
/// its signing key, and the Omnipod DASH Milenage operator constant.
///
/// It is not ours to publish, so it is never committed. Each build bundles it
/// from the gitignored `assets/vendor_keys/vendor_keys.json` (see
/// `docs/VENDOR_KEYS.md`). Without that file every field is empty: the app warns
/// on start ([VendorKeysWarning]) and the affected device refuses to pair.
///
/// Loaded once per isolate, like `RustCore`: the UI isolate in `main`, the
/// service isolate before it touches the CGM or the pod.
class VendorKeys {
  VendorKeys({
    required this.dexcomDisplayCertificates,
    required this.dexcomDisplayKey,
    required this.omnipodOperator,
  });

  VendorKeys.empty()
    : dexcomDisplayCertificates = const [],
      dexcomDisplayKey = Uint8List(0),
      omnipodOperator = Uint8List(0);

  /// Parses the `vendor_keys.json` layout (`vendor_keys.example.json`).
  factory VendorKeys.fromJson(String source) {
    final root = json.decode(source) as Map<String, dynamic>;
    final dexcom = root['dexcom'] as Map<String, dynamic>? ?? const {};
    final omnipod = root['omnipod'] as Map<String, dynamic>? ?? const {};
    final certificates = dexcom['display_certificates'] as List? ?? const [];
    return VendorKeys(
      dexcomDisplayCertificates: [
        for (final certificate in certificates) _hex(certificate as String),
      ],
      dexcomDisplayKey: _hex(dexcom['display_private_key'] as String? ?? ''),
      omnipodOperator: _hex(omnipod['milenage_operator'] as String? ?? ''),
    );
  }

  static const String assetPath = 'assets/vendor_keys/vendor_keys.json';

  /// The keys of this isolate; empty until [ensureLoaded] has finished.
  static VendorKeys current = VendorKeys.empty();
  static Future<void>? _loading;

  final List<Uint8List> dexcomDisplayCertificates;
  final Uint8List dexcomDisplayKey;
  final Uint8List omnipodOperator;

  bool get hasDexcom =>
      dexcomDisplayCertificates.isNotEmpty && dexcomDisplayKey.length == 32;

  bool get hasOmnipod => omnipodOperator.length == 16;

  /// The devices that cannot pair with these keys, for the start-up warning.
  List<String> get missingDevices => [
    if (!hasDexcom) 'Dexcom G7',
    if (!hasOmnipod) 'Omnipod DASH',
  ];

  /// Loads [current] from the bundled asset once per isolate. A missing or
  /// malformed file leaves it empty rather than failing the caller: the warning
  /// and the per-device checks are what surface it.
  static Future<void> ensureLoaded() {
    return _loading ??= rootBundle
        .load(assetPath)
        .then((data) => current = VendorKeys.fromJson(_utf8(data)))
        .then<void>((_) {}, onError: (Object _) {});
  }
}
