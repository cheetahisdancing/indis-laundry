package com.indis.laundry

import android.Manifest
import android.annotation.SuppressLint
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
import androidx.core.content.ContextCompat
import java.util.concurrent.atomic.AtomicInteger

/**
 * 로컬 알림 담당 (iOS의 NotificationManager.swift와 같은 역할).
 * - showNow: 바로 알림
 * - schedule: 정해진 시각에 알림 (앱이 꺼져 있어도 AlarmManager가 깨워서 보냄)
 */
class Notifier(context: Context) {
    private val context = context.applicationContext

    init {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "세탁실 알림", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "세탁 종료, 빈 세탁기, 빨래 수거 요청 알림"
            }
            context.getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    fun hasPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    /** 바로 알림. notificationId가 같으면 이전 알림을 덮어씀 */
    @SuppressLint("MissingPermission")
    fun showNow(title: String, body: String, notificationId: Int = nextId.incrementAndGet()) {
        if (!hasPermission()) return
        val open = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_bell)
            .setColor(0xFF1D4ED8.toInt())
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(notificationId, notification)
        } catch (e: SecurityException) {
        }
    }

    /** 지정한 시각(epoch ms)에 알림 */
    fun schedule(key: String, title: String, body: String, atMillis: Long) {
        val alarm = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = alarmIntent(key, title, body)
        val exactAllowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarm.canScheduleExactAlarms()
        try {
            if (exactAllowed) {
                alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
            } else {
                alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
            }
        } catch (e: SecurityException) {
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
        }
    }

    /** 예약한 알림 취소 */
    fun cancel(key: String) {
        context.getSystemService(AlarmManager::class.java)?.cancel(alarmIntent(key, "", ""))
    }

    private fun alarmIntent(key: String, title: String, body: String): PendingIntent {
        val intent = Intent(context, NotificationReceiver::class.java)
            .setAction("com.indis.laundry.NOTIFY.$key")
            .putExtra(EXTRA_TITLE, title)
            .putExtra(EXTRA_BODY, body)
            .putExtra(EXTRA_ID, idFor(key))
        return PendingIntent.getBroadcast(
            context, idFor(key), intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    companion object {
        const val CHANNEL_ID = "laundry"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_ID = "id"
        private val nextId = AtomicInteger(1000)

        /** 기기마다 고정된 알림 번호 (같은 기기 알림은 하나만 보이게) */
        fun idFor(key: String): Int = key.hashCode() and 0x7FFFFFFF
    }
}

/** 예약 시각이 되면 AlarmManager가 호출 → 알림 표시 */
class NotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra(Notifier.EXTRA_TITLE) ?: return
        val body = intent.getStringExtra(Notifier.EXTRA_BODY) ?: ""
        Notifier(context).showNow(title, body, intent.getIntExtra(Notifier.EXTRA_ID, 1))
    }
}
