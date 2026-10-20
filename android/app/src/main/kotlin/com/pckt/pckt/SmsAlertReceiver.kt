package com.pckt.pckt

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Telephony
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.text.NumberFormat
import java.util.Locale

/**
 * Posts "₹250 debited · HDFC — tap to review" as soon as a bank SMS arrives.
 *
 * Detection here is deliberately small and conservative: a DLT bank-style
 * sender, a completed debit/credit verb and an amount. It never writes any
 * data — tapping the notification opens the app, whose resume sync runs the
 * real Dart pipeline (parse → dedup → store).
 */
class SmsAlertReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (!alertsEnabled(context)) return
        val parts = try {
            Telephony.Sms.Intents.getMessagesFromIntent(intent)
        } catch (e: Exception) {
            return
        } ?: return
        // Multipart messages arrive as several PDUs from one sender.
        parts.filterNotNull()
            .groupBy { it.displayOriginatingAddress ?: it.originatingAddress ?: "" }
            .forEach { (sender, msgs) ->
                val body = msgs.joinToString("") { it.displayMessageBody ?: it.messageBody ?: "" }
                val alert = detect(sender, body) ?: return@forEach
                notify(context, alert, (sender + body).hashCode())
            }
    }

    data class Alert(val amount: String, val debit: Boolean, val bank: String)

    companion object {
        const val CHANNEL_ID = "txn_alerts"

        /** Flutter's shared_preferences (legacy API) file; keys get a "flutter." prefix. */
        private const val PREFS = "FlutterSharedPreferences"
        private const val PREF_ALERTS = "flutter.sms.alerts"
        private const val PREF_SMS = "flutter.sms.enabled"

        // VM-HDFCBK, AD-ICICIT-S, JD-SBIUPI-T … but not promotional (-P).
        private val dlt = Regex("^[A-Z]{2}-([A-Z0-9]{3,9})(?:-[STG])?$")
        private val amount = Regex("(?:rs\\.?|inr|₹)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)")
        private val debit = Regex("\\b(debited|spent|withdrawn|sent|paid|deducted|purchase)\\b")
        private val credit = Regex("\\b(credited|received|deposited|refunded)\\b")
        private val skip = Regex(
            "\\b(otp|one[- ]time password|verification code)\\b|will be (auto[- ]?)?debited|to be debited|" +
                "\\b(due|reminder|failed|declined|unsuccessful|requested|request)\\b|statement|" +
                "\\b(offer|cashback up ?to|pre-?approved|apply now)\\b"
        )

        private val banks = linkedMapOf(
            "HDFC" to "HDFC", "ICICI" to "ICICI", "SBICRD" to "SBI Card", "SBI" to "SBI", "AXIS" to "Axis",
            "KOTAK" to "Kotak", "KMBL" to "Kotak", "IDFC" to "IDFC First", "YESB" to "Yes Bank",
            "INDUS" to "IndusInd", "PNB" to "PNB", "BOB" to "Bank of Baroda", "BARODA" to "Bank of Baroda",
            "CANBNK" to "Canara", "UNION" to "Union Bank", "UBOI" to "Union Bank", "FED" to "Federal",
            "AUBANK" to "AU Bank", "RBL" to "RBL", "IDBI" to "IDBI", "CITI" to "Citi", "HSBC" to "HSBC",
            "AMEX" to "Amex", "SCB" to "StanChart", "PAYTM" to "Paytm", "PYTM" to "Paytm",
            "AIRBNK" to "Airtel Payments", "JUPITR" to "Jupiter", "ONECRD" to "OneCard", "SLICE" to "slice",
            "IMEIND" to "IME India",
        )

        private fun alertsEnabled(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return prefs.getBoolean(PREF_SMS, false) && prefs.getBoolean(PREF_ALERTS, true)
        }

        /** Null unless this looks like a completed transaction from a known bank. */
        fun detect(sender: String, body: String): Alert? {
            val header = dlt.find(sender.trim().uppercase(Locale.ROOT))?.groupValues?.get(1) ?: return null
            val bank = banks.entries.firstOrNull { header.contains(it.key) }?.value ?: return null
            val lower = body.lowercase(Locale.ROOT)
            if (skip.containsMatchIn(lower)) return null
            val d = debit.find(lower)
            val c = credit.find(lower)
            if (d == null && c == null) return null
            val isDebit = when {
                Regex("\\b(refund(ed)?|reversed|reversal)\\b").containsMatchIn(lower) -> false
                c == null -> true
                d == null -> false
                else -> d.range.first <= c.range.first
            }
            // First amount that isn't a balance/limit figure.
            val value = amount.findAll(lower).firstOrNull { m ->
                val before = lower.substring(maxOf(0, m.range.first - 24), m.range.first)
                !Regex("(bal(ance)?|limit|avl|available)[\\s:.\\-]*(is\\s*)?$").containsMatchIn(before)
            }?.groupValues?.get(1)?.replace(",", "")?.toDoubleOrNull() ?: return null
            if (value <= 0) return null
            val fmt = NumberFormat.getNumberInstance(Locale.forLanguageTag("en-IN")).apply {
                minimumFractionDigits = 0
                maximumFractionDigits = 2
            }
            return Alert("₹" + fmt.format(value), isDebit, bank)
        }

        fun ensureChannel(context: Context) {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return
            if (nm.getNotificationChannel(CHANNEL_ID) != null) return
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Transaction alerts", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "A heads-up when a bank SMS shows money moving"
                }
            )
        }

        private fun notify(context: Context, alert: Alert, id: Int) {
            if (Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) return
            ensureChannel(context)
            val open = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(MainActivity.EXTRA_FROM_ALERT, true)
            }
            val pi = PendingIntent.getActivity(
                context, id, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val verb = if (alert.debit) "debited" else "credited"
            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_pckt)
                .setContentTitle("${alert.amount} $verb · ${alert.bank}")
                .setContentText("Tap to review")
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build()
            try {
                NotificationManagerCompat.from(context).notify(id, notification)
            } catch (e: SecurityException) {
                // Permission revoked between the check and the post.
            }
        }
    }
}
