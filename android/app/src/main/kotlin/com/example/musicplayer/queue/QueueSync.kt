package com.example.musicplayer.queue

import android.content.Context
import android.os.Handler
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.example.musicplayer.events.NativeLogger
import org.json.JSONArray
import org.json.JSONObject
import kotlin.concurrent.thread

/**
 * Persists and restores queue state via SharedPreferences.
 *
 * Fixes:
 * - Background thread reads a full snapshot of queue taken on main thread (already done
 *   in original), but now uses the QueueManager reference for a consistent view.
 * - Separates the concern cleanly from QueueManager.
 */
@UnstableApi
class QueueSync(
    private val context: Context,
    private val handler: Handler,
    private val getQueue: () -> List<Map<String, Any?>>,
    private val getActiveQueueIndex: () -> Int,
    private val getPlayer: () -> ExoPlayer?,
    private val getCrossfadeDurationSec: () -> Float,
) {
    companion object {
        const val PREFS_NAME      = "media3_queue_prefs"
        const val KEY_QUEUE       = "queue_json"
        const val KEY_INDEX       = "queue_index"
        const val KEY_POS_MS      = "position_ms"
        const val KEY_REPEAT_MODE = "repeat_mode"
        const val KEY_SHUFFLE     = "shuffle_enabled"
    }

    fun save() {
        val queue = getQueue()
        if (queue.isEmpty()) return

        val p   = getPlayer()
        val idx = if (getCrossfadeDurationSec() > 0f)
            getActiveQueueIndex()
        else
            (p?.currentMediaItemIndex ?: getActiveQueueIndex())

        val posMs      = p?.currentPosition?.coerceAtLeast(0L) ?: 0L
        val repeatMode = p?.repeatMode ?: Player.REPEAT_MODE_OFF
        val shuffle    = p?.shuffleModeEnabled ?: false

        // Snapshot on main thread before handing off to background thread
        val queueSnapshot = queue.map { HashMap(it) }

        thread {
            try {
                val arr = JSONArray()
                for (song in queueSnapshot) {
                    val obj = JSONObject()
                    for ((k, v) in song) {
                        when (v) {
                            null      -> obj.put(k, JSONObject.NULL)
                            is Number -> obj.put(k, v)
                            is Boolean -> obj.put(k, v)
                            else      -> obj.put(k, v.toString())
                        }
                    }
                    arr.put(obj)
                }
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putString(KEY_QUEUE, arr.toString())
                    .putInt(KEY_INDEX, idx.coerceIn(0, (queueSnapshot.size - 1).coerceAtLeast(0)))
                    .putLong(KEY_POS_MS, posMs)
                    .putInt(KEY_REPEAT_MODE, repeatMode)
                    .putBoolean(KEY_SHUFFLE, shuffle)
                    .apply()
            } catch (e: Exception) {
                handler.post {
                    NativeLogger.emit("warn", "QueueSync", "save failed: ${e.message}")
                }
            }
        }
    }

    /**
     * Returns a [RestoreResult] on success, or null if there is nothing to restore.
     * Caller is responsible for applying the result to the player and QueueManager.
     */
    fun restore(): RestoreResult? {
        return try {
            val prefs      = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val json       = prefs.getString(KEY_QUEUE, null) ?: return null
            val savedIdx   = prefs.getInt(KEY_INDEX, 0)
            val savedPos   = prefs.getLong(KEY_POS_MS, 0L)
            val savedRepeat = prefs.getInt(KEY_REPEAT_MODE, Player.REPEAT_MODE_OFF)
            val savedShuffle = prefs.getBoolean(KEY_SHUFFLE, false)

            val arr   = JSONArray(json)
            val items = mutableListOf<Map<String, Any?>>()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val map = mutableMapOf<String, Any?>()
                for (key in obj.keys()) {
                    val v = obj.get(key)
                    map[key] = if (v == JSONObject.NULL) null else v
                }
                items.add(map)
            }
            if (items.isEmpty()) return null

            RestoreResult(
                items    = items,
                index    = savedIdx.coerceIn(0, (items.size - 1).coerceAtLeast(0)),
                posMs    = savedPos,
                repeat   = savedRepeat,
                shuffle  = savedShuffle,
            )
        } catch (e: Exception) {
            NativeLogger.emit("warn", "QueueSync", "restore failed: ${e.message}")
            null
        }
    }

    data class RestoreResult(
        val items:   List<Map<String, Any?>>,
        val index:   Int,
        val posMs:   Long,
        val repeat:  Int,
        val shuffle: Boolean,
    )
}
