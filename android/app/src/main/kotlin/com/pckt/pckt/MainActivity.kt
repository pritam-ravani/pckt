package com.pckt.pckt

import android.Manifest
import android.app.ActivityManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.Telephony
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

// FlutterFragmentActivity (not FlutterActivity): local_auth's biometric
// prompt needs a FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPermission: MethodChannel.Result? = null

    /** Text shared to Pckt / pckt://ingest links not yet taken by Dart. */
    private val pendingShares = ArrayList<Map<String, Any?>>()
    private var shareChannel: MethodChannel? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Apply "Hide in recent apps" before the first frame, so even the
        // cold-start snapshot is protected. Dart keeps it in shared_preferences
        // (legacy store: FlutterSharedPreferences, keys prefixed "flutter.").
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        setSecure(prefs.getBoolean("flutter.$HIDE_IN_RECENTS_PREF", false))
    }

    private fun setSecure(secure: Boolean) {
        if (secure) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pckt/security").setMethodCallHandler { call, result ->
            when (call.method) {
                // FLAG_SECURE: blank thumbnail in Recents, no screenshots.
                "setSecure" -> {
                    setSecure(call.argument<Boolean>("secure") == true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pckt/sms").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasSmsPermission())
                // RECEIVE_SMS powers real-time alerts; it is in the same group as
                // READ_SMS, so once that is granted it's granted without a dialog.
                "hasReceivePermission" -> result.success(hasReceivePermission())
                "requestPermission" -> {
                    if (hasSmsPermission() && hasReceivePermission()) {
                        result.success(true)
                    } else {
                        pendingPermission?.success(false)
                        pendingPermission = result
                        requestPermissions(
                            arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS),
                            SMS_REQUEST,
                        )
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
                // Background on-device AI runs more often while charging.
                "isCharging" -> {
                    val bm = getSystemService(BATTERY_SERVICE) as BatteryManager
                    result.success(bm.isCharging)
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
                "notificationsAllowed" -> result.success(
                    Build.VERSION.SDK_INT < 33 ||
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
                )
                else -> result.notImplemented()
            }
        }
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pckt/share").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePending" -> {
                        result.success(ArrayList(pendingShares))
                        pendingShares.clear()
                    }
                    else -> result.notImplemented()
                }
            }
        }
        captureShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (captureShare(intent)) shareChannel?.invokeMethod("pending", null)
    }

    /**
     * ACTION_SEND text/plain (share sheet) or pckt://ingest?text=…&sender=…
     * (deep link). Queued until Dart asks; returns true if one was captured.
     */
    private fun captureShare(intent: Intent?): Boolean {
        if (intent == null || intent.getBooleanExtra(EXTRA_HANDLED, false)) return false
        val share = when {
            intent.action == Intent.ACTION_SEND && intent.type?.startsWith("text/") == true -> {
                val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                text?.let { mapOf("text" to it, "sender" to null, "via" to "share") }
            }
            intent.action == Intent.ACTION_VIEW && intent.data?.scheme == "pckt" && intent.data?.host == "ingest" -> {
                val data = intent.data!!
                data.getQueryParameter("text")?.let {
                    mapOf("text" to it, "sender" to data.getQueryParameter("sender"), "via" to "link")
                }
            }
            else -> null
        } ?: return false
        if ((share["text"] as String).isBlank()) return false
        // Don't re-ingest the same intent after a configuration change / recreate.
        intent.putExtra(EXTRA_HANDLED, true)
        pendingShares.add(share)
        return true
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

    private fun hasReceivePermission() =
        checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_REQUEST) {
            // Success means inbox access; RECEIVE_SMS only adds live alerts.
            pendingPermission?.success(hasSmsPermission())
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
        const val EXTRA_FROM_ALERT = "com.pckt.pckt.FROM_ALERT"
        private const val EXTRA_HANDLED = "com.pckt.pckt.SHARE_HANDLED"
        // Must match SecurityPrefKeys.hideInRecents on the Dart side.
        private const val HIDE_IN_RECENTS_PREF = "security.hideInRecents"
    }
}
