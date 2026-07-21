package de.insulink

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel bridge reporting whether any headphone-type output (wired,
 * Bluetooth, LE Audio, USB or hearing aid) is currently connected.
 *
 * The glucose alarm sound plays in the flutter_foreground_task background engine
 * (see [InsulinkApplication]), so — like [Libre3SecurityPlugin] — this must be
 * registered on BOTH the UI engine and the service engine, or the alarm's
 * routing check throws MissingPluginException with the app closed.
 */
class AudioOutputPlugin(private val context: Context) {
    companion object {
        private const val CHANNEL = "insulink/audio_output"
        private const val TAG = "InsulinkAudio"

        // Every personal-listening output type. LE Audio earbuds report
        // TYPE_BLE_HEADSET on Android 13+ (not TYPE_BLUETOOTH_A2DP), which is
        // why the original wired/A2DP-only list missed modern Bluetooth buds.
        private val HEADPHONE_TYPES = intArrayOf(
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_HEARING_AID,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_BROADCAST,
        )
    }

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "headphonesConnected" -> result.success(headphonesConnected())
                    else -> result.notImplemented()
                }
            }
    }

    private fun headphonesConnected(): Boolean {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val outputs = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        Log.i(TAG, "output device types: ${outputs.map { it.type }}")
        return outputs.any { device -> device.type in HEADPHONE_TYPES }
    }
}
