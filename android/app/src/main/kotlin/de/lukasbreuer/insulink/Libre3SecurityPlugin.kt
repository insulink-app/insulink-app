package de.lukasbreuer.insulink

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
 * The Abbott `.so` and the `liblibre3bridge.so` shim are NOT in this repo (see
 * `android/app/src/main/jniLibs/README.md`). Absent them, [nativeLoaded] is
 * false and every call returns a `no_blob` error — so G7-only builds keep
 * working and the Libre 3 flow degrades cleanly.
 */
class Libre3SecurityPlugin {
    companion object {
        private const val CHANNEL = "insulink/libre3_security"

        private val nativeLoaded: Boolean = try {
            System.loadLibrary("libre3bridge")
            true
        } catch (t: Throwable) {
            false
        }

        // JNI surface of the native shim. Command numbers mirror Juggluco's
        // Natives.processint/processbar (see docs/LIBRE3.md). Only invoked when
        // nativeLoaded is true, so their absence never crashes the app.
        @JvmStatic external fun processInt(cmd: Int, a: ByteArray?, b: ByteArray?): Int
        @JvmStatic external fun processBar(cmd: Int, nonce: ByteArray?, data: ByteArray?): ByteArray?
        @JvmStatic external fun appCertificate(): ByteArray?
        @JvmStatic external fun setPatchCertificate(cert: ByteArray)
        @JvmStatic external fun initCipher(kEnc: ByteArray, ivEnc: ByteArray)
        @JvmStatic external fun decrypt(channelId: Int, data: ByteArray): ByteArray?
    }

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
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
            "initKeys" ->
                result.success(processInt(1, call.argument("authKey"), null) >= 0)
            "appCertificate" -> result.success(appCertificate())
            "generateEphemeralKeys" -> result.success(processBar(5, null, null))
            "setPatchCertificate" -> {
                setPatchCertificate(call.argument<ByteArray>("cert")!!)
                result.success(null)
            }
            "setPatchEphemeral" ->
                result.success(processInt(6, call.argument("ephemeral"), null) >= 0)
            "encryptChallenge" ->
                result.success(processBar(7, call.argument("nonce"), call.argument("data")))
            "decryptChallenge" ->
                result.success(processBar(8, call.argument("nonce"), call.argument("data")))
            "exportAuthKey" -> result.success(processBar(9, null, null))
            "initCipher" -> {
                initCipher(call.argument<ByteArray>("kEnc")!!, call.argument<ByteArray>("ivEnc")!!)
                result.success(null)
            }
            "decrypt" ->
                result.success(decrypt(call.argument<Int>("channelId")!!, call.argument<ByteArray>("data")!!))
            else -> result.notImplemented()
        }
    }
}
