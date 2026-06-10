package com.example.musicplayer

import android.Manifest
import android.content.ContentUris
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity
import java.io.ByteArrayOutputStream

class MainActivity : AudioServiceActivity() {

    private val channelName = "musicplayer/media_store"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSongs" -> result.success(getSongs())
                    "getArtwork" -> {
                        val albumId = call.argument<Number>("albumId")?.toLong() ?: 0L
                        val songId = call.argument<Number>("songId")?.toLong() ?: 0L
                        val path = call.argument<String>("path")

                        result.success(getArtwork(albumId, songId, path))
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

    private fun getArtwork(albumId: Long, songId: Long, path: String?): ByteArray? {
        if (!hasMediaPermission()) return null

        return getAlbumArtwork(albumId)
            ?: getAudioThumbnail(songId)
            ?: getEmbeddedArtwork(songId, path)
    }

    private fun getAlbumArtwork(albumId: Long): ByteArray? {
        if (albumId <= 0L) return null

        return try {
            val uri = ContentUris.withAppendedId(
                Uri.parse("content://media/external/audio/albumart"),
                albumId
            )

            contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (_: Exception) {
            null
        }
    }

    private fun getAudioThumbnail(songId: Long): ByteArray? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || songId <= 0L) return null

        return try {
            val uri = audioContentUri(songId)
            val bitmap = contentResolver.loadThumbnail(uri, Size(512, 512), null)

            bitmap.toPngByteArray()
        } catch (_: Exception) {
            null
        }
    }

    private fun getEmbeddedArtwork(songId: Long, path: String?): ByteArray? {
        if (songId > 0L) {
            val uri = audioContentUri(songId)

            getEmbeddedArtworkFromContentUri(uri)?.let { return it }
            getEmbeddedArtworkFromFileDescriptor(uri)?.let { return it }
        }

        if (!path.isNullOrBlank()) {
            getEmbeddedArtworkFromPath(path)?.let { return it }
        }

        return null
    }

    private fun getEmbeddedArtworkFromContentUri(uri: Uri): ByteArray? {
        return readEmbeddedArtwork { retriever ->
            retriever.setDataSource(this, uri)
        }
    }

    private fun getEmbeddedArtworkFromFileDescriptor(uri: Uri): ByteArray? {
        return try {
            contentResolver.openFileDescriptor(uri, "r")?.use { descriptor ->
                readEmbeddedArtwork { retriever ->
                    retriever.setDataSource(descriptor.fileDescriptor)
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun getEmbeddedArtworkFromPath(path: String): ByteArray? {
        return readEmbeddedArtwork { retriever ->
            retriever.setDataSource(path)
        }
    }

    private fun readEmbeddedArtwork(
        setDataSource: (MediaMetadataRetriever) -> Unit
    ): ByteArray? {
        val retriever = MediaMetadataRetriever()

        return try {
            setDataSource(retriever)
            retriever.embeddedPicture
        } catch (_: Exception) {
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
                // MediaMetadataRetriever.release can throw on some platform builds.
            }
        }
    }

    private fun audioContentUri(songId: Long): Uri {
        return ContentUris.withAppendedId(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            songId
        )
    }

    private fun Bitmap.toPngByteArray(): ByteArray {
        val stream = ByteArrayOutputStream()
        compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
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
                val songId = cursor.getLong(idCol)
                val albumId = cursor.getLong(albumIdCol)

                songs.add(
                    mapOf(
                        "id" to songId,
                        "title" to cursor.getString(titleCol),
                        "artist" to (cursor.getString(artistCol) ?: "Unknown Artist"),
                        "album" to (cursor.getString(albumCol) ?: "Unknown Album"),
                        "albumId" to albumId,
                        "artworkUri" to "content://media/external/audio/albumart/$albumId",
                        "contentUri" to audioContentUri(songId).toString(),
                        "path" to cursor.getString(pathCol),
                        "duration" to cursor.getLong(durationCol)
                    )
                )
            }
        }

        return songs
    }
}
