package com.pckt.pckt

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import java.util.Calendar

/** Picks the next alert time. No Android types, so it can be unit tested. */
object ReminderSchedule {
    /** [days] are ISO weekdays: 1 is Monday, 7 is Sunday. */
    data class Slot(val hour: Int, val minute: Int, val days: Set<Int>)

    fun next(slots: List<Slot>, now: Calendar): Long? {
        var best: Long? = null
        for (slot in slots) {
            for (offset in 0..7) {
                val at = (now.clone() as Calendar).apply {
                    add(Calendar.DAY_OF_YEAR, offset)
                    set(Calendar.HOUR_OF_DAY, slot.hour)
                    set(Calendar.MINUTE, slot.minute)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                val isoDay = (at.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
                if (isoDay !in slot.days || !at.after(now)) continue
                if (best == null || at.timeInMillis < best) best = at.timeInMillis
                break
            }
        }
        return best
    }
}

/**
 * Check-in alerts at the times set in Settings → Reminders. One alarm is kept
 * for the soonest time; when it fires, the next one is set. The text is
 * worked out at that moment so the count is current. Amounts are never shown.
 */
object Reminders {
    private const val PREFS = "FlutterSharedPreferences"
    private const val PREF_LIST = "flutter.reminders.v1"
    private const val PREF_ONLY_PENDING = "flutter.reminders.onlyPending"
    private const val PREF_REVIEW_COUNT = "flutter.reminders.reviewCount"
    private const val CHANNEL_ID = "check_in_reminders"
    private const val NOTIFICATION_ID = 4301

    const val ACTION_FIRE = "com.pckt.pckt.REMINDER_FIRE"

    private fun slots(context: Context): List<ReminderSchedule.Slot> = try {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(PREF_LIST, null) ?: "[]"
        val list = JSONArray(raw)
        (0 until list.length()).map { list.getJSONObject(it) }.filter { it.optBoolean("on", true) }.map { r ->
            val days = r.getJSONArray("days")
            ReminderSchedule.Slot(r.getInt("h"), r.getInt("m"), (0 until days.length()).map { days.getInt(it) }.toSet())
        }
    } catch (e: Exception) {
        emptyList()
    }

    private fun alarm(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        NOTIFICATION_ID,
        Intent(context, ReminderReceiver::class.java).setAction(ACTION_FIRE),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        return context.getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() ?: false
    }

    fun reschedule(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = alarm(context)
        val at = ReminderSchedule.next(slots(context), Calendar.getInstance())
        if (at == null) {
            manager.cancel(pending)
            return
        }
        try {
            if (canScheduleExact(context)) {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
            } else {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
            }
        } catch (e: SecurityException) {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        }
    }

    private fun waiting(context: Context): Int {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return try {
            prefs.getLong(PREF_REVIEW_COUNT, 0L).toInt()
        } catch (e: ClassCastException) {
            0
        } + PaymentQueue.waitingCount(context)
    }

    fun fire(context: Context) {
        val onlyPending = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(PREF_ONLY_PENDING, false)
        val count = waiting(context)
        if (!onlyPending || count > 0) show(context, count)
    }

    fun show(context: Context, count: Int = waiting(context)) {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        ensureChannel(context)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        fun open(request: Int, extra: String?) = PendingIntent.getActivity(
            context,
            request,
            Intent(context, MainActivity::class.java).apply {
                this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                if (extra != null) putExtra(extra, true)
            },
            flags,
        )
        val body = when (count) {
            0 -> "Anything to add? Cash or a payment that was missed"
            1 -> "1 payment needs your review"
            else -> "$count payments need your review"
        }
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_pckt)
            .setContentTitle("PennyWise check-in")
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(open(NOTIFICATION_ID + 1, if (count > 0) MainActivity.EXTRA_OPEN_REVIEW else null))
        if (count > 0) builder.addAction(0, "Review", open(NOTIFICATION_ID + 2, MainActivity.EXTRA_OPEN_REVIEW))
        builder.addAction(0, "Add transaction", open(NOTIFICATION_ID + 3, MainActivity.EXTRA_OPEN_ADD))
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, builder.build())
        } catch (e: SecurityException) {
            // Permission revoked between the check and the post.
        }
    }

    private fun ensureChannel(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Check-in reminders", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Your scheduled reminders to review or add transactions"
            }
        )
    }
}

/** Fires an alert, and restores the alarm after a restart, an update or a clock change. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Reminders.ACTION_FIRE -> Reminders.fire(context)
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED -> Unit
            else -> return
        }
        Reminders.reschedule(context)
    }
}
