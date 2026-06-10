package com.example.musicplayer

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {

    private val channelName = "musicplayer/media_store"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSongs" -> result.success(getSongs())
                    "getArtwork" -> {
                        val songId = call.argument<Int>("songId")
                        result.success(getArtwork(songId ?: 0))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasMediaPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_MEDIA_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.READ_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun getArtwork(songId: Int): ByteArray? {
        return try {
            val uri = Uri.withAppendedPath(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                songId.toString()
            )

            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(this, uri)
            val artwork = retriever.embeddedPicture
            retriever.release()

            artwork
        } catch (_: Exception) {
            null
        }
    }

    private fun getSongs(): List<Map<String, Any?>> {
        if (!hasMediaPermission()) {
            return emptyList()
        }

        val songs = mutableListOf<Map<String, Any?>>()

        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.DURATION
        )

        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            MediaStore.Audio.Media.IS_MUSIC + "!= 0",
            null,
            MediaStore.Audio.Media.TITLE + " ASC"
        )?.use { cursor ->

            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumIdCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val pathCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val durationCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)

            while (cursor.moveToNext()) {
                val albumId = cursor.getInt(albumIdCol)

                songs.add(
                    mapOf(
                        "id" to cursor.getLong(idCol).toInt(),
                        "title" to cursor.getString(titleCol),
                        "artist" to (cursor.getString(artistCol) ?: "Unknown Artist"),
                        "album" to (cursor.getString(albumCol) ?: "Unknown Album"),
                        "albumId" to albumId,
                        "artworkUri" to "content://media/external/audio/albumart/$albumId",
                        "path" to cursor.getString(pathCol),
                        "duration" to cursor.getLong(durationCol).toInt()
                    )
                )
            }
        }

        return songs
    }
}
