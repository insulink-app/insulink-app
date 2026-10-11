package de.insulink

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity (instead of FlutterActivity) is required by the
// Health Connect permission flow of the `health` plugin.
class MainActivity : FlutterFragmentActivity() {
    private val backupExport = BackupExportPlugin(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // FreeStyle Libre 3 crypto bridge to Abbott's native blobs. No-op (returns
        // "no_blob") unless the shim + .so are present, so G7-only builds are fine.
        Libre3SecurityPlugin().register(flutterEngine)
        // Headphone-detection for alarm routing (see AudioOutputPlugin).
        AudioOutputPlugin(applicationContext).register(flutterEngine)
        // Pushes each reading to the home-screen widget (see GlucoseWidgetPlugin).
        GlucoseWidgetPlugin(applicationContext).register(flutterEngine)
        // Saves the data backup via the system "save as" dialog.
        backupExport.register(flutterEngine)
    }
}
