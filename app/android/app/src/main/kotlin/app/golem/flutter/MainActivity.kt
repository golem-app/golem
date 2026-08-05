package app.golem.flutter

import android.app.ActivityManager
import android.content.Context
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
            if (call.method == "physicalMemoryBytes") {
                // totalMem reports net of kernel/firmware reservations, so a
                // nominal 8 GB device reads ~7.5 GB — the policy threshold
                // accounts for that.
                val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val info = ActivityManager.MemoryInfo()
                manager.getMemoryInfo(info)
                result.success(info.totalMem)
                return@setMethodCallHandler
            }
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
