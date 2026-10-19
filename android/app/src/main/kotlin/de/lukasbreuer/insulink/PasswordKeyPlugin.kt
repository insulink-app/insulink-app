package de.insulink

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/**
 * MethodChannel bridge that derives a 256-bit key from the account password
 * with PBKDF2-HMAC-SHA256 (see docs/POD_KEY_ENCRYPTION.md).
 *
 * Native because the platform's implementation is many times faster than one
 * in Dart: the iteration count that makes a stolen envelope expensive to guess
 * would otherwise freeze sign-in for many seconds. Runs off the main thread and
 * answers on it, as the channel requires.
 */
class PasswordKeyPlugin {
    companion object {
        private const val CHANNEL = "insulink/password_key"
        private const val KEY_BITS = 256
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "derive" -> derive(
                        call.argument<String>("password")!!,
                        call.argument<ByteArray>("salt")!!,
                        call.argument<Int>("iterations")!!,
                        result,
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private fun derive(
        password: String,
        salt: ByteArray,
        iterations: Int,
        result: MethodChannel.Result,
    ) {
        worker.execute {
            try {
                val spec = PBEKeySpec(password.toCharArray(), salt, iterations, KEY_BITS)
                val key = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
                    .generateSecret(spec).encoded
                spec.clearPassword()
                main.post { result.success(key) }
            } catch (error: Exception) {
                main.post { result.error("derive_failed", error.message, null) }
            }
        }
    }
}
