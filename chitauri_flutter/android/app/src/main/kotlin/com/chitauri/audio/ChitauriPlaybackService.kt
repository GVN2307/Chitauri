package com.chitauri.audio

import android.app.Notification
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.content.ContextCompat

class ChitauriPlaybackService : Service() {

    companion object {
        const val NOTIFICATION_ID = 1001
        private var lastNotification: Notification? = null

        fun startOrUpdate(context: Context, notification: Notification) {
            lastNotification = notification
            val intent = Intent(context, ChitauriPlaybackService::class.java).apply {
                action = "UPDATE_NOTIFICATION"
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ContextCompat.startForegroundService(context, intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Exception) {
                // If service start is restricted by background limits, notify via NotificationManager directly
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                nm?.notify(NOTIFICATION_ID, notification)
            }
        }

        fun stop(context: Context) {
            lastNotification = null
            val intent = Intent(context, ChitauriPlaybackService::class.java).apply {
                action = "STOP_SERVICE"
            }
            try {
                context.startService(intent)
            } catch (_: Exception) {}
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "STOP_SERVICE" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
            }
            else -> {
                lastNotification?.let { notif ->
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            startForeground(
                                NOTIFICATION_ID,
                                notif,
                                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                            )
                        } else {
                            startForeground(NOTIFICATION_ID, notif)
                        }
                    } catch (_: Exception) {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                        nm?.notify(NOTIFICATION_ID, notif)
                    }
                }
            }
        }
        return START_STICKY
    }
}
