package app.golem

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.golem/storage"
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
            if (call.method == "isVirtualDevice") {
                result.success(isVirtualDevice())
                return@setMethodCallHandler
            }
            if (call.method == "availableMemoryBytes") {
                val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val info = ActivityManager.MemoryInfo()
                manager.getMemoryInfo(info)
                result.success(info.availMem)
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
                "totalBytes" -> try {
                    result.success(StatFs(path).totalBytes)
                } catch (error: Exception) {
                    result.error("total-bytes", error.message, null)
                }
                // Backup exclusion is static on Android: dataExtractionRules
                // already excludes the models directory.
                "excludeFromBackup" -> result.success(null)
                else -> result.notImplemented()
            }
        }
    }

    // Public Build fields only: ro.kernel.qemu and ro.build.characteristics
    // separate the two just as cleanly but are not API. Verified against the
    // Pixel emulator (hardware "ranchu", product "sdk_gphone16k_arm64") and
    // the OnePlus 12R (hardware "qcom", product "CPH2609EEA").
    //
    // Deliberately narrow. A false positive on a phone is a permanent refusal
    // of every download, with no override to correct it in production, so this
    // reads only names the emulators own: the two Android device models and
    // their Cuttlefish/GCE/VirtualBox siblings, and SDK-image product and model
    // names. Generic and unknown build fingerprints are excluded even though
    // emulators carry them — de-branded and AOSP-derived ROMs on real hardware
    // carry them too, and every emulator here is already named by hardware.
    private fun isVirtualDevice(): Boolean =
        Build.HARDWARE in VIRTUAL_HARDWARE ||
            VIRTUAL_PRODUCT_PREFIXES.any { Build.PRODUCT.startsWith(it) } ||
            Build.MODEL.startsWith("sdk_") ||
            Build.MODEL.contains("Emulator") ||
            Build.MODEL.contains("Android SDK built for")

    private companion object {
        // goldfish and ranchu are the Android emulator's two device models;
        // the rest are Cuttlefish, Google Compute Engine, and VirtualBox.
        val VIRTUAL_HARDWARE = setOf(
            "goldfish",
            "ranchu",
            "cutf_cvm",
            "cutf_cvm_arm64",
            "gce_x86",
            "gce_x86_64",
            "vbox86",
            "android_x86",
        )
        val VIRTUAL_PRODUCT_PREFIXES = listOf("sdk_gphone", "google_sdk", "vsoc", "vbox")
    }
}
