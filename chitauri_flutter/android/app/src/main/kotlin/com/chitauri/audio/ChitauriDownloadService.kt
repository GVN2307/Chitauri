package com.chitauri.audio

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class ChitauriDownloadService : Service() {

    companion object {
        const val DOWNLOAD_NOTIFICATION_ID = 2002
        const val CHANNEL_ID = "chitauri_download_channel"
        private var wakeLock: PowerManager.WakeLock? = null
        private val activeDownloadsCount = java.util.concurrent.atomic.AtomicInteger(0)

        fun notifyDownloadStarted(context: Context, songTitle: String) {
            activeDownloadsCount.incrementAndGet()
            startOrUpdate(context, songTitle, 5)
        }

        fun notifyDownloadProgress(context: Context, songTitle: String, progressPct: Int) {
            startOrUpdate(context, songTitle, progressPct)
        }

        fun notifyDownloadEnded(context: Context) {
            val remaining = activeDownloadsCount.decrementAndGet()
            if (remaining <= 0) {
                activeDownloadsCount.set(0)
                stop(context)
            }
        }

        fun startOrUpdate(context: Context, songTitle: String, progressPct: Int) {
            val intent = Intent(context, ChitauriDownloadService::class.java).apply {
                action = "UPDATE_DOWNLOAD"
                putExtra("title", songTitle)
                putExtra("progress", progressPct)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ContextCompat.startForegroundService(context, intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Exception) {}
        }

        fun stop(context: Context) {
            val intent = Intent(context, ChitauriDownloadService::class.java).apply {
                action = "STOP_SERVICE"
            }
            try {
                context.startService(intent)
            } catch (_: Exception) {}
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Chitauri:BackgroundDownloadWakeLock")
            wakeLock?.acquire(30 * 60 * 1000L) // 30 minutes max safety limit
        } catch (_: Exception) {}
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Chitauri Active Downloads",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows live download progress while downloading in background"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "STOP_SERVICE" -> {
                try {
                    if (wakeLock?.isHeld == true) {
                        wakeLock?.release()
                    }
                } catch (_: Exception) {}
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
            }
            else -> {
                val title = intent?.getStringExtra("title") ?: "Downloading Audio"
                val progress = intent?.getIntExtra("progress", 0) ?: 0

                val openAppIntent = Intent(this, MainActivity::class.java).apply {
                    this.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
                val pi = PendingIntent.getActivity(
                    this, 0, openAppIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                val builder = NotificationCompat.Builder(this, CHANNEL_ID)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle("Downloading: $title")
                    .setContentText("$progress% completed • Background download active")
                    .setContentIntent(pi)
                    .setProgress(100, progress, progress <= 0)
                    .setOngoing(true)
                    .setOnlyAlertOnce(true)

                val notif = builder.build()

                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        startForeground(
                            DOWNLOAD_NOTIFICATION_ID,
                            notif,
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                        )
                    } else {
                        startForeground(DOWNLOAD_NOTIFICATION_ID, notif)
                    }
                } catch (_: Exception) {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                    nm?.notify(DOWNLOAD_NOTIFICATION_ID, notif)
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
