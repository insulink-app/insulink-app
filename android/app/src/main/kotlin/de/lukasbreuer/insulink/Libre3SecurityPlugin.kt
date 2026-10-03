package de.insulink

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel bridge for the FreeStyle Libre 3 BLE security crypto.
 *
 * Mirrors Juggluco's `loadlibs.cpp`: a tiny native shim (`liblibre3bridge.so`)
 * `dlopen`s Abbott's proprietary `liblibre3extension.so` / `libcrl_dp.so` (both
 * in `jniLibs/arm64-v8a/`) and exposes their `process1`/`process2` symbols to
 * JNI. The Dart side ([Libre3NativeCrypto]) calls this channel; the ordered
 * handshake lives in Dart ([Libre3Transport]).
 *
 * The Abbott `.so` is NOT in this repo (see `docs/VENDOR_KEYS.md`). Absent them, [nativeLoaded] is
 * false and every call returns a `no_blob` error — so G7-only builds keep
 * working and the Libre 3 flow degrades cleanly.
 */
class Libre3SecurityPlugin {
    // The sensor's security generation, set by initKeys and used to pick the
    // embedded cert/key pair (KEYSCrypto's `securityVersion`).
    private var securityVersion = 0

    companion object {
        private const val CHANNEL = "insulink/libre3_security"

        private val nativeLoaded: Boolean = try {
            System.loadLibrary("libre3bridge")
            true
        } catch (t: Throwable) {
            false
        }

        // The two real Abbott primitives, bridged by liblibre3bridge.so
        // (process1/process2). Command numbers mirror Juggluco's
        // Natives.processint/processbar (see docs/LIBRE3.md). Only invoked when
        // nativeLoaded is true, so their absence never crashes the app.
        @JvmStatic external fun processInt(cmd: Int, a: ByteArray?, b: ByteArray?): Int
        @JvmStatic external fun processBar(cmd: Int, nonce: ByteArray?, data: ByteArray?): ByteArray?
    }

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "vendorKeysComplete") {
                    result.success(Libre3Keys.complete)
                    return@setMethodCallHandler
                }
                if (!nativeLoaded) {
                    result.error(
                        "no_blob",
                        "Libre 3 native crypto library (liblibre3bridge.so) not present",
                        null,
                    )
                    return@setMethodCallHandler
                }
                try {
                    handle(call.method, call, result)
                } catch (t: Throwable) {
                    result.error("libre3_error", t.message, null)
                }
            }
    }

    private fun handle(
        method: String,
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        when (method) {
            // KEYSCrypto.initKEYS: process1(1) to init, then process1(2) to load
            // the embedded (SKB-wrapped) private key with the cached kAuth `op`.
            "initKeys" -> {
                securityVersion = call.argument<Int>("securityVersion") ?: 0
                if (securityVersion >= Libre3Keys.appPrivateKeys.size) {
                    result.success(true)
                } else {
                    processInt(1, null, null)
                    processInt(2, Libre3Keys.appPrivateKeys[securityVersion],
                        call.argument("authKey"))
                    result.success(true)
                }
            }
            // getAppCertificate: the embedded cert for this security version.
            "appCertificate" ->
                result.success(Libre3Keys.appCertificates[securityVersion])
            // The rest map onto Abbott's process1/process2 (command numbers from
            // Juggluco's Libre3GattCallback; see docs/LIBRE3.md).
            "generateEphemeralKeys" -> result.success(processBar(5, null, null))
            "setPatchCertificate" ->
                result.success(processInt(4, call.argument<ByteArray>("cert")!!, null) >= 0)
            "setPatchEphemeral" ->
                result.success(processInt(6, call.argument("ephemeral"), null) >= 0)
            "encryptChallenge" ->
                result.success(processBar(7, call.argument("nonce"), call.argument("data")))
            "decryptChallenge" ->
                result.success(processBar(8, call.argument("nonce"), call.argument("data")))
            "exportAuthKey" -> result.success(processBar(9, null, null))
            // The AES-CCM data path (initCipher/decrypt) is clean-room in Dart.
            else -> result.notImplemented()
        }
    }
}
