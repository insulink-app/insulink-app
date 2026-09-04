package de.insulink

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel bridge handing the latest reading to [GlucoseWidgetProvider].
 *
 * Readings arrive in the flutter_foreground_task background engine — the app is
 * usually closed when the widget matters most — so, like [AudioOutputPlugin],
 * this must be registered on BOTH the UI engine and the service engine, or the
 * push throws MissingPluginException with the app closed.
 */
class GlucoseWidgetPlugin(private val context: Context) {
    companion object {
        private const val CHANNEL = "insulink/glucose_widget"
    }

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "publish" -> {
                        publish(call)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Colour and timestamp are read as [Number], not as Int/Long: an opaque
     * ARGB exceeds Int.MAX_VALUE, so the standard codec ships it as a Long and
     * asking for an Int would fail. Truncating that Long back to 32 bits is the
     * original ARGB.
     */
    private fun publish(call: MethodCall) {
        GlucoseWidgetProvider.publish(
            context,
            call.argument<String>("value") ?: "",
            call.argument<String>("unit") ?: "",
            call.argument<String>("arrow") ?: "",
            call.argument<Number>("color")?.toInt() ?: 0,
            call.argument<Number>("time")?.toLong() ?: 0L,
        )
    }
}
