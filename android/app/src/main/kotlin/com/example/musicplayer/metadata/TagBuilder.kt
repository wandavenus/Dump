package com.example.musicplayer.metadata

import androidx.media3.common.util.UnstableApi
import androidx.media3.container.MdtaMetadataEntry
import androidx.media3.extractor.metadata.id3.TextInformationFrame
import androidx.media3.extractor.metadata.vorbis.VorbisComment

/**
 * Accumulates parsed metadata entries into a single [ExoMetadataReader.AudioTags].
 *
 * Handles three Media3 entry types:
 *   [TextInformationFrame]  — ID3v2 TXXX frames (MP3/WAV): ReplayGain, R128, iTunNORM.
 *   [VorbisComment]         — Vorbis comments (FLAC/OGG/OPUS): ReplayGain, R128, lyrics.
 *   [MdtaMetadataEntry]     — QuickTime mdta atoms (M4A): ©lyr lyrics.
 *
 * Extracted as `internal` so it can be tested in JVM unit tests without an Android device.
 * All fields are nullable: null means the tag was not found in the file.
 */
@OptIn(UnstableApi::class)
internal class TagBuilder {

    var rgTrackGain : String? = null
    var rgTrackPeak : String? = null
    var rgAlbumGain : String? = null
    var rgAlbumPeak : String? = null
    var r128Track   : String? = null
    var r128Album   : String? = null
    var iTunNorm    : String? = null
    var lyrics      : String? = null

    /**
     * Processes a single [androidx.media3.common.Metadata.Entry].
     * Unknown entry types are silently ignored.
     */
    fun consume(entry: androidx.media3.common.Metadata.Entry) {
        when (entry) {

            // ── ID3v2 TXXX — MP3 / WAV ────────────────────────────────────────
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

            // ── Vorbis Comment — FLAC / OGG / OPUS ───────────────────────────
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

            // ── MdtaMetadataEntry — M4A ©lyr ─────────────────────────────────
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

    /** Builds the final [ExoMetadataReader.AudioTags] from accumulated state. */
    fun build() = ExoMetadataReader.AudioTags(
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
