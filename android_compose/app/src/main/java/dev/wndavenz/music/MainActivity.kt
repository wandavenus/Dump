package dev.wndavenz.music

import android.Manifest
import android.content.ContentUris
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.core.content.ContextCompat
import dev.wndavenz.music.data.PlaylistRepository
import dev.wndavenz.music.effects.NativeDspAudioProcessor
import dev.wndavenz.music.models.LocalSong
import dev.wndavenz.music.ui.navigation.BottomNavScreen
import dev.wndavenz.music.ui.theme.MusicPlayerTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {

    private lateinit var playlistRepository: PlaylistRepository

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        if (isGranted) {
            loadSongs()
        }
    }

    private val songsState = mutableStateListOf<LocalSong>()
    private var currentSongState = mutableStateOf<LocalSong?>(null)
    private var isPlayingState = mutableStateOf(false)
    private var positionMsState = mutableLongStateOf(0L)
    private var durationMsState = mutableLongStateOf(0L)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        playlistRepository = PlaylistRepository(this)

        // Ensure C/C++ Native Audio Engine is initialized
        if (NativeDspAudioProcessor.isLibraryAvailable) {
            android.util.Log.i("MainActivity", "Native audio C++ engine initialized successfully.")
        }

        checkAndRequestPermissions()

        setContent {
            MusicPlayerTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = Color.Black
                ) {
                    val playlists by playlistRepository.playlists.collectAsState()

                    BottomNavScreen(
                        songs = songsState,
                        playlists = playlists,
                        currentSong = currentSongState.value,
                        isPlaying = isPlayingState.value,
                        positionMs = positionMsState.longValue,
                        durationMs = durationMsState.longValue,
                        onSongSelect = { song ->
                            currentSongState.value = song
                            isPlayingState.value = true
                            durationMsState.longValue = song.durationMs
                            positionMsState.longValue = 0L
                        },
                        onPlayPause = {
                            isPlayingState.value = !isPlayingState.value
                        },
                        onNext = {
                            val current = currentSongState.value
                            if (current != null && songsState.isNotEmpty()) {
                                val idx = songsState.indexOf(current)
                                if (idx != -1 && idx < songsState.size - 1) {
                                    currentSongState.value = songsState[idx + 1]
                                    durationMsState.longValue = songsState[idx + 1].durationMs
                                    positionMsState.longValue = 0L
                                }
                            }
                        },
                        onPrevious = {
                            val current = currentSongState.value
                            if (current != null && songsState.isNotEmpty()) {
                                val idx = songsState.indexOf(current)
                                if (idx > 0) {
                                    currentSongState.value = songsState[idx - 1]
                                    durationMsState.longValue = songsState[idx - 1].durationMs
                                    positionMsState.longValue = 0L
                                }
                            }
                        },
                        onSeek = { pos -> positionMsState.longValue = pos },
                        onCreatePlaylist = { name -> playlistRepository.createPlaylist(name) }
                    )
                }
            }
        }
    }

    private fun checkAndRequestPermissions() {
        val perm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

        if (ContextCompat.checkSelfPermission(this, perm) == PackageManager.PERMISSION_GRANTED) {
            loadSongs()
        } else {
            permissionLauncher.launch(perm)
        }
    }

    private fun loadSongs() {
        kotlinx.coroutines.CoroutineScope(Dispatchers.IO).launch {
            val list = queryAudioFiles()
            withContext(Dispatchers.Main) {
                songsState.clear()
                songsState.addAll(list)
                if (list.isNotEmpty() && currentSongState.value == null) {
                    currentSongState.value = list.first()
                    durationMsState.longValue = list.first().durationMs
                }
            }
        }
    }

    private fun queryAudioFiles(): List<LocalSong> {
        val songs = mutableListOf<LocalSong>()
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.DURATION,
        )

        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            "${MediaStore.Audio.Media.TITLE} ASC"
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumIdCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val pathCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val durCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol).toInt()
                val title = cursor.getString(titleCol) ?: "Unknown Title"
                val artist = cursor.getString(artistCol) ?: "Unknown Artist"
                val album = cursor.getString(albumCol) ?: "Unknown Album"
                val albumId = cursor.getInt(albumIdCol)
                val path = cursor.getString(pathCol) ?: ""
                val duration = cursor.getLong(durCol)

                val artUri = ContentUris.withAppendedId(
                    android.net.Uri.parse("content://media/external/audio/albumart"),
                    albumId.toLong()
                ).toString()

                songs.add(
                    LocalSong(
                        id = id,
                        title = title,
                        artist = artist,
                        path = path,
                        album = album,
                        albumId = albumId,
                        artworkUri = artUri,
                        durationMs = duration
                    )
                )
            }
        }
        return songs
    }
}
