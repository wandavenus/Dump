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
    // FIX Temuan #9 (LOW): `path` was a dead field — the fd-based API
    // (WriteReplayGainTagsFd et al.) ignores it entirely, and the
    // path-based API was removed. Deleted to remove maintenance debt and
    // prevent any future caller from accidentally filling it under the
    // false impression it does something.
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
    // Appended — never renumber the values above, Kotlin/JNI map them
    // positionally. Returned by the fd-based verify step (see below) when a
    // just-written value doesn't read back as expected, or when unrelated
    // metadata (title/artist/album) changed unexpectedly.
    kVerificationFailed = 8,
    // Rollback was required but could not be completed and verified.
    kRollbackFailed      = 9,
};

// Snapshot of the small set of tag *values* relevant to a ReplayGain write —
// the existing loudness fields plus title/artist/album — used only for the
// cheap post-write verification comparison (VerifyReplayGainTagsFd /
// VerifyReplayGainRemovedFd). This is NOT what rollback uses; see
// RegionBackup below for that.
struct TagSnapshot {
    std::optional<std::string> track_gain;
    std::optional<std::string> track_peak;
    std::optional<std::string> album_gain;
    std::optional<std::string> album_peak;
    std::optional<std::string> r128_track;
    std::optional<std::string> r128_album;
    std::optional<std::string> title;
    std::optional<std::string> artist;
    std::optional<std::string> album;
};

// Exact, format-determined backup of the container's metadata region (see
// metadata_region.h) captured immediately before mutating. Arbitrary size —
// never a fixed guess — so it always covers the whole tag block byte-for-
// byte: every field (not just the ones this module knows about), all
// embedded artwork no matter how large or how many pictures, all lyrics,
// etc. Restored via RestoreMetadataRegionFd, which uses the same
// insert-with-replace-count primitive TagLib itself uses, so it correctly
// un-shifts the file regardless of whether the mutation grew or shrank the
// metadata region.
struct RegionBackup {
    std::string bytes;
    // An empty region is valid, so this is the success signal.
    bool captured = false;
};

// ── Scoped-storage-safe fd-based API ─────────────────────────────────────────
//
// On Android 10+, files under shared media storage that this app doesn't own
// generally cannot be opened by raw path for writing — only a
// MediaStore-granted `ParcelFileDescriptor` (via `createWriteRequest` or a
// `RecoverableSecurityException` grant) works. The functions below operate
// on such an already-open, already write-granted file descriptor instead of
// a path, via `TagLib::FileStream(fd, ...)` wrapping a format-specific
// `TagLib::File(IOStream*, ...)` constructor — no whole-file copy is made.
//
// No fixed-size or whole-file backup is taken before mutating. Instead, the
// exact metadata region is determined dynamically per format (see
// metadata_region.h — ID3v2 header size from its own size field, FLAC's
// metadata block chain walked to its last-block flag, Ogg's header packets
// walked page-by-page) and backed up in full, however large that turns out
// to be (arbitrarily large embedded art, lyrics, multi-block FLAC pictures,
// etc. are all covered — nothing is truncated or estimated). If the region
// can't be determined with certainty, the write is aborted before anything
// is touched — see DetermineMetadataRegionSize's contract.
//
//   1. WriteReplayGainTagsFd/RemoveReplayGainTagsFd first determine the
//      exact metadata region size and copy exactly those bytes into
//      `*out_region` (RegionBackup), and separately capture a small
//      `TagSnapshot` of the prior values (for the cheap post-write value
//      comparison in step 3) — then mutate + save via TagLib.
//   2. The caller (Kotlin) closes the write fd, fsyncs, and reopens a fresh
//      READ-ONLY fd from MediaStore.
//   3. VerifyReplayGainTagsFd re-reads that fresh fd and confirms the new
//      values match what was requested AND that title/artist/album still
//      match the pre-mutation snapshot. On mismatch, returns
//      kVerificationFailed instead of the caller reporting false success.
//   4. On verification failure, the caller reopens a fresh WRITE fd and
//      calls RestoreMetadataRegionFd, which re-determines the (now
//      possibly different-sized, post-mutation) region size and replaces
//      exactly that many bytes with the originally-backed-up region via
//      the same insert-with-replace-count primitive TagLib itself uses —
//      so restoration is byte-exact and correctly un-shifts the file
//      whether the failed mutation grew or shrank the metadata region.
//
// Residual risk (explicitly accepted, not hidden): if the process is killed
// mid-`save()` — during the actual TagLib rewrite, before step 2/3/4 can
// ever run — the file can be left corrupted with no way to recover, since
// there is no atomic swap available for `content://`-backed fds. Reliably
// surviving a kill mid-write would require a full-file copy (or an atomic
// filesystem-level swap, unavailable here), which was ruled out as too
// costly for arbitrary-size media files. This is the unavoidable trade-off
// of avoiding both a full-file copy and MANAGE_EXTERNAL_STORAGE; it matches
// what any scoped-storage-compliant tag editor on Android accepts. Once
// save() itself completes (successfully or not) and control returns to
// Kotlin, every subsequent step is covered by the exact-region backup
// above.
//
// Threading: same rule as the path-based API — never call concurrently on
// descriptors referring to the same underlying file.

