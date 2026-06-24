package com.example.musicplayer.metadata

import androidx.media3.common.util.UnstableApi
import androidx.media3.container.MdtaMetadataEntry
import androidx.media3.extractor.metadata.id3.TextInformationFrame
import androidx.media3.extractor.metadata.vorbis.VorbisComment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * JVM unit tests for [TagBuilder].
 *
 * Runs on the local JVM — no Android device, emulator, MediaStore, or
 * Flutter layer required.  Covers all three Media3 entry types that
 * [TagBuilder.consume] handles:
 *
 *   [TextInformationFrame]  — ID3v2 TXXX frames (MP3/WAV)
 *   [VorbisComment]         — Vorbis comments    (FLAC/OGG/OPUS)
 *   [MdtaMetadataEntry]     — QuickTime mdta      (M4A)
 *
 * Test groups:
 *   A. TextInformationFrame  — happy-path, case, invalid input, malformed values
 *   B. VorbisComment         — happy-path, case, invalid input, malformed values
 *   C. MdtaMetadataEntry     — happy-path, UTF-8, invalid/malformed payload
 *   D. Duplicate-key policy  — first-value-wins across all entry types
 *   E. Merge correctness     — multiple tags accumulated correctly
 *   F. Cross-type scenarios  — mixed entry types in a single pass
 *   G. Format regressions    — complete FLAC / OGG / OPUS / M4A scenarios
 *   H. build() / hasLoudness — AudioTags assembly and helper
 */
@OptIn(UnstableApi::class)
class TagBuilderTest {

    private lateinit var builder: TagBuilder

