import 'package:flutter/services.dart';

import 'libre3_ccm.dart';

/// The FreeStyle Libre 3 BLE security crypto, as a bridge interface.
///
/// Every operation here is performed by Abbott's proprietary native blobs
/// (`liblibre3extension.so` / `libcrl_dp.so`), because the app-certificate
/// signing key is protected by WhiteCryption Secure Key Box and cannot be used
/// in the open — this was proven from Juggluco's own `loadlibs.cpp`, which
/// `dlopen`s those libraries and delegates to their `process1`/`process2`
/// symbols. See docs/LIBRE3.md.
///
/// The handshake itself (the ordered GATT exchange in [Libre3Transport]) is
/// clean-room; only these crypto primitives are routed through the blob. The
/// method names mirror Juggluco's `Natives.processint`/`processbar`/`intDecrypt`
/// so the native shim maps 1:1.
abstract class Libre3Crypto {
  /// `initKEYS(authKey, version)` — prime the crypto with a cached kAuth (or
  /// null on a first pairing). Returns false if the blob is unavailable.
  Future<bool> initKeys(Uint8List? authKey, int securityVersion);

  /// `getAppCertificate()` — the 162-byte app certificate to send the sensor.
  Future<Uint8List> appCertificate();

  /// `processbar(5, …)` — our ephemeral P-256 public key, already framed as
  /// `[0x04 ‖ ephemeralPublicKey(65)]` for the CERT_DATA write.
  Future<Uint8List> generateEphemeralKeys();

  /// `setPatchCertificate(cert)` — accept the sensor's 140-byte patch cert.
  Future<void> setPatchCertificate(Uint8List cert140);

  /// `processint(6, patchEphemeral, null)` — feed the sensor's 65-byte ephemeral
  /// public key; the blob computes the shared secret. Returns success.
  Future<bool> setPatchEphemeral(Uint8List ephemeral65);

  /// `processbar(7, nonce, r1‖r2‖pin)` — encrypt the challenge response.
  Future<Uint8List> encryptChallenge(Uint8List nonce7, Uint8List r1r2pin);

  /// `processbar(8, nonce, first60)` — decrypt the sensor's reply to
  /// `[r2 ‖ r1 ‖ kEnc(16) ‖ ivEnc(8)]`; the caller validates r1/r2 and keeps
  /// kEnc/ivEnc.
  Future<Uint8List> decryptChallenge(Uint8List nonce7, Uint8List first60);

  /// `processbar(9, …)` — the 16-byte kAuth to cache for the next (fast)
  /// reconnect.
  Future<Uint8List> exportAuthKey();

  /// `initcrypt(kEnc, ivEnc)` — set up the AES-128-CCM data cipher context.
  Future<void> initCipher(Uint8List kEnc, Uint8List ivEnc);

  /// `intDecrypt(channelId, data)` — decrypt one data-characteristic payload
  /// (3 = glucose, 4 = historic, 2 = patch status, …).
  Future<Uint8List> decrypt(int channelId, Uint8List data);
}

/// [Libre3Crypto] backed by the native blob via a `MethodChannel`. The Android
/// side (`Libre3SecurityPlugin`, Kotlin) mirrors Juggluco's `loadlibs.cpp`:
/// it `dlopen`s the Abbott `.so` from `jniLibs/arm64-v8a/` and forwards each
/// call to `process1`/`process2`. The `.so` binaries are NOT in this repo and
/// must be supplied by the developer (see `android/app/src/main/jniLibs/README`).
class Libre3NativeCrypto implements Libre3Crypto {
  static const _channel = MethodChannel('insulink/libre3_security');

  /// Session key + IV from the handshake, kept for the clean-room AES-CCM data
  /// path (Juggluco's `initcrypt`/`intDecrypt` — NOT the blob).
  Uint8List? _kEnc;
  Uint8List? _ivEnc;

  @override
  Future<bool> initKeys(Uint8List? authKey, int securityVersion) async {
    final ok = await _channel.invokeMethod<bool>('initKeys', {
      'authKey': authKey,
      'securityVersion': securityVersion,
    });
    return ok ?? false;
  }

  /// The embedded app certificate for the current security version (served from
  /// the Kotlin side's `Libre3Keys`, ported from Juggluco's `KEYSCrypto.java`).
  @override
  Future<Uint8List> appCertificate() => _bytes('appCertificate');

  @override
  Future<Uint8List> generateEphemeralKeys() => _bytes('generateEphemeralKeys');

  @override
  Future<void> setPatchCertificate(Uint8List cert140) async {
    await _channel.invokeMethod<void>('setPatchCertificate', {'cert': cert140});
  }

  @override
  Future<bool> setPatchEphemeral(Uint8List ephemeral65) async {
    final ok = await _channel.invokeMethod<bool>('setPatchEphemeral', {
      'ephemeral': ephemeral65,
    });
    return ok ?? false;
  }

  @override
  Future<Uint8List> encryptChallenge(Uint8List nonce7, Uint8List r1r2pin) =>
      _bytes('encryptChallenge', {'nonce': nonce7, 'data': r1r2pin});

  @override
  Future<Uint8List> decryptChallenge(Uint8List nonce7, Uint8List first60) =>
      _bytes('decryptChallenge', {'nonce': nonce7, 'data': first60});

  @override
  Future<Uint8List> exportAuthKey() => _bytes('exportAuthKey');

  /// Clean-room: keep the session key/IV for the AES-CCM data path — no blob.
  @override
  Future<void> initCipher(Uint8List kEnc, Uint8List ivEnc) async {
    _kEnc = kEnc;
    _ivEnc = ivEnc;
  }

  /// Decrypt one data-characteristic payload with AES-128-CCM (see [Libre3Ccm]).
  ///
  /// ponytail: the CCM nonce (here `ivEnc`), MAC length (4 bytes) and whether the
  /// channel id / a per-frame sequence feed the nonce or AAD are the parts to
  /// confirm against a real sensor — the AES-CCM primitive itself is RFC-3610
  /// verified. Adjust the nonce/aad/macBits here once captured on-device.
  @override
  Future<Uint8List> decrypt(int channelId, Uint8List data) async {
    final key = _kEnc;
    final iv = _ivEnc;
    if (key == null || iv == null) {
      throw StateError('initCipher must run before decrypt');
    }
    return Libre3Ccm.decrypt(
      key: key,
      nonce: iv,
      ciphertextAndTag: data,
      macBits: 32,
    );
  }

  Future<Uint8List> _bytes(String method, [Map<String, Object?>? args]) async {
    final result = await _channel.invokeMethod<Uint8List>(method, args);
    if (result == null) {
      throw StateError('libre3_security.$method returned null (blob missing?)');
    }
    return result;
  }
}
