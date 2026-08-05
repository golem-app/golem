package app.golem.flutter

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.golem.flutter/storage"
        ).setMethodCallHandler { call, result ->
            val path = call.argument<String>("path")
            if (path == null) {
                result.error("bad-args", "Expected a path argument", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "freeBytes" -> try {
                    result.success(StatFs(path).availableBytes)
                } catch (error: Exception) {
                    result.error("free-bytes", error.message, null)
                }
                // Backup exclusion is static on Android: dataExtractionRules
                // already excludes the models directory.
                "excludeFromBackup" -> result.success(null)
                else -> result.notImplemented()
            }
        }
    }
}
