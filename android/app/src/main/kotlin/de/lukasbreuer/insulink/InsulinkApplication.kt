package de.insulink

import android.app.Application
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskPlugin
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import io.flutter.embedding.engine.FlutterEngine

/**
 * Registers the app's own MethodChannels on the foreground-service isolate.
 *
 * The read pipeline — and therefore the Libre 3 BLE security handshake, the
 * alarm's audio routing and the home-screen widget push — runs in the
 * flutter_foreground_task background engine, NOT the UI engine that
 * [MainActivity] configures. Without registering the channels there too, the
 * first call into one throws MissingPluginException. FFT
 * builds a fresh engine per task and fires [onEngineCreate] before the task
 * starts, so that is where we register the plugin. Doing it from
 * [Application.onCreate] means it also covers a system/sticky service restart,
 * when [MainActivity] never runs.
 */
class InsulinkApplication : Application() {
    private val libre3ServiceListener = object : FlutterForegroundTaskLifecycleListener {
        override fun onEngineCreate(flutterEngine: FlutterEngine?) {
            flutterEngine?.let {
                Libre3SecurityPlugin().register(it)
                AudioOutputPlugin(applicationContext).register(it)
                GlucoseWidgetPlugin(applicationContext).register(it)
            }
        }

        override fun onTaskStart(starter: FlutterForegroundTaskStarter) {}
        override fun onTaskRepeatEvent() {}
        override fun onTaskDestroy() {}
        override fun onEngineWillDestroy() {}
    }

    override fun onCreate() {
        super.onCreate()
        FlutterForegroundTaskPlugin.addTaskLifecycleListener(libre3ServiceListener)
    }
}
