package de.insulink

import android.app.Application
import android.util.Log
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskPlugin
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import im.nfc.flutter_nfc_kit.FlutterNfcKitPlugin
import io.flutter.embedding.engine.FlutterEngine
import io.reactivex.exceptions.UndeliverableException
import io.reactivex.plugins.RxJavaPlugins

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
 *
 * flutter_nfc_kit is taken off that engine again: it keeps its channels in
 * statics, so the service engine shutting down can clear the handler of the UI
 * engine, and every later NFC scan throws MissingPluginException. The NFC scan
 * only ever runs on the UI engine.
 */
class InsulinkApplication : Application() {
    private val libre3ServiceListener = object : FlutterForegroundTaskLifecycleListener {
        override fun onEngineCreate(flutterEngine: FlutterEngine?) {
            flutterEngine?.let {
                it.plugins.remove(FlutterNfcKitPlugin::class.java)
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
        RxJavaPlugins.setErrorHandler(::onUndeliverable)
    }

    /**
     * The fitbit_air plugin's Golden Gate transport runs on RxJava 2 and
     * disposes its subscriptions when a band command ends; a timeout or
     * session error arriving after that has no subscriber left, and RxJava's
     * default sends it to the thread's uncaught handler, killing the app (and
     * the CGM service with it). Such errors are expected noise: drop them.
     * Anything else is a real bug and still crashes as before.
     */
    private fun onUndeliverable(error: Throwable) {
        if (error !is UndeliverableException) {
            Thread.currentThread().uncaughtExceptionHandler?.uncaughtException(Thread.currentThread(), error)
            return
        }
        Log.w("Insulink", "Dropped undeliverable RxJava error: ${error.cause}")
    }
}
