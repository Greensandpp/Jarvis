package com.privateagent.private_agent

import android.app.Activity
import android.app.ActivityManager
import android.content.Intent
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Owner-selected, file-only model import. No downloader, inference server or network credential. */
class LocalBrainBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private val prefs = activity.getSharedPreferences("phone_local_brain", Activity.MODE_PRIVATE)
    private var pending: MethodChannel.Result? = null
    private val model get() = File(activity.filesDir, "local-brain/owner-model.gguf")
    companion object { const val PICK = 8751; const val MAX_BYTES = 3L * 1024 * 1024 * 1024 }
    init {
        MethodChannel(messenger, "greensoil/local_brain").setMethodCallHandler { call, result ->
            when (call.method) {
                "profile" -> result.success(profile())
                "modelInfo" -> result.success(info())
                "chooseModel" -> {
                    if (pending != null) result.error("BUSY", "A model picker is already open", null)
                    else {
                        pending = result
                        try { activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            type = "*/*"; addCategory(Intent.CATEGORY_OPENABLE)
                        }, PICK) } catch (_: Exception) { pending = null; result.error("PICKER", "Document picker unavailable", null) }
                    }
                }
                "deleteModel" -> io.execute {
                    val deleted = !model.exists() || model.delete()
                    if (deleted) prefs.edit().clear().commit()
                    main.post { if (deleted) result.success(null) else result.error("DELETE", "Could not remove local model", null) }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun info(): Map<String, Any>? {
        val sha = prefs.getString("sha256", null) ?: return null
        if (!model.isFile || model.length() != prefs.getLong("bytes", -1)) return null
        return mapOf("path" to model.absolutePath, "bytes" to model.length(), "sha256" to sha)
    }
    private fun profile(): Map<String, Any> {
        val memory = ActivityManager.MemoryInfo()
        (activity.getSystemService(Activity.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
        val battery = activity.registerReceiver(null, android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        return mapOf(
            "availableMemoryBytes" to memory.availMem, "totalMemoryBytes" to memory.totalMem,
            "lowMemory" to memory.lowMemory, "sdk" to Build.VERSION.SDK_INT,
            "batteryPercent" to (activity.getSystemService(Activity.BATTERY_SERVICE) as BatteryManager).getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY),
            "batteryTemperatureC" to ((battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -10) ?: -10) / 10.0),
            "thermalStatus" to (if (Build.VERSION.SDK_INT >= 29) (activity.getSystemService(Activity.POWER_SERVICE) as PowerManager).currentThermalStatus else -1),
            "freeStorageBytes" to activity.filesDir.usableSpace
        )
    }
    fun onActivityResult(request: Int, resultCode: Int, data: Intent?): Boolean {
        if (request != PICK) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri?.scheme != "content") { result.error("CANCELLED", "No model selected", null); return true }
        io.execute {
            val temp = File(activity.filesDir, "local-brain/import.partial")
            try {
                temp.parentFile!!.mkdirs()
                val digest = MessageDigest.getInstance("SHA-256")
                activity.contentResolver.openInputStream(uri)!!.use { input -> temp.outputStream().buffered().use { output ->
                    val buffer = ByteArray(1024 * 1024); var total = 0L
                    while (true) {
                        if (Thread.currentThread().isInterrupted) throw InterruptedException()
                        val n = input.read(buffer); if (n < 0) break
                        total += n; require(total <= MAX_BYTES && activity.filesDir.usableSpace > 64L * 1024 * 1024)
                        digest.update(buffer, 0, n); output.write(buffer, 0, n)
                    }
                } }
                require(temp.length() >= 1024 * 1024)
                temp.inputStream().use { input -> val magic = ByteArray(4); require(input.read(magic) == 4 && String(magic, Charsets.US_ASCII) == "GGUF") }
                val sha = digest.digest().joinToString("") { "%02x".format(it) }
                check(temp.renameTo(model))
                check(prefs.edit().putString("sha256", sha).putLong("bytes", model.length()).commit())
                main.post { result.success(info()) }
            } catch (_: Exception) {
                temp.delete(); main.post { result.error("IMPORT", "Choose a trusted GGUF file between 1 MB and 3 GB; check free storage", null) }
            }
        }
        return true
    }
    fun dispose() { io.shutdownNow(); pending?.error("CLOSED", "App closed", null); pending = null }
}
