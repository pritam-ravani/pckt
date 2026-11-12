package com.pckt.pckt

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject
import java.text.NumberFormat
import java.util.Locale

/**
 * Watches Google Pay, Paytm and PhonePe for completed payments. Notifications
 * from every other app are dropped on the first line, unread.
 */
class PaymentNotificationListener : NotificationListenerService() {
    private val recent = LinkedHashMap<String, Long>()

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val app = APPS[sbn.packageName] ?: return
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        if (!prefs.getBoolean(PREF_ENABLED, false)) return
        val n = sbn.notification ?: return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0 || sbn.isOngoing) return

        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()

        val result = PaymentNotificationParser.parse(title, text)
        val outcome = if (result is PaymentNotificationParser.Result.Ignored) result.reason else "payment"
        Log.i(TAG, "$app: $outcome: ${PaymentNotificationParser.shape(title, text)}")
        if (result !is PaymentNotificationParser.Result.Payment) return

        // Apps re-post the same notification when they update it.
        val key = "$app|${result.amountMinor}|${result.merchant}|${result.credit}"
        val now = System.currentTimeMillis()
        recent.entries.removeAll { now - it.value > DUPLICATE_WINDOW_MS }
        if (recent.containsKey(key)) return
        recent[key] = now

        val id = "$app:${sbn.postTime}:${result.amountMinor}"
        PaymentQueue.add(
            this,
            JSONObject()
                .put("id", id)
                .put("app", app)
                .put("title", title)
                .put("text", text)
                .put("postedAt", sbn.postTime)
                .put("amountMinor", result.amountMinor)
                .put("credit", result.credit)
                .put("merchant", result.merchant ?: JSONObject.NULL),
        )
        prompt(this, id, result, prefs.getString(PREF_HINTS, null))
    }

    companion object {
        private const val TAG = "pw-notif"
        private const val PREFS = "FlutterSharedPreferences"
        private const val PREF_ENABLED = "flutter.notif.capture"
        private const val PREF_HINTS = "flutter.notif.hints"
        private const val CHANNEL_ID = "payment_prompts"
        private const val DUPLICATE_WINDOW_MS = 120_000L

        const val EXTRA_ID = "com.pckt.pckt.PAYMENT_ID"
        const val EXTRA_CATEGORY = "com.pckt.pckt.PAYMENT_CATEGORY"
        const val EXTRA_NOTIFICATION = "com.pckt.pckt.PAYMENT_NOTIFICATION"

        val APPS = mapOf(
            "com.google.android.apps.nbu.paisa.user" to "Google Pay",
            "net.one97.paytm" to "Paytm",
            "com.phonepe.app" to "PhonePe",
        )

        private fun ensureChannel(context: Context) {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return
            if (nm.getNotificationChannel(CHANNEL_ID) != null) return
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Payment prompts", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Asks for a category right after you pay"
                }
            )
        }

        /** The learned category for [merchant], then the most used ones, at most two in all. */
        private fun suggestions(hints: String?, merchant: String?): Pair<String?, List<String>> {
            if (hints == null) return null to emptyList()
            return try {
                val json = JSONObject(hints)
                val guess = merchant?.let { json.getJSONObject("m").optString(it.lowercase(Locale.ROOT)).ifEmpty { null } }
                val top = json.getJSONArray("top")
                val others = (0 until top.length()).map { top.getString(it) }
                guess to (listOfNotNull(guess) + others).distinct().take(2)
            } catch (e: Exception) {
                null to emptyList()
            }
        }

        private fun rupees(minor: Long): String {
            val fmt = NumberFormat.getNumberInstance(Locale.forLanguageTag("en-IN")).apply {
                minimumFractionDigits = 0
                maximumFractionDigits = 2
            }
            return "₹" + fmt.format(minor / 100.0)
        }

        private fun prompt(context: Context, id: String, p: PaymentNotificationParser.Result.Payment, hints: String?) {
            if (Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) return
            ensureChannel(context)
            val notificationId = id.hashCode()
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val open = PendingIntent.getActivity(
                context,
                notificationId,
                Intent(context, MainActivity::class.java).apply {
                    this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra(MainActivity.EXTRA_OPEN_REVIEW, true)
                },
                flags,
            )
            val party = p.merchant?.let { if (p.credit) " from $it" else " to $it" }.orEmpty()
            val title = if (p.credit) "${rupees(p.amountMinor)} received$party" else "${rupees(p.amountMinor)}$party"
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_pckt)
                .setContentTitle(title)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(open)

            if (p.credit) {
                builder.setContentText("Saved. Tap to review")
            } else {
                val (guess, buttons) = suggestions(hints, p.merchant)
                builder.setContentText(if (guess != null) "$guess?" else "Which category?")
                buttons.forEachIndexed { i, category ->
                    val choose = PendingIntent.getBroadcast(
                        context,
                        notificationId + i + 1,
                        Intent(context, PaymentActionReceiver::class.java)
                            .putExtra(EXTRA_ID, id)
                            .putExtra(EXTRA_CATEGORY, category)
                            .putExtra(EXTRA_NOTIFICATION, notificationId),
                        flags,
                    )
                    builder.addAction(0, category, choose)
                }
                builder.addAction(0, "Change", open)
            }
            try {
                NotificationManagerCompat.from(context).notify(notificationId, builder.build())
            } catch (e: SecurityException) {
                // Permission revoked between the check and the post.
            }
        }
    }
}

/** A category button on a payment prompt: remembers the pick for the app to apply. */
class PaymentActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(PaymentNotificationListener.EXTRA_ID) ?: return
        val category = intent.getStringExtra(PaymentNotificationListener.EXTRA_CATEGORY) ?: return
        PaymentQueue.choose(context, id, category)
        NotificationManagerCompat.from(context)
            .cancel(intent.getIntExtra(PaymentNotificationListener.EXTRA_NOTIFICATION, 0))
    }
}
