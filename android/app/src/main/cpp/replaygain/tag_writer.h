#ifndef REPLAYGAIN_TAG_WRITER_H
#define REPLAYGAIN_TAG_WRITER_H

#include <optional>
#include <string>

namespace replaygain {

// Which container/tag format to target. Determined by the Kotlin caller from
// the file extension (cheap, reliable — TagLib itself also sniffs content,
// but we need to know up front which tag flavor to write:
// ID3v2 TXXX vs. Xiph/Vorbis comment vs. Opus-specific R128 fields).
enum class TagFormat : int32_t {
    kMp3      = 0,  // ID3v2 TXXX frames
    kFlac     = 1,  // Xiph/Vorbis comment block (inside FLAC container)
    kOggVorbis = 2, // Xiph/Vorbis comment (Ogg Vorbis stream)
    kOggOpus   = 3, // Xiph/Vorbis comment + R128_TRACK_GAIN/R128_ALBUM_GAIN
};

struct WriteRequest {
    std::string path;
    TagFormat   format = TagFormat::kMp3;

    // Track-level, always required.
    double track_gain_db = 0.0;
    double track_peak_linear = 0.0;   // 0.0..~1.0+ (true peak can exceed 1.0)

    // Album-level, optional — absent when scanning a single track outside
    // an album/batch context.
    bool   has_album = false;
    double album_gain_db = 0.0;
    double album_peak_linear = 0.0;

    // Pre-quantized R128 fields (Opus only). Computed by the caller via
    // LufsToR128Q7_8() so tag_writer.cpp doesn't need to depend on the
    // analyzer's LUFS reference-level math.
    int32_t r128_track_q7_8 = 0;
    bool    has_r128_album = false;
    int32_t r128_album_q7_8 = 0;
};

enum class WriteResult : int32_t {
    kOk                 = 0,
    kUnsupportedFormat  = 1,
    kCorruptedFile      = 2,
    kWriteFailure       = 3,
    kPermissionFailure  = 4,
    kFileNotFound       = 5,
    kInvalidArgument    = 6,
    kUnknown            = 7,
};

// Writes ReplayGain (and, for Opus, R128_*) tags into the file described by
// `req`, preserving every other existing tag field (title, artist, album,
// cover art, lyrics, ISRC, disc/track number, comments, etc.) byte-for-byte
// where TagLib's save() doesn't need to touch them. TagLib rewrites only the
// tag/metadata region of the file — the encoded audio stream is never
// touched, so this is a metadata-only operation with no re-encoding.
//
// Threading: safe to call from any thread, but never call it twice
// concurrently on the SAME path — the Kotlin-side executor must serialize
// writes per file (reads are fine to overlap).
WriteResult WriteReplayGainTags(const WriteRequest& req);

// Strips REPLAYGAIN_*, R128_*, and iTunNORM tag fields, leaving all other
// metadata (title/artist/album/art/lyrics/etc.) intact. Detects format from
// the file extension internally, same as WriteReplayGainTags.
WriteResult RemoveReplayGainTags(const std::string& path);

}  // namespace replaygain

#endif  // REPLAYGAIN_TAG_WRITER_H
