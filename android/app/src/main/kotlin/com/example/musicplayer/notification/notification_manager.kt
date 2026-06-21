package com.example.musicplayer.notification

import android.app.Notification

/**
 * Extension seam for Media3 playback notifications.
 *
 * The service still owns notification rendering in this compatibility pass so
 * existing foreground-service behavior remains unchanged. This facade reserves
 * the requested module boundary for follow-up extraction without changing the
 * notification API surface.
 */
class NotificationManagerFacade {
    fun dispatch(update: NotificationUpdate, notify: (Int, Notification) -> Unit) {
        notify(update.id, update.notification)
    }
}

data class NotificationUpdate(
    val id: Int,
    val notification: Notification,
)
