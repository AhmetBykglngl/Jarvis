package com.jarvis.jarvis

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Uygulama arka plandayken süreci ayakta tutar; böylece "Jarvis"
 * uyandırma motoru mikrofonu dinlemeye devam eder.
 */
class JarvisService : Service() {
    private var kilit: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val kanal = "jarvis_dinleme"
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(kanal, "Jarvis dinleme", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val bayrak = if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
        val ac = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            bayrak
        )
        val kurucu = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, kanal)
        else @Suppress("DEPRECATION") Notification.Builder(this)
        val bildirim = kurucu
            .setContentTitle("Jarvis dinliyor")
            .setContentText("\"Jarvis\" demen yeterli")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(ac)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(7, bildirim, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(7, bildirim)
        }

        if (kilit == null) {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            kilit = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "jarvis:dinleme").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        kilit?.let { if (it.isHeld) it.release() }
        kilit = null
        super.onDestroy()
    }
}
