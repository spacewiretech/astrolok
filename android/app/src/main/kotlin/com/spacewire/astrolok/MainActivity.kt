package com.spacewire.astrolok

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    /**
     * The channel every push from the backend names (`astrolok_default`, see `_shared/fcm.ts`).
     *
     * Created before the first push can arrive, so it carries the name and importance chosen here
     * rather than FCM's "Miscellaneous" fallback. High importance, because a kundali that is ready or a
     * reply to "why are you leaving" is worth a heads-up. Creating an existing channel is a no-op.
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "astrolok_default",
            "Readings & reminders",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Your Kundali, reading reminders and account alerts"
        }
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }
}
