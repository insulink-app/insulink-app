package de.insulink

import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel bridge that saves the data backup through the system "save as"
 * dialog (Storage Access Framework), so the user picks where it lands: the
 * Downloads folder, a USB stick or a cloud drive. No storage permission needed,
 * and the file outlives an uninstall.
 *
 * Constructed as a property of [MainActivity], because the activity-result
 * launcher must be registered before the activity is started.
 */
class BackupExportPlugin(private val activity: FragmentActivity) {
    companion object {
        private const val CHANNEL = "insulink/backup_export"
    }

    private var pendingContent: String? = null
    private var pendingResult: MethodChannel.Result? = null

    private val createDocument = activity.registerForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri ->
        val result = pendingResult
        val content = pendingContent
        pendingResult = null
        pendingContent = null
        if (uri == null || content == null) {
            result?.success(false)
        } else {
            try {
                activity.contentResolver.openOutputStream(uri)!!.use { stream ->
                    stream.write(content.toByteArray(Charsets.UTF_8))
                }
                result?.success(true)
            } catch (error: Exception) {
                result?.error("write_failed", error.message, null)
            }
        }
    }

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "save" -> save(call.argument<String>("name")!!, call.argument<String>("content")!!, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun save(name: String, content: String, result: MethodChannel.Result) {
        pendingResult?.success(false)
        pendingContent = content
        pendingResult = result
        createDocument.launch(name)
    }
}
