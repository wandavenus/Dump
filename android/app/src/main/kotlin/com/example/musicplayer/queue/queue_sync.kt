package com.example.musicplayer.queue

import android.content.Context
import androidx.media3.common.Player
import org.json.JSONArray
import org.json.JSONObject
import kotlin.concurrent.thread

class QueueSync(private val context: Context, private val log: (String) -> Unit) {
    data class Restored(val queue: List<Map<String, Any?>>, val index: Int, val positionMs: Long, val repeatMode: Int, val shuffle: Boolean)
    fun save(prefsName: String, keys: List<String>, queue: List<Map<String, Any?>>, index: Int, posMs: Long, repeatMode: Int, shuffle: Boolean) {
        if (queue.isEmpty()) return
        val snapshot = queue.map { HashMap(it) }
        thread {
            try {
                val arr = JSONArray()
                for (song in snapshot) {
                    val obj = JSONObject()
                    for ((k, v) in song) when (v) {
                        null -> obj.put(k, JSONObject.NULL)
                        is Number, is Boolean -> obj.put(k, v)
                        else -> obj.put(k, v.toString())
                    }
                    arr.put(obj)
                }
                context.getSharedPreferences(prefsName, Context.MODE_PRIVATE).edit()
                    .putString(keys[0], arr.toString())
                    .putInt(keys[1], index.coerceIn(0, (snapshot.size - 1).coerceAtLeast(0)))
                    .putLong(keys[2], posMs)
                    .putInt(keys[3], repeatMode)
                    .putBoolean(keys[4], shuffle)
                    .apply()
            } catch (e: Exception) { log("saveQueueToPrefs: ${e.message}") }
        }
    }
    fun restore(prefsName: String, keys: List<String>): Restored? = try {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val json = prefs.getString(keys[0], null) ?: return null
        val arr = JSONArray(json)
        val items = mutableListOf<Map<String, Any?>>()
        for (i in 0 until arr.length()) {
            val obj = arr.getJSONObject(i); val map = mutableMapOf<String, Any?>()
            for (key in obj.keys()) { val v = obj.get(key); map[key] = if (v == JSONObject.NULL) null else v }
            items.add(map)
        }
        if (items.isEmpty()) null else Restored(items, prefs.getInt(keys[1], 0), prefs.getLong(keys[2], 0L), prefs.getInt(keys[3], Player.REPEAT_MODE_OFF), prefs.getBoolean(keys[4], false))
    } catch (e: Exception) { log("restoreQueueFromPrefs: ${e.message}"); null }
}
