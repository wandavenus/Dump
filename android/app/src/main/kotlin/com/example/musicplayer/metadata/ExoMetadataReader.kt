package com.example.musicplayer.metadata

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.MetadataRetriever
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Reads audio metadata tags using the Media3 [MetadataRetriever] API.
 *
 * Supported formats and tag types:
 *
 *   FLAC / OGG / OPUS — Vorbis Comments
 *     • LYRICS / UNSYNCEDLYRICS         → lyrics
 *     • REPLAYGAIN_TRACK_GAIN / _PEAK   → ReplayGain
 *     • REPLAYGAIN_ALBUM_GAIN / _PEAK   → ReplayGain album
 *     • R128_TRACK_GAIN / R128_ALBUM_GAIN → EBU R128
 *
 *   MP3 / WAV — ID3v2 TXXX frames
 *     • REPLAYGAIN_TRACK_GAIN / _PEAK   → ReplayGain
 *     • REPLAYGAIN_ALBUM_GAIN / _PEAK   → ReplayGain album
 *     • R128_TRACK_GAIN / R128_ALBUM_GAIN → EBU R128
 *     • ITUNNORM / ITUN NORM            → iTunes normalisation
 *
 *   M4A — mdta atoms (androidx.media3:media3-container:1.10.1)
 *     • ©lyr (MdtaMetadataEntry, key = "\u00a9lyr") → lyrics (UTF-8)
 *
 * Architecture:
 *   MediaStore → Media3 MetadataRetriever → MetadataCacheDb → Flutter
 *
 * Tag parsing logic lives in [TagBuilder] (internal, separately testable).
 *
 * MIUI note: [Uri.fromFile] is used so ExoPlayer reads directly from the
 * filesystem path instead of via the content resolver, avoiding MIUI's
 * occasional permission issues with content:// URIs on external storage.
 *
 * Must be called from a background thread — [read] blocks for up to
 * [TIMEOUT_SEC]. Never throws; returns empty [AudioTags] on any error.
 */
@OptIn(UnstableApi::class)
object ExoMetadataReader {

    private const val TAG         = "ExoMetadataReader"
    private const val TIMEOUT_SEC = 10L

    // ── Public result model ───────────────────────────────────────────────────

    /**
     * All nullable fields — null means the tag was not found in the file.
     * An empty [AudioTags] (all nulls) is returned on any read error.
     */
    data class AudioTags(
        val rgTrackGain : String? = null,
        val rgTrackPeak : String? = null,
        val rgAlbumGain : String? = null,
        val rgAlbumPeak : String? = null,
        val r128Track   : String? = null,
        val r128Album   : String? = null,
        val iTunNorm    : String? = null,
        val lyrics      : String? = null,
    ) {
        /** True if at least one loudness tag is present. */
        fun hasLoudness(): Boolean =
            rgTrackGain != null || r128Track != null || iTunNorm != null
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Reads all audio metadata for the file at [path] using Media3
     * [MetadataRetriever].
     *
     * @param context Application or activity context.
     * @param path    Absolute file path.
     * @return [AudioTags] with populated fields; all-null if nothing found or on error.
     */
    fun read(context: Context, path: String): AudioTags {
        if (path.isBlank()) return AudioTags()
        val file = File(path)
        if (!file.exists()) return AudioTags()

        return try {
            val future = MetadataRetriever.retrieveMetadata(
                context, MediaItem.fromUri(Uri.fromFile(file))
            )
            val trackGroups = future.get(TIMEOUT_SEC, TimeUnit.SECONDS)

            val builder = TagBuilder()
            for (i in 0 until trackGroups.length) {
                val group = trackGroups[i]
                for (j in 0 until group.length) {
                    val metadata = group.getFormat(j).metadata ?: continue
                    for (k in 0 until metadata.length()) {
                        runCatching { builder.consume(metadata[k]) }
                    }
                }
            }
            builder.build().also { tags ->
                Log.d(TAG, "Read ${file.name}: " +
                    "rg=${tags.rgTrackGain} r128=${tags.r128Track} " +
                    "lyrics=${tags.lyrics?.length?.let { "${it}ch" } ?: "none"}")
            }
        } catch (e: TimeoutException) {
            Log.w(TAG, "MetadataRetriever timed out for: $path")
            AudioTags()
        } catch (e: Exception) {
            Log.w(TAG, "MetadataRetriever failed for $path: ${e.message}")
            AudioTags()
        }
    }
}
