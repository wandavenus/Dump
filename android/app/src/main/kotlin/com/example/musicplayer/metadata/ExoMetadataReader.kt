package com.example.musicplayer.metadata

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.container.MdtaMetadataEntry
import androidx.media3.exoplayer.MetadataRetriever
import androidx.media3.extractor.metadata.id3.TextInformationFrame
import androidx.media3.extractor.metadata.vorbis.VorbisComment
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
 *     Note: embedded MP3 USLT lyrics are NOT supported (not in library).
 *
 *   M4A — mdta atoms (androidx.media3:media3-container:1.10.1)
 *     • ©lyr (MdtaMetadataEntry, key = "\u00a9lyr") → lyrics (UTF-8)
 *
 * Architecture:
 *   MediaStore
 *       ↓
 *   Media3 MetadataRetriever  (@UnstableApi)
 *       ↓
 *   MetadataCacheDb  (SQLite, song_id + mtime key)
 *       ↓
 *   Flutter
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

    // ── Internal tag accumulator ──────────────────────────────────────────────

    private class TagBuilder {
        var rgTrackGain : String? = null
        var rgTrackPeak : String? = null
        var rgAlbumGain : String? = null
        var rgAlbumPeak : String? = null
        var r128Track   : String? = null
        var r128Album   : String? = null
        var iTunNorm    : String? = null
        var lyrics      : String? = null

        fun consume(entry: androidx.media3.common.Metadata.Entry) {
            when (entry) {

                // ── ID3v2 TXXX — MP3 / WAV (ReplayGain, R128, iTunNORM) ───────
                is TextInformationFrame -> {
                    if (!entry.id.equals("TXXX", ignoreCase = true)) return
                    val desc  = entry.description?.uppercase()?.trim() ?: return
                    val value = entry.values.firstOrNull()
                        ?.trim()?.takeIf { it.isNotBlank() } ?: return
                    when (desc) {
                        "REPLAYGAIN_TRACK_GAIN" -> if (rgTrackGain == null) rgTrackGain = value
                        "REPLAYGAIN_TRACK_PEAK" -> if (rgTrackPeak == null) rgTrackPeak = value
                        "REPLAYGAIN_ALBUM_GAIN" -> if (rgAlbumGain == null) rgAlbumGain = value
                        "REPLAYGAIN_ALBUM_PEAK" -> if (rgAlbumPeak == null) rgAlbumPeak = value
                        "R128_TRACK_GAIN",
                        "R128TRACKGAIN"         -> if (r128Track   == null) r128Track   = value
                        "R128_ALBUM_GAIN",
                        "R128ALBUMGAIN"         -> if (r128Album   == null) r128Album   = value
                        "ITUNNORM",
                        "ITUN NORM"             -> if (iTunNorm    == null) iTunNorm    = value
                    }
                }

                // ── Vorbis Comment — FLAC / OGG / OPUS ────────────────────────
                is VorbisComment -> {
                    val key   = entry.key.uppercase().trim()
                    val value = entry.value.trim().takeIf { it.isNotBlank() } ?: return
                    when (key) {
                        "REPLAYGAIN_TRACK_GAIN"  -> if (rgTrackGain == null) rgTrackGain = value
                        "REPLAYGAIN_TRACK_PEAK"  -> if (rgTrackPeak == null) rgTrackPeak = value
                        "REPLAYGAIN_ALBUM_GAIN"  -> if (rgAlbumGain == null) rgAlbumGain = value
                        "REPLAYGAIN_ALBUM_PEAK"  -> if (rgAlbumPeak == null) rgAlbumPeak = value
                        "R128_TRACK_GAIN"        -> if (r128Track   == null) r128Track   = value
                        "R128_ALBUM_GAIN"        -> if (r128Album   == null) r128Album   = value
                        "LYRICS",
                        "UNSYNCEDLYRICS",
                        "UNSYNCED LYRICS"        -> if (lyrics      == null) lyrics      = value
                    }
                }

                // ── MdtaMetadataEntry — M4A / QuickTime ©lyr atom ────────────
                //
                // Package: androidx.media3.container.MdtaMetadataEntry
                // Artifact: androidx.media3:media3-container:1.10.1
                // M4A lyrics are stored in the "©lyr" mdta key as UTF-8 bytes
                // (typeIndicator = TYPE_INDICATOR_STRING = 1).
                is MdtaMetadataEntry -> {
                    if (entry.key == "\u00a9lyr" && lyrics == null) {
                        lyrics = runCatching {
                            entry.value.toString(Charsets.UTF_8)
                                .trim().takeIf { it.isNotBlank() }
                        }.getOrNull()
                    }
                }

                else -> {}
            }
        }

        fun build() = AudioTags(
            rgTrackGain = rgTrackGain,
            rgTrackPeak = rgTrackPeak,
            rgAlbumGain = rgAlbumGain,
            rgAlbumPeak = rgAlbumPeak,
            r128Track   = r128Track,
            r128Album   = r128Album,
            iTunNorm    = iTunNorm,
            lyrics      = lyrics,
        )
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
