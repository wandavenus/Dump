package dev.wndavenz.music.data

import android.content.Context
import android.content.SharedPreferences
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import dev.wndavenz.music.models.Playlist
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.UUID

class PlaylistRepository(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("music_player_playlists", Context.MODE_PRIVATE)
    private val gson = Gson()

    private val _playlists = MutableStateFlow<List<Playlist>>(emptyList())
    val playlists: StateFlow<List<Playlist>> = _playlists.asStateFlow()

    init {
        loadPlaylists()
    }

    private fun loadPlaylists() {
        val raw = prefs.getString("playlists_json", null)
        if (!raw.isNullOrEmpty()) {
            try {
                val type = object : TypeToken<List<Playlist>>() {}.type
                val list: List<Playlist> = gson.fromJson(raw, type)
                _playlists.value = list
            } catch (e: Exception) {
                _playlists.value = emptyList()
            }
        }
    }

    private fun savePlaylists(list: List<Playlist>) {
        _playlists.value = list
        val raw = gson.toJson(list)
        prefs.edit().putString("playlists_json", raw).apply()
    }

    fun createPlaylist(name: String): Playlist {
        val newP = Playlist(
            id = UUID.randomUUID().toString(),
            name = name,
            songIds = emptyList(),
            createdAt = System.currentTimeMillis()
        )
        val updated = _playlists.value + newP
        savePlaylists(updated)
        return newP
    }

    fun deletePlaylist(id: String) {
        val updated = _playlists.value.filter { it.id != id }
        savePlaylists(updated)
    }

    fun addSongToPlaylist(playlistId: String, songId: Int) {
        val updated = _playlists.value.map { p ->
            if (p.id == playlistId) {
                if (!p.songIds.contains(songId)) {
                    p.copy(songIds = p.songIds + songId)
                } else p
            } else p
        }
        savePlaylists(updated)
    }

    fun removeSongFromPlaylist(playlistId: String, songId: Int) {
        val updated = _playlists.value.map { p ->
            if (p.id == playlistId) {
                p.copy(songIds = p.songIds.filter { it != songId })
            } else p
        }
        savePlaylists(updated)
    }

    fun renamePlaylist(playlistId: String, newName: String) {
        val updated = _playlists.value.map { p ->
            if (p.id == playlistId) p.copy(name = newName) else p
        }
        savePlaylists(updated)
    }
}
