package de.insulink

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity (statt FlutterActivity) ist für den Health-Connect-
// Berechtigungs-Flow des `health`-Plugins erforderlich.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // FreeStyle Libre 3 crypto bridge to Abbott's native blobs. No-op (returns
        // "no_blob") unless the shim + .so are present, so G7-only builds are fine.
        Libre3SecurityPlugin().register(flutterEngine)
    }
}
