package com.example.musicplayer.metadata

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.MetadataRetriever
import androidx.media3.extractor.metadata.id3.TextInformationFrame
import androidx.media3.extractor.metadata.vorbis.VorbisComment
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Reads audio metadata tags using a two-layer strategy:
 *
 *  Layer A — [MediaMetadataRetriever] (Android standard API)
 *    • Lyrics: METADATA_KEY_LYRICS covers USLT (MP3), ©lyr (M4A), and most other
 *      containers.  Available from API 12; reliable on all Android 10+ / MIUI 11+.
 *
 *  Layer B — ExoPlayer [MetadataRetriever] (@UnstableApi)
 *    • ReplayGain / R128 / iTunNORM tags via:
 *        ID3v2 TXXX frames → [TextInformationFrame]   (MP3, WAV-with-ID3)
 *        Vorbis Comments   → [VorbisComment]           (FLAC, OGG, OPUS)
 *    • Vorbis LYRICS comment (priority over Layer A for FLAC/OGG/OPUS files).
 *
 * Why not use [UnsynchronizedLyricsFrame] / [MdtaMetadataEntry]:
 *   These classes are not in the public API surface of media3-extractor:1.10.1 —
 *   they either don't exist at that version or are @InternalOnly.
 *   [MediaMetadataRetriever.METADATA_KEY_LYRICS] covers all the same containers.
 *
 * Must be called from a background thread — [read] blocks for up to [TIMEOUT_SEC].
 * Never throws; returns empty [AudioTags] on any error.
 *
 * MIUI note: [Uri.fromFile] is used so ExoPlayer reads directly from the
 * file system path rather than via the content resolver, avoiding MIUI's
 * occasional permission issues with content:// URIs for external-storage files.
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

    // ── Internal builder (ReplayGain + Vorbis lyrics only) ───────────────────

    private class TagBuilder {
        var rgTrackGain : String? = null
        var rgTrackPeak : String? = null
        var rgAlbumGain : String? = null
        var rgAlbumPeak : String? = null
        var r128Track   : String? = null
        var r128Album   : String? = null
        var iTunNorm    : String? = null
        // Vorbis LYRICS comment — used for FLAC/OGG/OPUS files
        var vorbisLyrics: String? = null

        fun consume(entry: androidx.media3.common.Metadata.Entry) {
            when (entry) {

                // ── ID3v2 TXXX — MP3 / WAV ReplayGain ─────────────────────
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

                // ── Vorbis Comment — FLAC / OGG / OPUS ────────────────────
                is VorbisComment -> {
                    val key   = entry.key.uppercase().trim()
                    val value = entry.value.trim().takeIf { it.isNotBlank() } ?: return
                    when (key) {
                        "REPLAYGAIN_TRACK_GAIN"  -> if (rgTrackGain   == null) rgTrackGain   = value
                        "REPLAYGAIN_TRACK_PEAK"  -> if (rgTrackPeak   == null) rgTrackPeak   = value
                        "REPLAYGAIN_ALBUM_GAIN"  -> if (rgAlbumGain   == null) rgAlbumGain   = value
                        "REPLAYGAIN_ALBUM_PEAK"  -> if (rgAlbumPeak   == null) rgAlbumPeak   = value
                        "R128_TRACK_GAIN"        -> if (r128Track     == null) r128Track     = value
                        "R128_ALBUM_GAIN"        -> if (r128Album     == null) r128Album     = value
                        "LYRICS",
                        "UNSYNCEDLYRICS",
                        "UNSYNCED LYRICS"        -> if (vorbisLyrics  == null) vorbisLyrics  = value
                    }
                }

                // All other entry types (BinaryFrame, etc.) are ignored — any
                // lyrics they would carry are already handled by Layer A (MMR).
                else -> {}
            }
        }

        fun build(mmrLyrics: String?) = AudioTags(
            rgTrackGain = rgTrackGain,
            rgTrackPeak = rgTrackPeak,
            rgAlbumGain = rgAlbumGain,
            rgAlbumPeak = rgAlbumPeak,
            r128Track   = r128Track,
            r128Album   = r128Album,
            iTunNorm    = iTunNorm,
            // Vorbis LYRICS comment takes priority (proper tag format);
            // fall back to MMR result which covers USLT (MP3) and ©lyr (M4A).
            lyrics      = vorbisLyrics ?: mmrLyrics,
        )
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Reads all audio metadata for the file at [path].
     *
     * Layer A ([MediaMetadataRetriever]) runs synchronously first to extract lyrics.
     * Layer B (ExoPlayer [MetadataRetriever]) then reads ReplayGain / R128 tags.
     * Both layers are called from the same background thread.
     *
     * @param context Application or activity context.
     * @param path    Absolute file path.
     * @return [AudioTags] with populated fields; all-null if nothing found or on error.
     */
    fun read(context: Context, path: String): AudioTags {
        if (path.isBlank()) return AudioTags()
        val file = File(path)
        if (!file.exists()) return AudioTags()

        // ── Layer A: MediaMetadataRetriever — lyrics (all formats) ────────
        // METADATA_KEY_LYRICS reads:
        //   USLT frames in MP3  (all languages, returns first match)
        //   ©lyr atom in M4A / AAC
        //   Lyrics tag in other containers where supported
        val mmrLyrics: String? = try {
            val mmr = MediaMetadataRetriever()
            mmr.setDataSource(path)
            val raw = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_LYRICS)
            mmr.release()
            raw?.trim()?.takeIf { it.isNotBlank() }
        } catch (_: Exception) { null }

        // ── Layer B: ExoPlayer MetadataRetriever — ReplayGain + Vorbis ────
        // Uses Uri.fromFile so ExoPlayer's FileDataSource reads directly from
        // the filesystem path, bypassing content-resolver on MIUI.
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
            builder.build(mmrLyrics).also { tags ->
                Log.d(TAG, "Read ${file.name}: " +
                    "rg=${tags.rgTrackGain} r128=${tags.r128Track} " +
                    "lyrics=${tags.lyrics?.length?.let { "${it}ch" } ?: "none"}")
            }
        } catch (e: TimeoutException) {
            Log.w(TAG, "ExoPlayer timed out for: $path — returning MMR data only")
            AudioTags(lyrics = mmrLyrics)
        } catch (e: Exception) {
            Log.w(TAG, "ExoPlayer failed for $path: ${e.message} — returning MMR data only")
            AudioTags(lyrics = mmrLyrics)
        }
    }
}
