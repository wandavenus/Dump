package dev.wndavenz.music.metadata

import androidx.media3.common.util.UnstableApi
import androidx.media3.container.MdtaMetadataEntry
import androidx.media3.extractor.metadata.id3.CommentFrame
import androidx.media3.extractor.metadata.id3.TextInformationFrame
import androidx.media3.extractor.metadata.vorbis.VorbisComment

/**
 * Accumulates parsed metadata entries into a single [ExoMetadataReader.AudioTags].
 *
 * Handles four Media3 entry types:
 *   [TextInformationFrame]  — ID3v2 text frames (MP3/WAV): TXXX custom + standard T*** frames.
 *   [CommentFrame]          — ID3v2 COMM comment frames.
 *   [VorbisComment]         — Vorbis comments (FLAC/OGG/OPUS): ReplayGain, R128, extended tags.
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

    // ── Extended metadata tags ────────────────────────────────────────────────
    var composer    : String? = null
    var comment     : String? = null
    var encoder     : String? = null
    var isrc        : String? = null
    var copyright   : String? = null
    var publisher   : String? = null

    /**
     * Processes a single [androidx.media3.common.Metadata.Entry].
     * Unknown entry types are silently ignored.
     */
    fun consume(entry: androidx.media3.common.Metadata.Entry) {
        when (entry) {

            // ── ID3v2 TextInformationFrame — handles all T*** frames ───────────
            is TextInformationFrame -> {
                val id = entry.id.uppercase().trim()

                when (id) {
                    // ── Standard ID3v2 text information frames ─────────────────
                    "TCOM" -> {
                        val v = entry.values.firstOrNull()?.trim()?.takeIf { it.isNotBlank() } ?: return
                        if (composer  == null) composer  = v
                    }
                    "TENC" -> {
                        val v = entry.values.firstOrNull()?.trim()?.takeIf { it.isNotBlank() } ?: return
                        if (encoder   == null) encoder   = v
                    }
                    "TSRC" -> {
                        val v = entry.values.firstOrNull()?.trim()?.takeIf { it.isNotBlank() } ?: return
                        if (isrc      == null) isrc      = v
                    }
                    "TCOP" -> {
                        val v = entry.values.firstOrNull()?.trim()?.takeIf { it.isNotBlank() } ?: return
                        if (copyright == null) copyright = v
                    }
                    "TPUB" -> {
                        val v = entry.values.firstOrNull()?.trim()?.takeIf { it.isNotBlank() } ?: return
                        if (publisher == null) publisher = v
                    }

                    // ── TXXX — custom user-text frames (ReplayGain, R128, iTunNORM) ─
                    "TXXX" -> {
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
                }
            }

            // ── ID3v2 CommentFrame (COMM) ─────────────────────────────────────
            is CommentFrame -> {
                val text = entry.text.trim().takeIf { it.isNotBlank() } ?: return
                // Prefer standard comments (blank/null description) over
                // iTunes-style entries that use description as a namespaced key.
                if (comment == null || entry.description.isNullOrBlank()) {
                    comment = text
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
                    "COMPOSER"               -> if (composer    == null) composer    = value
                    "COMMENT",
                    "DESCRIPTION"            -> if (comment     == null) comment     = value
                    "ENCODER",
                    "ENCODED-BY"             -> if (encoder     == null) encoder     = value
                    "ISRC"                   -> if (isrc        == null) isrc        = value
                    "COPYRIGHT"              -> if (copyright   == null) copyright   = value
                    "ORGANIZATION",
                    "PUBLISHER"              -> if (publisher   == null) publisher   = value
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
        composer    = composer,
        comment     = comment,
        encoder     = encoder,
        isrc        = isrc,
        copyright   = copyright,
        publisher   = publisher,
    )
}
