// Embedded Dexcom display certificate chain, ported from Juggluco
// (DexGattCallback.certs). Sent during the 0x0B exchange to prove the reader is
// a legitimate display. cert[1] is the leaf whose private key the Rust core
// holds (DISPLAY_PRIV_KEY) and signs the 0x0C proof-of-possession with.
import 'dart:typed_data';

Uint8List _h(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

final List<Uint8List> kDisplayCerts = [
  _h(
    '***REMOVED***',
  ),
  _h(
    '***REMOVED***',
  ),
];
