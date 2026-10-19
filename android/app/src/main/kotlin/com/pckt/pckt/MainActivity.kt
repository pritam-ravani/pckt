package com.pckt.pckt

import android.Manifest
import android.app.ActivityManager
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pckt/sms").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasSmsPermission())
                "requestPermission" -> {
                    if (hasSmsPermission()) {
                        result.success(true)
                    } else {
                        pendingPermission?.success(false)
                        pendingPermission = result
                        requestPermissions(arrayOf(Manifest.permission.READ_SMS), SMS_REQUEST)
                    }
                }
                "readInbox" -> {
                    val since = call.argument<Number>("sinceMillis")?.toLong() ?: 0L
                    val limit = call.argument<Int>("limit") ?: 5000
                    io.execute {
                        try {
                            val rows = readInbox(since, limit)
                            main.post { result.success(rows) }
                        } catch (e: SecurityException) {
                            main.post { result.error("PERMISSION", e.message, null) }
                        } catch (e: Exception) {
                            main.post { result.error("READ_FAILED", e.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pckt/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "profile" -> result.success(deviceProfile())
                // True on mobile data or a metered hotspot: big downloads ask first.
                "isMetered" -> {
                    val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                    result.success(cm.activeNetwork == null || cm.isActiveNetworkMetered)
                }
                // Android 13+: lets the model download show its progress notification.
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFY_REQUEST)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** What the on-device model picker needs to choose a model that fits. */
    private fun deviceProfile(): Map<String, Any?> {
        val am = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        val mem = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        val stat = StatFs(filesDir.absolutePath)
        val openCl = listOf(
            "/vendor/lib64/libOpenCL.so",
            "/system/vendor/lib64/libOpenCL.so",
            "/system/lib64/libOpenCL.so",
            // Mali drivers expose OpenCL through the GLES driver.
            "/vendor/lib64/egl/libGLES_mali.so",
        ).any { File(it).exists() }
        return mapOf(
            "totalRamBytes" to mem.totalMem,
            "availRamBytes" to mem.availMem,
            "lowRamDevice" to am.isLowRamDevice,
            "sdkInt" to Build.VERSION.SDK_INT,
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "hardware" to Build.HARDWARE,
            "board" to Build.BOARD,
            "socManufacturer" to if (Build.VERSION.SDK_INT >= 31) Build.SOC_MANUFACTURER else null,
            "socModel" to if (Build.VERSION.SDK_INT >= 31) Build.SOC_MODEL else null,
            "freeStorageBytes" to stat.availableBytes,
            "hasOpenCl" to openCl,
        )
    }

    private fun hasSmsPermission() =
        checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_REQUEST) {
            pendingPermission?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
    }

    /** Inbox messages newer than [since], oldest first. */
    private fun readInbox(since: Long, limit: Int): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms._ID, Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
            "${Telephony.Sms.DATE} > ?",
            arrayOf(since.toString()),
            "${Telephony.Sms.DATE} ASC",
        )?.use { c ->
            val id = c.getColumnIndexOrThrow(Telephony.Sms._ID)
            val addr = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val body = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val date = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
            while (c.moveToNext() && out.size < limit) {
                out.add(
                    mapOf(
                        "id" to c.getLong(id).toString(),
                        "address" to (c.getString(addr) ?: ""),
                        "body" to (c.getString(body) ?: ""),
                        "date" to c.getLong(date),
                    )
                )
            }
        }
        return out
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val SMS_REQUEST = 4201
        private const val NOTIFY_REQUEST = 4202
    }
}
