package com.example.musicplayer.metadata

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.container.MdtaMetadataEntry
import androidx.media3.exoplayer.MetadataRetriever
import androidx.media3.extractor.metadata.id3.TextInformationFrame
import androidx.media3.extractor.metadata.id3.UnsynchronizedLyricsFrame
import androidx.media3.extractor.metadata.vorbis.VorbisComment
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Reads audio metadata tags using a two-layer strategy:
 *
 * ════════════════════════════════════════════════════════════════════════
 *  AUDIT RESULT — Media3 1.10.1 Lyrics Extraction Capability
 * ════════════════════════════════════════════════════════════════════════
 *
 *  Pure Media3 lyrics extraction is NOT fully achievable in 1.10.1.
 *  MediaMetadataRetriever remains required for MP3 USLT frames.
 *
 *  Root cause: Media3 issue #922 (open, "low priority" as of June 2026).
 *  The MP3 ID3 parser in Media3 1.10.1 emits USLT frames as BinaryFrame
 *  instead of UnsynchronizedLyricsFrame. The class UnsynchronizedLyricsFrame
 *  EXISTS in the public API (@UnstableApi, androidx.media3.extractor.metadata
 *  .id3) but the extractor never instantiates it for MP3 files.
 *
 *  See: https://github.com/androidx/media/issues/922
 *       https://github.com/androidx/media/issues/1435
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Implemented architecture (final, post-audit):
 * ════════════════════════════════════════════════════════════════════════
 *
 *  MediaStore
 *       ↓
 *  Layer A — android.media.MediaMetadataRetriever  (MP3 USLT only)
 *    • METADATA_KEY_LYRICS — reads USLT from MP3, ©lyr from M4A.
 *    • Necessary because Media3 1.10.1 MP3 extractor emits USLT as
 *      BinaryFrame (issue #922). Skipped for FLAC/OGG/OPUS because
 *      Layer B covers those containers completely.
 *
 *  Layer B — androidx.media3.exoplayer.MetadataRetriever  (@UnstableApi)
 *    • TextInformationFrame (TXXX) → ReplayGain / R128 / iTunNORM (MP3, WAV)
 *    • VorbisComment         → ReplayGain / R128 + LYRICS (FLAC, OGG, OPUS)
 *    • UnsynchronizedLyricsFrame → MP3 USLT (class is public @UnstableApi;
 *        extractor does not yet populate it for MP3 — future-proof guard)
 *    • MdtaMetadataEntry (©lyr) → M4A lyrics as UTF-8 bytes
 *        Requires: androidx.media3:media3-container:1.10.1
 *        Fallback: MMR Layer A covers this case when Media3 cannot parse it.
 *       ↓
 *  MetadataCacheDb  (SQLite, keyed by song_id + mtime)
 *       ↓
 *  Flutter
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Per-class public API status in media3 1.10.1:
 * ════════════════════════════════════════════════════════════════════════
 *
 *  Class                      | Artifact              | Status
 *  ─────────────────────────────────────────────────────────────────────
 *  TextInformationFrame       | media3-extractor      | Public @UnstableApi
 *  VorbisComment              | media3-extractor      | Public @UnstableApi
 *  UnsynchronizedLyricsFrame  | media3-extractor      | Public @UnstableApi;
 *                             |                       | extractor emits
 *                             |                       | BinaryFrame for MP3
 *                             |                       | (bug #922, open)
 *  MdtaMetadataEntry          | media3-container      | Public @UnstableApi;
 *                             |                       | separate artifact dep
 *  BinaryFrame                | media3-extractor      | Public @UnstableApi;
 *                             |                       | used for unhandled ID3
 *
 * MIUI note: Uri.fromFile is used so ExoPlayer reads directly from the
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

    /**
     * Accumulates tags from every metadata entry emitted by Media3.
     *
     * Priority rules for lyrics (highest → lowest):
     *   1. VorbisComment LYRICS / UNSYNCEDLYRICS — exact tag for FLAC/OGG/OPUS.
     *   2. UnsynchronizedLyricsFrame             — USLT via Media3 (future: when
     *                                              issue #922 is fixed upstream).
     *   3. MdtaMetadataEntry "©lyr"              — M4A iTunes lyrics atom.
     *   4. mmrLyrics (MMR fallback)              — USLT in MP3 (necessary now),
     *                                              ©lyr in M4A (MMR backup).
     */
    private class TagBuilder {
        var rgTrackGain     : String? = null
        var rgTrackPeak     : String? = null
        var rgAlbumGain     : String? = null
        var rgAlbumPeak     : String? = null
        var r128Track       : String? = null
        var r128Album       : String? = null
        var iTunNorm        : String? = null
        // Media3-sourced lyrics (formats where Media3 works)
        var vorbisLyrics    : String? = null   // FLAC/OGG/OPUS — VorbisComment
        var usltLyrics      : String? = null   // MP3 — UnsynchronizedLyricsFrame
        var mdtaLyrics      : String? = null   // M4A — MdtaMetadataEntry "©lyr"

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
                        "UNSYNCED LYRICS"        -> if (vorbisLyrics == null) vorbisLyrics = value
                    }
                }

                // ── UnsynchronizedLyricsFrame — ID3v2 USLT (MP3) ─────────────
                //
                // API status: public @UnstableApi in media3-extractor:1.10.1.
                // Extractor status: Media3 1.10.1 MP3 parser emits BinaryFrame
                // for USLT frames instead of this class (issue #922, open).
                // This branch is a future-proof guard: it will activate
                // automatically when the upstream fix is released without
                // requiring changes here. Until then, mmrLyrics (Layer A)
                // covers MP3 USLT.
                is UnsynchronizedLyricsFrame -> {
                    val value = entry.lyrics.trim().takeIf { it.isNotBlank() } ?: return
                    if (usltLyrics == null) usltLyrics = value
                }

                // ── MdtaMetadataEntry — M4A / QuickTime ©lyr atom ────────────
                //
                // API status: public @UnstableApi in media3-container:1.10.1.
                // Artifact: androidx.media3:media3-container (separate dep).
                // M4A lyrics are stored in the "©lyr" mdta key as a UTF-8
                // string (typeIndicator = TYPE_INDICATOR_STRING = 1).
                // Layer A (MMR) provides a fallback in case Media3 cannot
                // parse this atom for a specific encoder variant.
                is MdtaMetadataEntry -> {
                    if (entry.key == "\u00a9lyr") {         // "©lyr"
                        if (mdtaLyrics == null) {
                            val decoded = runCatching {
                                entry.value.toString(Charsets.UTF_8)
                                    .trim().takeIf { it.isNotBlank() }
                            }.getOrNull()
                            mdtaLyrics = decoded
                        }
                    }
                }

                // ── All other entry types are ignored ─────────────────────────
                //
                // Notable ignored type: BinaryFrame.
                // In MP3, USLT currently arrives as BinaryFrame (issue #922).
                // We intentionally do NOT attempt to decode BinaryFrame raw
                // bytes here — the encoding, language prefix, and content
                // descriptor fields make manual decoding unreliable across
                // ID3v2.3 / v2.4 variants. MMR (Layer A) is the correct
                // fallback and handles encoding transparently.
                else -> {}
            }
        }

        /**
         * Merges all collected tags into a final [AudioTags].
         *
         * Lyrics priority (first non-null wins):
         *   vorbisLyrics > usltLyrics > mdtaLyrics > mmrLyrics
         *
         * [mmrLyrics] is the result from [MediaMetadataRetriever] (Layer A).
         * It covers MP3 USLT (primary use now) and M4A ©lyr (backup).
         */
        fun build(mmrLyrics: String?) = AudioTags(
            rgTrackGain = rgTrackGain,
            rgTrackPeak = rgTrackPeak,
            rgAlbumGain = rgAlbumGain,
            rgAlbumPeak = rgAlbumPeak,
            r128Track   = r128Track,
            r128Album   = r128Album,
            iTunNorm    = iTunNorm,
            lyrics      = vorbisLyrics ?: usltLyrics ?: mdtaLyrics ?: mmrLyrics,
        )
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Reads all audio metadata for the file at [path].
     *
     * Layer A ([MediaMetadataRetriever]) runs synchronously to extract lyrics
     * for containers where Media3 cannot yet read them (primarily MP3 USLT —
     * see issue #922). Layer B (ExoPlayer [MetadataRetriever]) reads
     * ReplayGain / R128 tags and lyrics for FLAC/OGG/OPUS/M4A.
     *
     * @param context Application or activity context.
     * @param path    Absolute file path.
     * @return [AudioTags] with populated fields; all-null if nothing found or on error.
     */
    fun read(context: Context, path: String): AudioTags {
        if (path.isBlank()) return AudioTags()
        val file = File(path)
        if (!file.exists()) return AudioTags()

        val ext = file.extension.lowercase()

        // ── Layer A: MediaMetadataRetriever — lyrics for MP3 and M4A ─────────
        //
        // We only run MMR for containers where Media3 cannot supply lyrics:
        //   • MP3  — USLT → BinaryFrame in Media3 (issue #922, still open)
        //   • M4A  — ©lyr backup when MdtaMetadataEntry parsing fails
        //
        // FLAC / OGG / OPUS are fully covered by VorbisComment in Layer B;
        // running MMR on those files would be wasted I/O.
        val needsMmrLyrics = ext == "mp3" || ext == "m4a" || ext == "aac" || ext == "mp4"

        val mmrLyrics: String? = if (needsMmrLyrics) {
            try {
                val mmr = MediaMetadataRetriever()
                mmr.setDataSource(path)
                val raw = mmr.extractMetadata(MediaMetadataRetriever.METADATA_KEY_LYRICS)
                mmr.release()
                raw?.trim()?.takeIf { it.isNotBlank() }
            } catch (_: Exception) { null }
        } else null

        // ── Layer B: ExoPlayer MetadataRetriever — ReplayGain + Media3 lyrics ─
        //
        // Uses Uri.fromFile so ExoPlayer's FileDataSource reads directly from
        // the filesystem path, bypassing the content resolver on MIUI.
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
                    "lyrics=${tags.lyrics?.length?.let { "${it}ch" } ?: "none"} " +
                    "(src: vorbis=${builder.vorbisLyrics != null} " +
                    "uslt=${builder.usltLyrics != null} " +
                    "mdta=${builder.mdtaLyrics != null} " +
                    "mmr=${mmrLyrics != null})")
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
