package com.example.musicplayer.metadata

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.MetadataRetriever
import androidx.media3.extractor.metadata.id3.TextInformationFrame
import androidx.media3.extractor.metadata.id3.UnsynchronizedLyricsFrame
import androidx.media3.extractor.metadata.mp4.MdtaMetadataEntry
import androidx.media3.extractor.metadata.vorbis.VorbisComment
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Reads audio metadata tags using ExoPlayer's [MetadataRetriever].
 *
 * Replaces jaudiotagger for:
 *  - ReplayGain / R128 / iTunNORM tag reading (all standard audio formats)
 *  - Embedded lyrics (USLT for MP3, Vorbis LYRICS for FLAC/OGG/OPUS, ©lyr for M4A)
 *
 * Must be called from a background thread — [read] blocks for up to [TIMEOUT_SEC].
 * Never throws; returns empty [AudioTags] on any error.
 *
 * Supported formats (via ExoPlayer container demuxers):
 *  MP3   → ID3v2 TXXX frames for RG; USLT frames for lyrics
 *  FLAC  → Vorbis comments for RG + lyrics
 *  OGG   → Vorbis comments for RG + lyrics
 *  OPUS  → Vorbis comments for RG + lyrics
 *  M4A   → MdtaMetadataEntry atoms for RG + ©lyr for lyrics
 *  WAV   → ID3v2 TXXX (when ID3 chunk is present)
 *
 * MIUI note: [Uri.fromFile] is used so ExoPlayer reads directly from the
 * file system path rather than via a content resolver, which avoids MIUI's
 * occasional URI permission quirks for external storage files.
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

    // ── Internal builder ──────────────────────────────────────────────────────

    private class TagBuilder {
        var rgTrackGain  : String? = null
        var rgTrackPeak  : String? = null
        var rgAlbumGain  : String? = null
        var rgAlbumPeak  : String? = null
        var r128Track    : String? = null
        var r128Album    : String? = null
        var iTunNorm     : String? = null

        // Prefer blank-language or "eng" USLT; keep non-eng as fallback
        private var lyricsEng   : String? = null
        private var lyricsOther : String? = null
        val lyrics: String? get() = lyricsEng ?: lyricsOther

        fun consume(entry: androidx.media3.common.Metadata.Entry) {
            when (entry) {

                // ── ID3v2 TXXX — MP3 ReplayGain ───────────────────────────
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

                // ── ID3v2 USLT — MP3 embedded lyrics ──────────────────────
                is UnsynchronizedLyricsFrame -> {
                    val text = entry.lyrics?.trim()?.takeIf { it.isNotBlank() } ?: return
                    val lang = entry.language?.trim()?.lowercase() ?: ""
                    if (lang.isEmpty() || lang == "eng") {
                        if (lyricsEng == null) lyricsEng = text
                    } else {
                        if (lyricsOther == null) lyricsOther = text
                    }
                }

                // ── Vorbis Comment — FLAC / OGG / OPUS ────────────────────
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
                        "UNSYNCED LYRICS"        -> if (lyricsEng   == null) lyricsEng   = value
                    }
                }

                // ── MdtaMetadataEntry — M4A / MP4 atoms ───────────────────
                // Standard atoms use a 4-char key (e.g. "©lyr").
                // iTunes free-form atoms (----) may surface as longer keys.
                is MdtaMetadataEntry -> {
                    val keyRaw   = entry.key?.trim() ?: return
                    val rawBytes = entry.value     ?: return
                    val value    = runCatching {
                        String(rawBytes, Charsets.UTF_8).trim()
                    }.getOrNull()?.takeIf { it.isNotBlank() } ?: return

                    val keyLower = keyRaw.lowercase()
                    when {
                        // Standard lyrics atom  ©lyr  (unicode copyright + "lyr")
                        keyRaw == "\u00a9lyr" || keyLower.endsWith(".lyrics") ->
                            if (lyricsEng == null) lyricsEng = value

                        // iTunes free-form ReplayGain atoms
                        keyLower.contains("replaygain_track_gain") ->
                            if (rgTrackGain == null) rgTrackGain = value
                        keyLower.contains("replaygain_track_peak") ->
                            if (rgTrackPeak == null) rgTrackPeak = value
                        keyLower.contains("replaygain_album_gain") ->
                            if (rgAlbumGain == null) rgAlbumGain = value
                        keyLower.contains("replaygain_album_peak") ->
                            if (rgAlbumPeak == null) rgAlbumPeak = value
                        keyLower.contains("r128_track_gain")       ->
                            if (r128Track   == null) r128Track   = value
                        keyLower.contains("r128_album_gain")       ->
                            if (r128Album   == null) r128Album   = value
                        keyLower.contains("itunnorm") ||
                        keyLower.contains("itun norm")              ->
                            if (iTunNorm    == null) iTunNorm    = value
                    }
                }
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
     * Reads all metadata tags for the audio file at [path].
     *
     * Uses ExoPlayer [MetadataRetriever] which creates an internal
     * [android.os.HandlerThread] — safe to call from any background thread.
     * Blocks for up to [TIMEOUT_SEC] seconds.
     *
     * @param context Application or activity context.
     * @param path    Absolute file path.
     * @return [AudioTags] with populated fields; all-null if nothing found or error.
     */
    fun read(context: Context, path: String): AudioTags {
        if (path.isBlank()) return AudioTags()
        val file = File(path)
        if (!file.exists()) return AudioTags()

        return try {
            // Use Uri.fromFile so ExoPlayer reads directly via FileDataSource,
            // bypassing any content-resolver redirects that MIUI may intercept.
            val mediaItem = MediaItem.fromUri(Uri.fromFile(file))
            val future    = MetadataRetriever.retrieveMetadata(context, mediaItem)
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
            builder.build().also {
                Log.d(TAG, "Read ${path.substringAfterLast('/')}: " +
                    "rg=${it.rgTrackGain} r128=${it.r128Track} " +
                    "lyrics=${it.lyrics?.length?.let { n -> "${n}ch" } ?: "none"}")
            }
        } catch (e: TimeoutException) {
            Log.w(TAG, "Timed out reading: $path")
            AudioTags()
        } catch (e: Exception) {
            Log.w(TAG, "Failed reading $path: ${e.message}")
            AudioTags()
        }
    }
}
