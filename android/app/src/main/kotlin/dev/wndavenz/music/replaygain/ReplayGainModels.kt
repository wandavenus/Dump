package dev.wndavenz.music.replaygain

/**
 * Stable error taxonomy returned to Flutter for every native ReplayGain
 * operation. Integer ordinals MUST stay in sync with
 * `replaygain::ErrorCode` / `replaygain::WriteResult` in
 * `src/main/cpp/replaygain/jni_common.h` and `tag_writer.h` — the native
 * side returns these as plain ints, decoded positionally here.
 */
enum class ReplayGainError {
    NONE,
    UNSUPPORTED_FORMAT,
    CORRUPTED_FILE,
    WRITE_FAILURE,
    PERMISSION_FAILURE,
    FILE_NOT_FOUND,
    INVALID_ARGUMENT,
    UNKNOWN,
    // ── Appended native ordinals ──────────────────────────────────────────────
    // Values below are positionally mapped from `replaygain::WriteResult`/
    // `ErrorCode` ordinals. Never reorder; never insert before this line.
    // New native error codes must be appended HERE (before VERIFICATION_FAILED)
    // to keep the Kotlin ordinals in sync with the C++ enum. K-07.
    VERIFICATION_FAILED,
    // ── Kotlin-only outcomes ──────────────────────────────────────────────────
    // These are never passed to fromNative(); they have no native ordinal.
    // Safe insertion point for future Kotlin-only errors: append after this line.
    // WRITE_ACCESS_DENIED: the user declined (or the system denied) the
    // MediaStore write-grant request for this file — see MediaStoreWriteGate.
    WRITE_ACCESS_DENIED;

    companion object {
        fun fromNative(code: Int): ReplayGainError =
            values().getOrElse(code) { UNKNOWN }
    }
}

/** Result of analyzing a single track's loudness via libebur128. */
data class LoudnessResult(
    val integratedLufs: Double,
    val loudnessRangeLu: Double,
    val truePeakDbtp: Double,
    val samplePeakDbfs: Double,
    val recommendedGainDb: Double,
    val valid: Boolean,
)

/** Outcome of a [ReplayGainService.scanTrack] call. */
sealed class ScanOutcome {
    data class Success(val result: LoudnessResult) : ScanOutcome()
    data class Failure(val error: ReplayGainError, val message: String?) : ScanOutcome()
}

/** Outcome of a [ReplayGainService.scanAlbum] call. */
data class AlbumScanResult(
    val trackResults: Map<String, LoudnessResult>,  // path -> per-track result
    val albumGainDb: Double,
    val albumPeakLinear: Double,
    val albumIntegratedLufs: Double,
    val failedPaths: List<String>,
)

/** Which tag flavor to write, mirrors `replaygain::TagFormat` in tag_writer.h. */
enum class TagFormat(val nativeValue: Int) {
    MP3(0),
    FLAC(1),
    OGG_VORBIS(2),
    OGG_OPUS(3);

    companion object {
        /**
         * Detects tag format from the file extension. Returns null for
         * formats we don't support writing to (e.g. M4A/AAC — those use
         * MP4 atoms, which are handled read-only via ExoMetadataReader and
         * are out of scope for this write-capable module: TagLib's MP4
         * writer support was intentionally disabled in CMakeLists.txt to
         * keep the native binary smaller, since ExoMetadataReader already
         * covers M4A reads and iTunNORM has no well-defined RG2.0 write
         * convention across players).
         */
        fun fromPath(path: String): TagFormat? {
            val ext = path.substringAfterLast('.', "").lowercase()
            return when (ext) {
                "mp3" -> MP3
                "flac" -> FLAC
                "ogg", "oga" -> OGG_VORBIS
                "opus" -> OGG_OPUS
                else -> null
            }
        }
    }
}

/** Live progress for a batch scan (single track or full album/library). */
data class ScanProgress(
    val currentPath: String,
    val fraction: Float,  // 0.0..1.0
)

/**
 * Kotlin mirror of `replaygain::TagSnapshot` (tag_writer.h) — a handful of
 * tag *values* (not raw bytes) used only for the cheap post-write value
 * comparison. Order matches `kSnapshotFieldCount`'s packing in
 * replaygain_jni.cpp: [trackGain, trackPeak, albumGain, albumPeak,
 * r128Track, r128Album, title, artist, album].
 */
data class TagSnapshot(
    val trackGain: String?,
    val trackPeak: String?,
    val albumGain: String?,
    val albumPeak: String?,
    val r128Track: String?,
    val r128Album: String?,
    val title: String?,
    val artist: String?,
    val album: String?,
) {
    fun toArray(): Array<String?> =
        arrayOf(trackGain, trackPeak, albumGain, albumPeak, r128Track, r128Album, title, artist, album)

    companion object {
        fun fromArray(arr: Array<String?>?): TagSnapshot {
            val a = arr ?: arrayOfNulls(9)
            return TagSnapshot(
                trackGain = a.getOrNull(0), trackPeak = a.getOrNull(1),
                albumGain = a.getOrNull(2), albumPeak = a.getOrNull(3),
                r128Track = a.getOrNull(4), r128Album = a.getOrNull(5),
                title = a.getOrNull(6), artist = a.getOrNull(7), album = a.getOrNull(8),
            )
        }
    }
}

/**
 * Result envelope for a native fd-based write/remove call — mirrors the
 * `Object[3]` `[resultCode, priorSnapshot, regionBytes]` packed by
 * `PackWriteEnvelope` in replaygain_jni.cpp.
 */
data class FdWriteOutcome(
    val error: ReplayGainError,
    val priorSnapshot: TagSnapshot,
    val regionBackup: ByteArray?,
)