// Determines the exact metadata region (see metadata_region.h), backs it up
// in full into `*out_region`, captures the cheap value-level `*out_prior`
// snapshot, then mutates the tags reachable via `fd` (already open for
// writing) according to `req` (req.path is ignored; req.format selects the
// container) and saves. Does NOT close `fd`.
//
// Returns kUnknown (without touching the file) if the metadata region can't
// be determined with certainty — see DetermineMetadataRegionSize.
WriteResult WriteReplayGainTagsFd(int fd, const WriteRequest& req, TagSnapshot* out_prior,
                                   RegionBackup* out_region);

// Same contract as WriteReplayGainTagsFd, but strips REPLAYGAIN_*/R128_*/
// ITUNNORM fields instead of writing new ones.
WriteResult RemoveReplayGainTagsFd(int fd, TagFormat format, TagSnapshot* out_prior,
                                    RegionBackup* out_region);

// Re-reads `fd` (freshly opened, read-only is fine) and confirms the
// loudness fields match `req` and title/artist/album match
// `prior_sentinel`. Returns kOk on match, kVerificationFailed on any
// mismatch.
WriteResult VerifyReplayGainTagsFd(int fd, const WriteRequest& req,
                                    const TagSnapshot& prior_sentinel);

// Re-reads `fd` and confirms every REPLAYGAIN_*/R128_* field is now absent
// and title/artist/album match `prior_sentinel`. Used after
// RemoveReplayGainTagsFd. Returns kOk on match, kVerificationFailed
// otherwise.
WriteResult VerifyReplayGainRemovedFd(int fd, TagFormat format,
                                       const TagSnapshot& prior_sentinel);

// Re-reads `fd` and confirms that the observable tag values match the snapshot
// captured immediately before the mutation. Used to prove rollback succeeded.
WriteResult VerifyReplayGainRestoredFd(int fd, TagFormat format,
                                       const TagSnapshot& prior);

// Byte-exact rollback: re-determines the CURRENT (post-mutation) metadata
// region size via `fd` (already open for writing) and replaces exactly
// those bytes with `backup.bytes`, using the same insert-with-replace-count
// primitive TagLib itself uses for tag resizes — so this is correct
// regardless of whether the failed write grew or shrank the region.
//
// Returns kUnknown (without touching the file) if the CURRENT region can't
// be determined with certainty, e.g. because the failed write left the
// container structurally broken in a way this module can't safely reason
// about; the caller should surface this as a distinct, more severe failure
// than a normal verification mismatch.
WriteResult RestoreMetadataRegionFd(int fd, TagFormat format, const RegionBackup& backup);

}  // namespace replaygain

#endif  // REPLAYGAIN_TAG_WRITER_H
