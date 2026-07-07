package de.lukasbreuer.insulink

import android.app.Application
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskPlugin
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import io.flutter.embedding.engine.FlutterEngine

/**
 * Registers the Libre 3 security MethodChannel on the foreground-service isolate.
 *
 * The read pipeline — and therefore the Libre 3 BLE security handshake — runs in
 * the flutter_foreground_task background engine, NOT the UI engine that
 * [MainActivity] configures. Without registering `insulink/libre3_security`
 * there too, the handshake's `initKeys` call throws MissingPluginException. FFT
 * builds a fresh engine per task and fires [onEngineCreate] before the task
 * starts, so that is where we register the plugin. Doing it from
 * [Application.onCreate] means it also covers a system/sticky service restart,
 * when [MainActivity] never runs.
 */
class InsulinkApplication : Application() {
    private val libre3ServiceListener = object : FlutterForegroundTaskLifecycleListener {
        override fun onEngineCreate(flutterEngine: FlutterEngine?) {
            flutterEngine?.let { Libre3SecurityPlugin().register(it) }
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
