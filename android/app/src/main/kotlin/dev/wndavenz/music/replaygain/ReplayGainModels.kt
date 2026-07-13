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
    UNKNOWN;

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