    @Before
    fun setUp() {
        builder = TagBuilder()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /** Creates a TXXX TextInformationFrame with a single value. */
    private fun txxx(description: String, value: String): TextInformationFrame =
        TextInformationFrame("TXXX", description, listOf(value))

    /** Creates a TXXX TextInformationFrame with an explicit values list. */
    private fun txxxValues(description: String, values: List<String>): TextInformationFrame =
        TextInformationFrame("TXXX", description, values)

    /** Creates a VorbisComment. */
    private fun vorbis(key: String, value: String): VorbisComment =
        VorbisComment(key, value)

    /** Creates an MdtaMetadataEntry for ©lyr with a UTF-8 lyrics payload. */
    private fun mdtaLyr(lyrics: String): MdtaMetadataEntry =
        MdtaMetadataEntry(
            "\u00a9lyr",
            lyrics.toByteArray(Charsets.UTF_8),
            MdtaMetadataEntry.TYPE_INDICATOR_STRING,
        )

    /** Creates an MdtaMetadataEntry for ©lyr with a raw byte payload. */
    private fun mdtaLyrBytes(bytes: ByteArray): MdtaMetadataEntry =
        MdtaMetadataEntry(
            "\u00a9lyr",
            bytes,
            MdtaMetadataEntry.TYPE_INDICATOR_STRING,
        )

    /** Creates an MdtaMetadataEntry with an arbitrary key. */
    private fun mdtaKey(key: String, value: String): MdtaMetadataEntry =
        MdtaMetadataEntry(
            key,
            value.toByteArray(Charsets.UTF_8),
            MdtaMetadataEntry.TYPE_INDICATOR_STRING,
        )

    // ═════════════════════════════════════════════════════════════════════════
    // A. TextInformationFrame — TXXX (MP3 / WAV)
    // ═════════════════════════════════════════════════════════════════════════

    // ── A1. Happy-path parsing ────────────────────────────────────────────────

    @Test fun `A01 TXXX REPLAYGAIN_TRACK_GAIN parsed`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "+1.23 dB"))
        assertEquals("+1.23 dB", builder.rgTrackGain)
    }

    @Test fun `A02 TXXX REPLAYGAIN_TRACK_PEAK parsed`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_PEAK", "0.987654"))
        assertEquals("0.987654", builder.rgTrackPeak)
    }

    @Test fun `A03 TXXX REPLAYGAIN_ALBUM_GAIN parsed`() {
        builder.consume(txxx("REPLAYGAIN_ALBUM_GAIN", "-0.50 dB"))
        assertEquals("-0.50 dB", builder.rgAlbumGain)
    }

    @Test fun `A04 TXXX REPLAYGAIN_ALBUM_PEAK parsed`() {
        builder.consume(txxx("REPLAYGAIN_ALBUM_PEAK", "1.0"))
        assertEquals("1.0", builder.rgAlbumPeak)
    }

    @Test fun `A05 TXXX R128_TRACK_GAIN parsed`() {
        builder.consume(txxx("R128_TRACK_GAIN", "-650"))
        assertEquals("-650", builder.r128Track)
    }

    @Test fun `A06 TXXX R128TRACKGAIN alias parsed`() {
        builder.consume(txxx("R128TRACKGAIN", "-700"))
        assertEquals("-700", builder.r128Track)
    }

    @Test fun `A07 TXXX R128_ALBUM_GAIN parsed`() {
        builder.consume(txxx("R128_ALBUM_GAIN", "-600"))
        assertEquals("-600", builder.r128Album)
    }

    @Test fun `A08 TXXX R128ALBUMGAIN alias parsed`() {
        builder.consume(txxx("R128ALBUMGAIN", "-580"))
        assertEquals("-580", builder.r128Album)
    }

    @Test fun `A09 TXXX ITUNNORM parsed`() {
        builder.consume(txxx("ITUNNORM", " 000002A6 000002A6 "))
        assertEquals("000002A6 000002A6", builder.iTunNorm)
    }

    @Test fun `A10 TXXX ITUN NORM space-alias parsed`() {
        builder.consume(txxx("ITUN NORM", "000002A6 000002A6"))
        assertEquals("000002A6 000002A6", builder.iTunNorm)
    }

    // ── A2. Case-insensitivity ────────────────────────────────────────────────

    @Test fun `A11 TXXX description lowercase accepted`() {
        builder.consume(txxx("replaygain_track_gain", "+2.00 dB"))
        assertEquals("+2.00 dB", builder.rgTrackGain)
    }

    @Test fun `A12 TXXX description mixed-case accepted`() {
        builder.consume(txxx("Replaygain_Album_Gain", "-1.00 dB"))
        assertEquals("-1.00 dB", builder.rgAlbumGain)
    }

    @Test fun `A13 TXXX id case-insensitive txxx accepted`() {
        builder.consume(TextInformationFrame("txxx", "REPLAYGAIN_TRACK_GAIN", listOf("+0.50 dB")))
        assertEquals("+0.50 dB", builder.rgTrackGain)
    }

    // ── A3. Invalid input (ignored without throwing) ──────────────────────────

    @Test fun `A14 non-TXXX TextInformationFrame ignored`() {
        builder.consume(TextInformationFrame("TIT2", null, listOf("Song Title")))
        assertNull(builder.rgTrackGain)
        assertNull(builder.lyrics)
    }

    @Test fun `A15 TXXX with null description ignored`() {
        builder.consume(TextInformationFrame("TXXX", null, listOf("+1.00 dB")))
        assertNull(builder.rgTrackGain)
    }

    @Test fun `A16 TXXX with unknown description ignored`() {
        builder.consume(txxx("ENCODER", "LAME 3.100"))
        assertNull(builder.rgTrackGain)
        assertNull(builder.lyrics)
    }

    @Test fun `A17 TXXX with blank value ignored`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "   "))
        assertNull(builder.rgTrackGain)
    }

    @Test fun `A18 TXXX with empty values list ignored`() {
        builder.consume(txxxValues("REPLAYGAIN_TRACK_GAIN", emptyList()))
        assertNull(builder.rgTrackGain)
    }

    @Test fun `A19 TXXX with single blank entry in values list ignored`() {
        builder.consume(txxxValues("REPLAYGAIN_TRACK_GAIN", listOf("  ")))
        assertNull(builder.rgTrackGain)
    }

    // ── A4. Malformed "numeric" ReplayGain values — raw string pass-through ───
    //
    // TagBuilder does NOT parse or validate numeric strings. It stores the raw
    // trimmed value verbatim. Downstream consumers are responsible for parsing.
    // These tests confirm malformed values are stored, not rejected.

    @Test fun `A20 TXXX ReplayGain value without unit stored verbatim`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "+1.23"))
        assertEquals("+1.23", builder.rgTrackGain)
    }

    @Test fun `A21 TXXX ReplayGain value missing space before dB stored verbatim`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "+1.23dB"))
        assertEquals("+1.23dB", builder.rgTrackGain)
    }

    @Test fun `A22 TXXX ReplayGain non-numeric string stored verbatim`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "not_a_number"))
        assertEquals("not_a_number", builder.rgTrackGain)
    }

    @Test fun `A23 TXXX ReplayGain scientific notation stored verbatim`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "1e2"))
        assertEquals("1e2", builder.rgTrackGain)
    }

    @Test fun `A24 TXXX ReplayGain zero stored verbatim`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "0.000 dB"))
        assertEquals("0.000 dB", builder.rgTrackGain)
    }

    @Test fun `A25 TXXX ReplayGain negative zero stored verbatim`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "-0.00 dB"))
        assertEquals("-0.00 dB", builder.rgTrackGain)
    }

    @Test fun `A26 TXXX R128 non-integer value stored verbatim`() {
        builder.consume(txxx("R128_TRACK_GAIN", "-650.5"))
        assertEquals("-650.5", builder.r128Track)
    }

    @Test fun `A27 TXXX only first value used when multi-value list`() {
        builder.consume(txxxValues("REPLAYGAIN_TRACK_GAIN", listOf("+1.00 dB", "+9.99 dB")))
        assertEquals("+1.00 dB", builder.rgTrackGain)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // B. VorbisComment — FLAC / OGG / OPUS
    // ═════════════════════════════════════════════════════════════════════════

    // ── B1. Happy-path parsing ────────────────────────────────────────────────

    @Test fun `B01 VorbisComment REPLAYGAIN_TRACK_GAIN parsed`() {
        builder.consume(vorbis("REPLAYGAIN_TRACK_GAIN", "+3.14 dB"))
        assertEquals("+3.14 dB", builder.rgTrackGain)
    }

    @Test fun `B02 VorbisComment REPLAYGAIN_TRACK_PEAK parsed`() {
        builder.consume(vorbis("REPLAYGAIN_TRACK_PEAK", "0.999"))
        assertEquals("0.999", builder.rgTrackPeak)
    }

    @Test fun `B03 VorbisComment REPLAYGAIN_ALBUM_GAIN parsed`() {
        builder.consume(vorbis("REPLAYGAIN_ALBUM_GAIN", "-1.00 dB"))
        assertEquals("-1.00 dB", builder.rgAlbumGain)
    }

    @Test fun `B04 VorbisComment REPLAYGAIN_ALBUM_PEAK parsed`() {
        builder.consume(vorbis("REPLAYGAIN_ALBUM_PEAK", "0.500"))
        assertEquals("0.500", builder.rgAlbumPeak)
    }

    @Test fun `B05 VorbisComment R128_TRACK_GAIN parsed`() {
        builder.consume(vorbis("R128_TRACK_GAIN", "-700"))
        assertEquals("-700", builder.r128Track)
    }

    @Test fun `B06 VorbisComment R128_ALBUM_GAIN parsed`() {
        builder.consume(vorbis("R128_ALBUM_GAIN", "-650"))
        assertEquals("-650", builder.r128Album)
    }

    @Test fun `B07 VorbisComment LYRICS parsed`() {
        builder.consume(vorbis("LYRICS", "Verse 1\nLine 2"))
        assertEquals("Verse 1\nLine 2", builder.lyrics)
    }

    @Test fun `B08 VorbisComment UNSYNCEDLYRICS parsed`() {
        builder.consume(vorbis("UNSYNCEDLYRICS", "La la la"))
        assertEquals("La la la", builder.lyrics)
    }

    @Test fun `B09 VorbisComment UNSYNCED LYRICS with space parsed`() {
        builder.consume(vorbis("UNSYNCED LYRICS", "Do re mi"))
        assertEquals("Do re mi", builder.lyrics)
    }

    // ── B2. Case-insensitivity ────────────────────────────────────────────────

    @Test fun `B10 VorbisComment key lowercase accepted`() {
        builder.consume(vorbis("lyrics", "lowercase key test"))
        assertEquals("lowercase key test", builder.lyrics)
    }

    @Test fun `B11 VorbisComment key mixed-case accepted`() {
        builder.consume(vorbis("LyRiCs", "mixed case key"))
        assertEquals("mixed case key", builder.lyrics)
    }

    @Test fun `B12 VorbisComment ReplayGain key lowercase accepted`() {
        builder.consume(vorbis("replaygain_track_gain", "+1.00 dB"))
        assertEquals("+1.00 dB", builder.rgTrackGain)
    }

    // ── B3. Invalid input ─────────────────────────────────────────────────────

    @Test fun `B13 VorbisComment blank value ignored`() {
        builder.consume(vorbis("LYRICS", "   "))
        assertNull(builder.lyrics)
    }

    @Test fun `B14 VorbisComment empty value ignored`() {
        builder.consume(vorbis("LYRICS", ""))
        assertNull(builder.lyrics)
    }

    @Test fun `B15 VorbisComment unknown key ignored`() {
        builder.consume(vorbis("COMMENT", "Some comment"))
        assertNull(builder.lyrics)
        assertNull(builder.rgTrackGain)
    }

    @Test fun `B16 VorbisComment ALBUMARTIST ignored`() {
        builder.consume(vorbis("ALBUMARTIST", "Artist Name"))
        assertNull(builder.rgTrackGain)
        assertNull(builder.lyrics)
    }

    // ── B4. Malformed "numeric" ReplayGain — raw string pass-through ──────────

    @Test fun `B17 VorbisComment ReplayGain without unit stored verbatim`() {
        builder.consume(vorbis("REPLAYGAIN_TRACK_GAIN", "+2.00"))
        assertEquals("+2.00", builder.rgTrackGain)
    }

    @Test fun `B18 VorbisComment ReplayGain non-numeric stored verbatim`() {
        builder.consume(vorbis("REPLAYGAIN_TRACK_GAIN", "bad_value"))
        assertEquals("bad_value", builder.rgTrackGain)
    }

    @Test fun `B19 VorbisComment ReplayGain leading whitespace stripped`() {
        builder.consume(vorbis("REPLAYGAIN_TRACK_GAIN", "  +1.00 dB  "))
        assertEquals("+1.00 dB", builder.rgTrackGain)
    }

    @Test fun `B20 VorbisComment R128 float value stored verbatim`() {
        builder.consume(vorbis("R128_TRACK_GAIN", "-700.25"))
        assertEquals("-700.25", builder.r128Track)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // C. MdtaMetadataEntry — M4A ©lyr
    // ═════════════════════════════════════════════════════════════════════════

    // ── C1. Happy-path parsing ────────────────────────────────────────────────

    @Test fun `C01 MdtaMetadataEntry copyright-lyr plain ASCII parsed`() {
        builder.consume(mdtaLyr("M4A lyrics content"))
        assertEquals("M4A lyrics content", builder.lyrics)
    }

    @Test fun `C02 MdtaMetadataEntry copyright-lyr multiline parsed`() {
        val lines = "Line 1\nLine 2\nLine 3"
        builder.consume(mdtaLyr(lines))
        assertEquals(lines, builder.lyrics)
    }

    // ── C2. UTF-8 payload handling ────────────────────────────────────────────

    @Test fun `C03 MdtaMetadataEntry UTF-8 Japanese characters parsed`() {
        builder.consume(mdtaLyr("日本語の歌詞"))
        assertEquals("日本語の歌詞", builder.lyrics)
    }

    @Test fun `C04 MdtaMetadataEntry UTF-8 Korean characters parsed`() {
        builder.consume(mdtaLyr("한국어 가사"))
        assertEquals("한국어 가사", builder.lyrics)
    }

    @Test fun `C05 MdtaMetadataEntry UTF-8 Arabic characters parsed`() {
        builder.consume(mdtaLyr("كلمات الأغنية"))
        assertEquals("كلمات الأغنية", builder.lyrics)
    }

    @Test fun `C06 MdtaMetadataEntry UTF-8 emoji characters parsed`() {
        builder.consume(mdtaLyr("🎵 Music 🎶"))
        assertEquals("🎵 Music 🎶", builder.lyrics)
    }

    @Test fun `C07 MdtaMetadataEntry leading and trailing whitespace trimmed`() {
        builder.consume(mdtaLyr("  trimmed  "))
        assertEquals("trimmed", builder.lyrics)
    }

    @Test fun `C08 MdtaMetadataEntry internal whitespace preserved`() {
        builder.consume(mdtaLyr("word1  word2"))
        assertEquals("word1  word2", builder.lyrics)
    }

    // ── C3. Invalid / malformed payload ──────────────────────────────────────

    @Test fun `C09 MdtaMetadataEntry blank content ignored`() {
        builder.consume(mdtaLyr("   "))
        assertNull(builder.lyrics)
    }

    @Test fun `C10 MdtaMetadataEntry empty byte array ignored`() {
        builder.consume(mdtaLyrBytes(ByteArray(0)))
        assertNull(builder.lyrics)
    }

    @Test fun `C11 MdtaMetadataEntry all-whitespace bytes ignored`() {
        builder.consume(mdtaLyrBytes(byteArrayOf(0x20, 0x20, 0x20)))  // spaces
        assertNull(builder.lyrics)
    }

    @Test fun `C12 MdtaMetadataEntry malformed UTF-8 bytes do not throw`() {
        // 0xFF is not valid UTF-8 — runCatching in TagBuilder swallows the error
        // and leaves lyrics null rather than crashing.
        val badBytes = byteArrayOf(0xFF.toByte(), 0xFE.toByte())
        builder.consume(mdtaLyrBytes(badBytes))
        // No assertion on the value — just that it does not throw
    }

    @Test fun `C13 MdtaMetadataEntry non-lyr key ignored`() {
        builder.consume(mdtaKey("com.apple.iTunes", "some value"))
        assertNull(builder.lyrics)
    }

    @Test fun `C14 MdtaMetadataEntry c-nam key ignored`() {
        builder.consume(mdtaKey("\u00a9nam", "Song Title"))
        assertNull(builder.lyrics)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // D. Duplicate-key policy — first value wins across all entry types
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `D01 TXXX duplicate REPLAYGAIN_TRACK_GAIN first wins`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "+1.00 dB"))
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "+9.99 dB"))
        assertEquals("+1.00 dB", builder.rgTrackGain)
    }

    @Test fun `D02 TXXX duplicate R128_TRACK_GAIN first wins`() {
        builder.consume(txxx("R128_TRACK_GAIN", "-650"))
        builder.consume(txxx("R128_TRACK_GAIN", "-999"))
        assertEquals("-650", builder.r128Track)
    }

    @Test fun `D03 TXXX duplicate ITUNNORM first wins`() {
        builder.consume(txxx("ITUNNORM", "AAAA"))
        builder.consume(txxx("ITUNNORM", "BBBB"))
        assertEquals("AAAA", builder.iTunNorm)
    }

    @Test fun `D04 VorbisComment duplicate LYRICS first wins`() {
        builder.consume(vorbis("LYRICS", "First lyrics"))
        builder.consume(vorbis("LYRICS", "Second lyrics"))
        assertEquals("First lyrics", builder.lyrics)
    }

    @Test fun `D05 VorbisComment duplicate REPLAYGAIN_TRACK_GAIN first wins`() {
        builder.consume(vorbis("REPLAYGAIN_TRACK_GAIN", "+1.00 dB"))
        builder.consume(vorbis("REPLAYGAIN_TRACK_GAIN", "+9.99 dB"))
        assertEquals("+1.00 dB", builder.rgTrackGain)
    }

    @Test fun `D06 VorbisComment LYRICS and UNSYNCEDLYRICS first-seen wins`() {
        builder.consume(vorbis("LYRICS", "From LYRICS tag"))
        builder.consume(vorbis("UNSYNCEDLYRICS", "From UNSYNCEDLYRICS tag"))
        assertEquals("From LYRICS tag", builder.lyrics)
    }

    @Test fun `D07 MdtaMetadataEntry duplicate copyright-lyr first wins`() {
        builder.consume(mdtaLyr("First"))
        builder.consume(mdtaLyr("Second"))
        assertEquals("First", builder.lyrics)
    }

    @Test fun `D08 VorbisComment lyrics blocks subsequent MdtaMetadataEntry`() {
        builder.consume(vorbis("LYRICS", "Vorbis wins"))
        builder.consume(mdtaLyr("M4A loses"))
        assertEquals("Vorbis wins", builder.lyrics)
    }

    @Test fun `D09 MdtaMetadataEntry lyrics blocks subsequent VorbisComment`() {
        builder.consume(mdtaLyr("M4A first"))
        builder.consume(vorbis("LYRICS", "Vorbis second"))
        assertEquals("M4A first", builder.lyrics)
    }

    @Test fun `D10 TXXX and VorbisComment same loudness field first wins`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "+1.00 dB"))
        builder.consume(vorbis("REPLAYGAIN_TRACK_GAIN", "+9.99 dB"))
        assertEquals("+1.00 dB", builder.rgTrackGain)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // E. Merge correctness — multiple distinct tags accumulated together
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `E01 all eight TXXX loudness tags merged correctly`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "+1.00 dB"))
        builder.consume(txxx("REPLAYGAIN_TRACK_PEAK", "0.900"))
        builder.consume(txxx("REPLAYGAIN_ALBUM_GAIN", "-0.50 dB"))
        builder.consume(txxx("REPLAYGAIN_ALBUM_PEAK", "0.800"))
        builder.consume(txxx("R128_TRACK_GAIN",       "-650"))
        builder.consume(txxx("R128_ALBUM_GAIN",       "-600"))
        builder.consume(txxx("ITUNNORM",              "AABB"))

        assertEquals("+1.00 dB", builder.rgTrackGain)
        assertEquals("0.900",    builder.rgTrackPeak)
        assertEquals("-0.50 dB", builder.rgAlbumGain)
        assertEquals("0.800",    builder.rgAlbumPeak)
        assertEquals("-650",     builder.r128Track)
        assertEquals("-600",     builder.r128Album)
        assertEquals("AABB",     builder.iTunNorm)
        assertNull(builder.lyrics)
    }

    @Test fun `E02 all Vorbis loudness tags merged correctly`() {
        builder.consume(vorbis("REPLAYGAIN_TRACK_GAIN", "+2.00 dB"))
        builder.consume(vorbis("REPLAYGAIN_TRACK_PEAK", "0.750"))
        builder.consume(vorbis("REPLAYGAIN_ALBUM_GAIN", "-0.25 dB"))
        builder.consume(vorbis("REPLAYGAIN_ALBUM_PEAK", "0.600"))
        builder.consume(vorbis("R128_TRACK_GAIN",       "-710"))
        builder.consume(vorbis("R128_ALBUM_GAIN",       "-690"))
        builder.consume(vorbis("LYRICS",                "Full lyrics text"))

        assertEquals("+2.00 dB",       builder.rgTrackGain)
        assertEquals("0.750",          builder.rgTrackPeak)
        assertEquals("-0.25 dB",       builder.rgAlbumGain)
        assertEquals("0.600",          builder.rgAlbumPeak)
        assertEquals("-710",           builder.r128Track)
        assertEquals("-690",           builder.r128Album)
        assertEquals("Full lyrics text", builder.lyrics)
    }

    @Test fun `E03 loudness fields do not pollute lyrics and vice versa`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "+1.00 dB"))
        builder.consume(vorbis("LYRICS", "Song text"))

        assertEquals("+1.00 dB", builder.rgTrackGain)
        assertEquals("Song text", builder.lyrics)
        assertNull(builder.r128Track)
        assertNull(builder.iTunNorm)
    }

    @Test fun `E04 tags arriving in reverse order still merge correctly`() {
        builder.consume(vorbis("R128_ALBUM_GAIN",       "-600"))
        builder.consume(vorbis("REPLAYGAIN_ALBUM_PEAK", "0.800"))
        builder.consume(vorbis("REPLAYGAIN_ALBUM_GAIN", "-0.50 dB"))
        builder.consume(vorbis("R128_TRACK_GAIN",       "-650"))
        builder.consume(vorbis("REPLAYGAIN_TRACK_PEAK", "0.900"))
        builder.consume(vorbis("REPLAYGAIN_TRACK_GAIN", "+1.00 dB"))
        builder.consume(vorbis("LYRICS",                "Lyrics last"))

        assertEquals("+1.00 dB", builder.rgTrackGain)
        assertEquals("0.900",    builder.rgTrackPeak)
        assertEquals("-0.50 dB", builder.rgAlbumGain)
        assertEquals("0.800",    builder.rgAlbumPeak)
        assertEquals("-650",     builder.r128Track)
        assertEquals("-600",     builder.r128Album)
        assertEquals("Lyrics last", builder.lyrics)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // F. Cross-type scenarios — mixed entry types in a single pass
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `F01 TXXX ReplayGain and VorbisComment lyrics coexist`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "+1.50 dB"))
        builder.consume(vorbis("LYRICS", "Cross-type lyrics"))

        assertEquals("+1.50 dB", builder.rgTrackGain)
        assertEquals("Cross-type lyrics", builder.lyrics)
    }

    @Test fun `F02 TXXX loudness and MdtaMetadataEntry lyrics coexist`() {
        builder.consume(txxx("R128_TRACK_GAIN", "-720"))
        builder.consume(txxx("ITUNNORM", "CCDD"))
        builder.consume(mdtaLyr("M4A cross-type lyrics"))

        assertEquals("-720", builder.r128Track)
        assertEquals("CCDD", builder.iTunNorm)
        assertEquals("M4A cross-type lyrics", builder.lyrics)
    }

    @Test fun `F03 all three entry types coexist without interference`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "+2.00 dB"))
        builder.consume(vorbis("R128_TRACK_GAIN", "-680"))
        builder.consume(mdtaLyr("M4A lyrics"))

        assertEquals("+2.00 dB", builder.rgTrackGain)
        assertEquals("-680", builder.r128Track)
        assertEquals("M4A lyrics", builder.lyrics)
    }

    @Test fun `F04 interleaved VorbisComment and TXXX entries all accumulated`() {
        builder.consume(vorbis("REPLAYGAIN_TRACK_GAIN", "+1.00 dB"))
        builder.consume(txxx("R128_TRACK_GAIN", "-650"))
        builder.consume(vorbis("REPLAYGAIN_ALBUM_GAIN", "-0.25 dB"))
        builder.consume(txxx("R128_ALBUM_GAIN", "-625"))
        builder.consume(vorbis("LYRICS", "Interleaved lyrics"))

        assertEquals("+1.00 dB",        builder.rgTrackGain)
        assertEquals("-0.25 dB",        builder.rgAlbumGain)
        assertEquals("-650",            builder.r128Track)
        assertEquals("-625",            builder.r128Album)
        assertEquals("Interleaved lyrics", builder.lyrics)
    }

    @Test fun `F05 unrecognised entries between valid entries do not disrupt accumulation`() {
        builder.consume(vorbis("REPLAYGAIN_TRACK_GAIN", "+1.00 dB"))
        builder.consume(vorbis("ALBUMARTIST", "ignored"))
        builder.consume(txxx("ENCODER", "ignored"))
        builder.consume(vorbis("LYRICS", "Still here"))

        assertEquals("+1.00 dB", builder.rgTrackGain)
        assertEquals("Still here", builder.lyrics)
    }

    // ═════════════════════════════════════════════════════════════════════════
    // G. Format regression scenarios — complete file-level tag sets
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `G01 regression - complete FLAC tag set`() {
        // Simulate all tags a well-tagged FLAC file would carry via VorbisComment.
        builder.consume(vorbis("REPLAYGAIN_TRACK_GAIN", "+1.14 dB"))
        builder.consume(vorbis("REPLAYGAIN_TRACK_PEAK", "0.988525"))
        builder.consume(vorbis("REPLAYGAIN_ALBUM_GAIN", "+0.80 dB"))
        builder.consume(vorbis("REPLAYGAIN_ALBUM_PEAK", "0.991340"))
        builder.consume(vorbis("R128_TRACK_GAIN",       "-1143"))
        builder.consume(vorbis("R128_ALBUM_GAIN",       "-1200"))
        builder.consume(vorbis("LYRICS",                "FLAC embedded lyrics\nLine 2"))

        val tags = builder.build()
        assertEquals("+1.14 dB",              tags.rgTrackGain)
        assertEquals("0.988525",              tags.rgTrackPeak)
        assertEquals("+0.80 dB",              tags.rgAlbumGain)
        assertEquals("0.991340",              tags.rgAlbumPeak)
        assertEquals("-1143",                 tags.r128Track)
        assertEquals("-1200",                 tags.r128Album)
        assertEquals("FLAC embedded lyrics\nLine 2", tags.lyrics)
        assertNull(tags.iTunNorm)
        assertTrue(tags.hasLoudness())
    }

    @Test fun `G02 regression - complete OGG tag set`() {
        builder.consume(vorbis("REPLAYGAIN_TRACK_GAIN", "+0.50 dB"))
        builder.consume(vorbis("REPLAYGAIN_TRACK_PEAK", "0.912000"))
        builder.consume(vorbis("REPLAYGAIN_ALBUM_GAIN", "+0.25 dB"))
        builder.consume(vorbis("REPLAYGAIN_ALBUM_PEAK", "0.900000"))
        builder.consume(vorbis("R128_TRACK_GAIN",       "-600"))
        builder.consume(vorbis("R128_ALBUM_GAIN",       "-575"))
        builder.consume(vorbis("UNSYNCEDLYRICS",        "OGG lyrics via UNSYNCEDLYRICS"))

        val tags = builder.build()
        assertEquals("+0.50 dB",                     tags.rgTrackGain)
        assertEquals("0.912000",                     tags.rgTrackPeak)
        assertEquals("+0.25 dB",                     tags.rgAlbumGain)
        assertEquals("0.900000",                     tags.rgAlbumPeak)
        assertEquals("-600",                         tags.r128Track)
        assertEquals("-575",                         tags.r128Album)
        assertEquals("OGG lyrics via UNSYNCEDLYRICS", tags.lyrics)
        assertTrue(tags.hasLoudness())
    }

    @Test fun `G03 regression - complete OPUS tag set`() {
        builder.consume(vorbis("REPLAYGAIN_TRACK_GAIN", "-0.12 dB"))
        builder.consume(vorbis("REPLAYGAIN_TRACK_PEAK", "0.955000"))
        builder.consume(vorbis("R128_TRACK_GAIN",       "-750"))
        builder.consume(vorbis("R128_ALBUM_GAIN",       "-720"))
        builder.consume(vorbis("LYRICS",                "OPUS lyrics"))

        val tags = builder.build()
        assertEquals("-0.12 dB",   tags.rgTrackGain)
        assertEquals("0.955000",   tags.rgTrackPeak)
        assertEquals("-750",       tags.r128Track)
        assertEquals("-720",       tags.r128Album)
        assertEquals("OPUS lyrics", tags.lyrics)
        assertTrue(tags.hasLoudness())
    }

    @Test fun `G04 regression - complete M4A tag set`() {
        // M4A: TXXX carries iTunNORM/ReplayGain; MdtaMetadataEntry carries ©lyr.
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "+0.75 dB"))
        builder.consume(txxx("REPLAYGAIN_TRACK_PEAK", "0.970000"))
        builder.consume(txxx("REPLAYGAIN_ALBUM_GAIN", "+0.60 dB"))
        builder.consume(txxx("REPLAYGAIN_ALBUM_PEAK", "0.965000"))
        builder.consume(txxx("ITUNNORM",              " 00000258 00000258 00004E72 00004E72 0002CE5B"))
        builder.consume(mdtaLyr("M4A embedded lyrics\nVerse 2"))

        val tags = builder.build()
        assertEquals("+0.75 dB",  tags.rgTrackGain)
        assertEquals("0.970000",  tags.rgTrackPeak)
        assertEquals("+0.60 dB",  tags.rgAlbumGain)
        assertEquals("0.965000",  tags.rgAlbumPeak)
        assertEquals("00000258 00000258 00004E72 00004E72 0002CE5B", tags.iTunNorm)
        assertEquals("M4A embedded lyrics\nVerse 2", tags.lyrics)
        assertTrue(tags.hasLoudness())
    }

    @Test fun `G05 regression - file with ReplayGain but no lyrics`() {
        builder.consume(vorbis("REPLAYGAIN_TRACK_GAIN", "+1.00 dB"))
        builder.consume(vorbis("REPLAYGAIN_ALBUM_GAIN", "+0.50 dB"))

        val tags = builder.build()
        assertEquals("+1.00 dB", tags.rgTrackGain)
        assertEquals("+0.50 dB", tags.rgAlbumGain)
        assertNull(tags.lyrics)
        assertTrue(tags.hasLoudness())
    }

    @Test fun `G06 regression - file with lyrics but no loudness tags`() {
        builder.consume(vorbis("LYRICS", "Lyrics only, no gain tags"))

        val tags = builder.build()
        assertEquals("Lyrics only, no gain tags", tags.lyrics)
        assertNull(tags.rgTrackGain)
        assertNull(tags.r128Track)
        assertFalse(tags.hasLoudness())
    }

    @Test fun `G07 regression - untagged file yields all-null AudioTags`() {
        val tags = builder.build()
        assertNull(tags.rgTrackGain)
        assertNull(tags.rgTrackPeak)
        assertNull(tags.rgAlbumGain)
        assertNull(tags.rgAlbumPeak)
        assertNull(tags.r128Track)
        assertNull(tags.r128Album)
        assertNull(tags.iTunNorm)
        assertNull(tags.lyrics)
        assertFalse(tags.hasLoudness())
    }

    // ═════════════════════════════════════════════════════════════════════════
    // H. build() and AudioTags.hasLoudness()
    // ═════════════════════════════════════════════════════════════════════════

    @Test fun `H01 build maps all eight fields to AudioTags`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "+1.00 dB"))
        builder.consume(txxx("REPLAYGAIN_TRACK_PEAK", "0.900"))
        builder.consume(txxx("REPLAYGAIN_ALBUM_GAIN", "-0.50 dB"))
        builder.consume(txxx("REPLAYGAIN_ALBUM_PEAK", "0.800"))
        builder.consume(txxx("R128_TRACK_GAIN",       "-650"))
        builder.consume(txxx("R128_ALBUM_GAIN",       "-600"))
        builder.consume(txxx("ITUNNORM",              "000002A6"))
        builder.consume(vorbis("LYRICS",              "Built lyrics"))

        val tags = builder.build()
        assertEquals("+1.00 dB", tags.rgTrackGain)
        assertEquals("0.900",    tags.rgTrackPeak)
        assertEquals("-0.50 dB", tags.rgAlbumGain)
        assertEquals("0.800",    tags.rgAlbumPeak)
        assertEquals("-650",     tags.r128Track)
        assertEquals("-600",     tags.r128Album)
        assertEquals("000002A6", tags.iTunNorm)
        assertEquals("Built lyrics", tags.lyrics)
    }

    @Test fun `H02 hasLoudness true when only rgTrackGain set`() {
        builder.consume(txxx("REPLAYGAIN_TRACK_GAIN", "+1.00 dB"))
        assertTrue(builder.build().hasLoudness())
    }

    @Test fun `H03 hasLoudness true when only r128Track set`() {
        builder.consume(vorbis("R128_TRACK_GAIN", "-700"))
        assertTrue(builder.build().hasLoudness())
    }

    @Test fun `H04 hasLoudness true when only iTunNorm set`() {
        builder.consume(txxx("ITUNNORM", "000002A6"))
        assertTrue(builder.build().hasLoudness())
    }

    @Test fun `H05 hasLoudness false when only rgAlbumGain set`() {
        // rgAlbumGain alone does not satisfy hasLoudness (no track or R128 tag).
        builder.consume(txxx("REPLAYGAIN_ALBUM_GAIN", "+0.50 dB"))
        assertFalse(builder.build().hasLoudness())
    }

    @Test fun `H06 hasLoudness false when only lyrics present`() {
        builder.consume(vorbis("LYRICS", "Lyrics only"))
        assertFalse(builder.build().hasLoudness())
    }

    @Test fun `H07 hasLoudness false when nothing consumed`() {
        assertFalse(builder.build().hasLoudness())
    }

    @Test fun `H08 build is repeatable - same instance can build twice`() {
        builder.consume(vorbis("REPLAYGAIN_TRACK_GAIN", "+1.00 dB"))
        val first  = builder.build()
        val second = builder.build()
        assertEquals(first.rgTrackGain, second.rgTrackGain)
    }
}
