#include "tag_writer.h"

#include "metadata_region.h"

#include <unistd.h>

#include <algorithm>
#include <cstdio>
#include <cstring>

#include <fileref.h>
#include <flacfile.h>
#include <flacproperties.h>
#include <id3v2tag.h>
#include <mpegfile.h>
#include <opusfile.h>
#include <opusproperties.h>
#include <tag.h>
#include <textidentificationframe.h>
#include <tfile.h>
#include <tfilestream.h>
#include <tstring.h>
#include <vorbisfile.h>
#include <vorbisproperties.h>
#include <xiphcomment.h>

namespace replaygain {

namespace {

// ── Value formatting ─────────────────────────────────────────────────────────
// REPLAYGAIN_*_GAIN is conventionally written as e.g. "-3.45 dB" (with unit
// suffix and sign), REPLAYGAIN_*_PEAK as a bare linear float "0.987654".
// This mirrors what foobar2000 / mp3gain / other RG2.0 writers emit, which is
// what our own TagBuilder.kt reader already expects on the parse side.

std::string FormatGainDb(double gain_db) {
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%+.2f dB", gain_db);
    return std::string(buf);
}

std::string FormatPeak(double peak_linear) {
    char buf[32];
    // Clamp negative/garbage peaks to 0; do not clamp above 1.0 — true peak
    // can legitimately exceed 0 dBFS (inter-sample peaks), and RG2.0 readers
    // expect the raw linear value.
    std::snprintf(buf, sizeof(buf), "%.6f", std::max(0.0, peak_linear));
    return std::string(buf);
}

// ── ID3v2 (MP3) ───────────────────────────────────────────────────────────────

// Removes ALL existing TXXX frames matching `description` (not just the
// first). A prior version of this code broke after the first match, so a
// file that had already accumulated duplicate TXXX frames — from an earlier
// bug, or from another tool writing the same description twice — would keep
// every duplicate beyond the first forever, since re-scans only ever removed
// one of them before adding a new one on top.
void RemoveTxxx(TagLib::ID3v2::Tag* tag, const char* description) {
    const TagLib::ID3v2::FrameList& frames = tag->frameList("TXXX");
    TagLib::ID3v2::FrameList to_remove;
    for (auto it = frames.begin(); it != frames.end(); ++it) {
        auto* txxx = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame*>(*it);
        if (txxx != nullptr &&
            txxx->description() == TagLib::String(description, TagLib::String::UTF8)) {
            to_remove.append(*it);
        }
    }
    for (auto it = to_remove.begin(); it != to_remove.end(); ++it) {
        tag->removeFrame(*it);
    }
}

// Reads the current value of a TXXX frame by description, or nullopt if
// absent. Mirrors RemoveTxxx/SetTxxx's UTF8-description matching.
std::optional<std::string> ReadTxxx(TagLib::ID3v2::Tag* tag, const char* description) {
    auto* frame = TagLib::ID3v2::UserTextIdentificationFrame::find(
        tag, TagLib::String(description, TagLib::String::UTF8));
    if (frame == nullptr) return std::nullopt;
    const TagLib::StringList fields = frame->fieldList();
    // fieldList()[0] is the description itself; the value lives at [1].
    if (fields.size() < 2) return std::string();
    return fields[1].to8Bit(true);
}

void SetTxxx(TagLib::ID3v2::Tag* tag, const char* description, const std::string& value) {
    // Remove every existing TXXX frame with this description first (see
    // RemoveTxxx doc above) so writes are idempotent and never accumulate
    // duplicate frames no matter how many times a track is re-scanned.
    RemoveTxxx(tag, description);
    auto* frame = new TagLib::ID3v2::UserTextIdentificationFrame(TagLib::String::UTF8);
    frame->setDescription(TagLib::String(description, TagLib::String::UTF8));
    frame->setText(TagLib::String(value, TagLib::String::UTF8));
    tag->addFrame(frame);  // tag takes ownership
}

// ── Xiph/Vorbis comment (FLAC / Ogg Vorbis / Ogg Opus) ───────────────────────

void SetXiphField(TagLib::Ogg::XiphComment* comment, const char* key, const std::string& value) {
    comment->addField(TagLib::String(key, TagLib::String::UTF8),
                       TagLib::String(value, TagLib::String::UTF8),
                       true);  // replace = true: dedupes automatically
}

void RemoveXiphField(TagLib::Ogg::XiphComment* comment, const char* key) {
    comment->removeFields(TagLib::String(key, TagLib::String::UTF8));
}

std::optional<std::string> ReadXiphField(TagLib::Ogg::XiphComment* comment, const char* key) {
    const TagLib::StringList values =
        comment->fieldListMap()[TagLib::String(key, TagLib::String::UTF8)];
    if (values.isEmpty()) return std::nullopt;
    return values.front().to8Bit(true);
}

// ── Sentinel fields (title/artist/album) shared by every tag flavor ─────────
// TagLib::Tag (the common base of ID3v2::Tag and Ogg::XiphComment) exposes
// title()/artist()/album() uniformly, so this one helper covers all formats.

std::optional<std::string> ToOpt(const TagLib::String& s) {
    if (s.isEmpty()) return std::nullopt;
    return s.to8Bit(true);
}

void CaptureSentinel(TagLib::Tag* tag, TagSnapshot* out) {
    if (out == nullptr || tag == nullptr) return;
    out->title  = ToOpt(tag->title());
    out->artist = ToOpt(tag->artist());
    out->album  = ToOpt(tag->album());
}

bool SentinelMatches(TagLib::Tag* tag, const TagSnapshot& prior) {
    if (tag == nullptr) return false;
    return ToOpt(tag->title()) == prior.title &&
           ToOpt(tag->artist()) == prior.artist &&
           ToOpt(tag->album()) == prior.album;
}

// Formats a request field the same way SetTxxx/SetXiphField would, so a
// freshly-read value can be compared textually against what was requested.
bool GainMatches(const std::optional<std::string>& actual, double expected_gain_db) {
    return actual.has_value() && *actual == FormatGainDb(expected_gain_db);
}
bool PeakMatches(const std::optional<std::string>& actual, double expected_peak) {
    return actual.has_value() && *actual == FormatPeak(expected_peak);
}
bool R128Matches(const std::optional<std::string>& actual, int32_t expected) {
    return actual.has_value() && *actual == std::to_string(expected);
}

void ApplyReplayGainFields(TagLib::Ogg::XiphComment* comment, const WriteRequest& req,
                            bool is_opus) {
    SetXiphField(comment, "REPLAYGAIN_TRACK_GAIN", FormatGainDb(req.track_gain_db));
    SetXiphField(comment, "REPLAYGAIN_TRACK_PEAK", FormatPeak(req.track_peak_linear));
    if (req.has_album) {
        SetXiphField(comment, "REPLAYGAIN_ALBUM_GAIN", FormatGainDb(req.album_gain_db));
        SetXiphField(comment, "REPLAYGAIN_ALBUM_PEAK", FormatPeak(req.album_peak_linear));
    }
    if (is_opus) {
        // Opus RFC/xiph spec: R128_TRACK_GAIN / R128_ALBUM_GAIN are signed
        // Q7.8 fixed-point integers (256 = 1 dB), referenced to -23 LUFS,
        // stored as plain decimal-integer text in the Vorbis comment.
        SetXiphField(comment, "R128_TRACK_GAIN", std::to_string(req.r128_track_q7_8));
        if (req.has_r128_album) {
            SetXiphField(comment, "R128_ALBUM_GAIN", std::to_string(req.r128_album_q7_8));
        }
    }
}

void RemoveReplayGainFields(TagLib::Ogg::XiphComment* comment) {
    for (const char* key : {"REPLAYGAIN_TRACK_GAIN", "REPLAYGAIN_TRACK_PEAK",
                              "REPLAYGAIN_ALBUM_GAIN", "REPLAYGAIN_ALBUM_PEAK",
                              "R128_TRACK_GAIN", "R128_ALBUM_GAIN"}) {
        RemoveXiphField(comment, key);
    }
}

// ── fd-based snapshot capture helpers ────────────────────────────────────────

void SnapshotMp3(TagLib::ID3v2::Tag* tag, TagSnapshot* out) {
    out->track_gain = ReadTxxx(tag, "REPLAYGAIN_TRACK_GAIN");
    out->track_peak = ReadTxxx(tag, "REPLAYGAIN_TRACK_PEAK");
    out->album_gain = ReadTxxx(tag, "REPLAYGAIN_ALBUM_GAIN");
    out->album_peak = ReadTxxx(tag, "REPLAYGAIN_ALBUM_PEAK");
    out->r128_track = ReadTxxx(tag, "R128_TRACK_GAIN");
    out->r128_album = ReadTxxx(tag, "R128_ALBUM_GAIN");
    CaptureSentinel(tag, out);
}

void SnapshotXiph(TagLib::Ogg::XiphComment* comment, TagSnapshot* out) {
    out->track_gain = ReadXiphField(comment, "REPLAYGAIN_TRACK_GAIN");
    out->track_peak = ReadXiphField(comment, "REPLAYGAIN_TRACK_PEAK");
    out->album_gain = ReadXiphField(comment, "REPLAYGAIN_ALBUM_GAIN");
    out->album_peak = ReadXiphField(comment, "REPLAYGAIN_ALBUM_PEAK");
    out->r128_track = ReadXiphField(comment, "R128_TRACK_GAIN");
    out->r128_album = ReadXiphField(comment, "R128_ALBUM_GAIN");
    CaptureSentinel(comment, out);
}

// Backs up the exact metadata region for `format` via `fd` into
// `*out_region`. Returns kOk on success, kUnknown if the region can't be
// determined safely (caller must abort without touching the file), or
// kWriteFailure on an unexpected short read.
WriteResult BackupRegion(int fd, TagFormat format, RegionBackup* out_region) {
    const auto size = DetermineMetadataRegionSize(fd, format);
    if (!size.has_value()) return WriteResult::kUnknown;
    if (!ReadRegion(fd, *size, &out_region->bytes)) return WriteResult::kWriteFailure;
    return WriteResult::kOk;
}

// RAII holder for a `dup()`'d fd used purely to fsync the file's data to
// storage after a TagLib save/insert. A dup'd fd shares the same underlying
// open-file-description (and therefore the same fsync-able inode data) as
// the original, but has its own independent lifetime — so it stays valid
// and fsync-able even after the original `fd` is closed internally by
// TagLib::FileStream's destructor (which calls fclose() on the FILE* it
// fdopen()'d from the original fd). Without this, there would be no way to
// force a flush to disk before control returns to Kotlin for the
// close→reopen→verify step, widening the crash window.
class FsyncGuard {
public:
    // FIX Temuan #4 (LOW): log dup() failure so rare hardware-level EMFILE /
    // ENFILE errors on MIUI are visible in logcat (stderr → logcat on Android).
    explicit FsyncGuard(int original_fd) : dup_fd_(::dup(original_fd)) {
        if (dup_fd_ < 0) {
            std::fprintf(stderr,
                         "[ReplayGainTagWriter] FsyncGuard: dup(%d) failed — "
                         "fsync and post-write verify will be skipped\n",
                         original_fd);
        }
    }
    ~FsyncGuard() {
        if (dup_fd_ >= 0) ::close(dup_fd_);
    }
    // Flushes pending writes to storage. Best-effort: a failure here doesn't
    // change the overall WriteResult (the tag data is still correct in the
    // page cache and will reach disk eventually).
    void Sync() {
        if (dup_fd_ >= 0) ::fsync(dup_fd_);
    }
    // FIX Temuan #2 (MEDIUM): expose dup'd fd for post-insert header check.
    // Returns -1 if dup() failed at construction time.
    int Fd() const { return dup_fd_; }

private:
    int dup_fd_;
};

}  // namespace

// ── fd-based write / remove / verify / restore ───────────────────────────────

WriteResult WriteReplayGainTagsFd(int fd, const WriteRequest& req, TagSnapshot* out_prior,
                                   RegionBackup* out_region) {
    if (fd < 0) return WriteResult::kInvalidArgument;
    if (out_region != nullptr) {
        const WriteResult backup_result = BackupRegion(fd, req.format, out_region);
        if (backup_result != WriteResult::kOk) {
            ::close(fd);  // FileStream not yet created — we still own this fd
            return backup_result;
        }
    }

    FsyncGuard fsync_guard(fd);
    TagLib::FileStream stream(fd, /*openReadOnly=*/false);
    if (!stream.isOpen()) {
        // fdopen() failed — TagLib did not take ownership of fd.
        // FsyncGuard holds dup(fd), not fd itself; closing fd here is safe.
        ::close(fd);
        return WriteResult::kPermissionFailure;
    }

    switch (req.format) {
        case TagFormat::kMp3: {
            TagLib::MPEG::File file(&stream, /*readProperties=*/true);
            if (!file.isValid()) return WriteResult::kCorruptedFile;
            TagLib::ID3v2::Tag* tag = file.ID3v2Tag(true);
            if (tag == nullptr) return WriteResult::kUnsupportedFormat;
            if (out_prior != nullptr) SnapshotMp3(tag, out_prior);
            SetTxxx(tag, "REPLAYGAIN_TRACK_GAIN", FormatGainDb(req.track_gain_db));
            SetTxxx(tag, "REPLAYGAIN_TRACK_PEAK", FormatPeak(req.track_peak_linear));
            if (req.has_album) {
                SetTxxx(tag, "REPLAYGAIN_ALBUM_GAIN", FormatGainDb(req.album_gain_db));
                SetTxxx(tag, "REPLAYGAIN_ALBUM_PEAK", FormatPeak(req.album_peak_linear));
            }
            if (!file.save()) return WriteResult::kWriteFailure;
            fsync_guard.Sync();
            return WriteResult::kOk;
        }
        case TagFormat::kFlac: {
            TagLib::FLAC::File file(&stream, /*readProperties=*/true);
            if (!file.isValid()) return WriteResult::kCorruptedFile;
            TagLib::Ogg::XiphComment* comment = file.xiphComment(true);
            if (comment == nullptr) return WriteResult::kUnsupportedFormat;
            if (out_prior != nullptr) SnapshotXiph(comment, out_prior);
            ApplyReplayGainFields(comment, req, /*is_opus=*/false);
            if (!file.save()) return WriteResult::kWriteFailure;
            fsync_guard.Sync();
            return WriteResult::kOk;
        }
        case TagFormat::kOggVorbis: {
            TagLib::Ogg::Vorbis::File file(&stream, /*readProperties=*/true);
            if (!file.isValid()) return WriteResult::kCorruptedFile;
            TagLib::Ogg::XiphComment* comment = file.tag();
            if (comment == nullptr) return WriteResult::kUnsupportedFormat;
            if (out_prior != nullptr) SnapshotXiph(comment, out_prior);
            ApplyReplayGainFields(comment, req, /*is_opus=*/false);
            if (!file.save()) return WriteResult::kWriteFailure;
            fsync_guard.Sync();
            return WriteResult::kOk;
        }
        case TagFormat::kOggOpus: {
            TagLib::Ogg::Opus::File file(&stream, /*readProperties=*/true);
            if (!file.isValid()) return WriteResult::kCorruptedFile;
            TagLib::Ogg::XiphComment* comment = file.tag();
            if (comment == nullptr) return WriteResult::kUnsupportedFormat;
            if (out_prior != nullptr) SnapshotXiph(comment, out_prior);
            ApplyReplayGainFields(comment, req, /*is_opus=*/true);
            if (!file.save()) return WriteResult::kWriteFailure;
            fsync_guard.Sync();
            return WriteResult::kOk;
        }
    }
    return WriteResult::kUnsupportedFormat;
}

WriteResult RemoveReplayGainTagsFd(int fd, TagFormat format, TagSnapshot* out_prior,
                                    RegionBackup* out_region) {
    if (fd < 0) return WriteResult::kInvalidArgument;
    if (out_region != nullptr) {
        const WriteResult backup_result = BackupRegion(fd, format, out_region);
        if (backup_result != WriteResult::kOk) {
            ::close(fd);  // FileStream not yet created — we still own this fd
            return backup_result;
        }
    }

    FsyncGuard fsync_guard(fd);
    TagLib::FileStream stream(fd, /*openReadOnly=*/false);
    if (!stream.isOpen()) {
        // fdopen() failed — TagLib did not take ownership of fd.
        // FsyncGuard holds dup(fd), not fd itself; closing fd here is safe.
        ::close(fd);
        return WriteResult::kPermissionFailure;
    }

    switch (format) {
        case TagFormat::kMp3: {
            TagLib::MPEG::File file(&stream, /*readProperties=*/true);
            if (!file.isValid()) return WriteResult::kCorruptedFile;
            TagLib::ID3v2::Tag* tag = file.ID3v2Tag(false);
            if (tag == nullptr) {
                if (out_prior != nullptr) *out_prior = TagSnapshot{};
                return WriteResult::kOk;  // nothing to remove
            }
            if (out_prior != nullptr) SnapshotMp3(tag, out_prior);
            for (const char* desc : {"REPLAYGAIN_TRACK_GAIN", "REPLAYGAIN_TRACK_PEAK",
                                      "REPLAYGAIN_ALBUM_GAIN", "REPLAYGAIN_ALBUM_PEAK",
                                      "R128_TRACK_GAIN", "R128_ALBUM_GAIN",
                                      "ITUNNORM", "ITUN NORM"}) {
                RemoveTxxx(tag, desc);
            }
            if (!file.save()) return WriteResult::kWriteFailure;
            fsync_guard.Sync();
            return WriteResult::kOk;
        }
        case TagFormat::kFlac: {
            TagLib::FLAC::File file(&stream, /*readProperties=*/true);
            if (!file.isValid()) return WriteResult::kCorruptedFile;
            TagLib::Ogg::XiphComment* comment = file.xiphComment(false);
            if (comment == nullptr) {
                if (out_prior != nullptr) *out_prior = TagSnapshot{};
                return WriteResult::kOk;
            }
            if (out_prior != nullptr) SnapshotXiph(comment, out_prior);
            RemoveReplayGainFields(comment);
            if (!file.save()) return WriteResult::kWriteFailure;
            fsync_guard.Sync();
            return WriteResult::kOk;
        }
        case TagFormat::kOggVorbis: {
            TagLib::Ogg::Vorbis::File file(&stream, /*readProperties=*/true);
            if (!file.isValid()) return WriteResult::kCorruptedFile;
            TagLib::Ogg::XiphComment* comment = file.tag();
            if (comment == nullptr) {
                if (out_prior != nullptr) *out_prior = TagSnapshot{};
                return WriteResult::kOk;
            }
            if (out_prior != nullptr) SnapshotXiph(comment, out_prior);
            RemoveReplayGainFields(comment);
            if (!file.save()) return WriteResult::kWriteFailure;
            fsync_guard.Sync();
            return WriteResult::kOk;
        }
        case TagFormat::kOggOpus: {
            TagLib::Ogg::Opus::File file(&stream, /*readProperties=*/true);
            if (!file.isValid()) return WriteResult::kCorruptedFile;
            TagLib::Ogg::XiphComment* comment = file.tag();
            if (comment == nullptr) {
                if (out_prior != nullptr) *out_prior = TagSnapshot{};
                return WriteResult::kOk;
            }
            if (out_prior != nullptr) SnapshotXiph(comment, out_prior);
            RemoveReplayGainFields(comment);
            if (!file.save()) return WriteResult::kWriteFailure;
            fsync_guard.Sync();
            return WriteResult::kOk;
        }
    }
    return WriteResult::kUnsupportedFormat;
}

namespace {

// Reads back the loudness fields + sentinel for `format` via an
// already-open (read is enough) `fd`, without mutating anything.
WriteResult ReadBackFd(int fd, TagFormat format, TagSnapshot* out) {
    TagLib::FileStream stream(fd, /*openReadOnly=*/true);
    if (!stream.isOpen()) {
        ::close(fd);  // fdopen() failed — TagLib did not take ownership of fd.
        return WriteResult::kPermissionFailure;
    }

    switch (format) {
        case TagFormat::kMp3: {
            TagLib::MPEG::File file(&stream, /*readProperties=*/false);
            if (!file.isValid()) return WriteResult::kCorruptedFile;
            TagLib::ID3v2::Tag* tag = file.ID3v2Tag(false);
            if (tag == nullptr) {
                *out = TagSnapshot{};
                return WriteResult::kOk;
            }
            SnapshotMp3(tag, out);
            return WriteResult::kOk;
        }
        case TagFormat::kFlac: {
            TagLib::FLAC::File file(&stream, /*readProperties=*/false);
            if (!file.isValid()) return WriteResult::kCorruptedFile;
            TagLib::Ogg::XiphComment* comment = file.xiphComment(false);
            if (comment == nullptr) {
                *out = TagSnapshot{};
                return WriteResult::kOk;
            }
            SnapshotXiph(comment, out);
            return WriteResult::kOk;
        }
        case TagFormat::kOggVorbis: {
            TagLib::Ogg::Vorbis::File file(&stream, /*readProperties=*/false);
            if (!file.isValid()) return WriteResult::kCorruptedFile;
            TagLib::Ogg::XiphComment* comment = file.tag();
            if (comment == nullptr) {
                *out = TagSnapshot{};
                return WriteResult::kOk;
            }
            SnapshotXiph(comment, out);
            return WriteResult::kOk;
        }
        case TagFormat::kOggOpus: {
            TagLib::Ogg::Opus::File file(&stream, /*readProperties=*/false);
            if (!file.isValid()) return WriteResult::kCorruptedFile;
            TagLib::Ogg::XiphComment* comment = file.tag();
            if (comment == nullptr) {
                *out = TagSnapshot{};
                return WriteResult::kOk;
            }
            SnapshotXiph(comment, out);
            return WriteResult::kOk;
        }
    }
    return WriteResult::kUnsupportedFormat;
}

}  // namespace

WriteResult VerifyReplayGainTagsFd(int fd, const WriteRequest& req,
                                    const TagSnapshot& prior_sentinel) {
    if (fd < 0) return WriteResult::kInvalidArgument;
    TagSnapshot actual;
    const WriteResult read_result = ReadBackFd(fd, req.format, &actual);
    if (read_result != WriteResult::kOk) return read_result;

    if (!GainMatches(actual.track_gain, req.track_gain_db)) return WriteResult::kVerificationFailed;
    if (!PeakMatches(actual.track_peak, req.track_peak_linear)) return WriteResult::kVerificationFailed;
    if (req.has_album) {
        if (!GainMatches(actual.album_gain, req.album_gain_db)) return WriteResult::kVerificationFailed;
        if (!PeakMatches(actual.album_peak, req.album_peak_linear)) return WriteResult::kVerificationFailed;
    }
    if (req.format == TagFormat::kOggOpus) {
        if (!R128Matches(actual.r128_track, req.r128_track_q7_8)) return WriteResult::kVerificationFailed;
        if (req.has_r128_album && !R128Matches(actual.r128_album, req.r128_album_q7_8)) {
            return WriteResult::kVerificationFailed;
        }
    }
    if (actual.title != prior_sentinel.title || actual.artist != prior_sentinel.artist ||
        actual.album != prior_sentinel.album) {
        return WriteResult::kVerificationFailed;
    }
    return WriteResult::kOk;
}

WriteResult VerifyReplayGainRemovedFd(int fd, TagFormat format,
                                       const TagSnapshot& prior_sentinel) {
    if (fd < 0) return WriteResult::kInvalidArgument;
    TagSnapshot actual;
    const WriteResult read_result = ReadBackFd(fd, format, &actual);
    if (read_result != WriteResult::kOk) return read_result;

    if (actual.track_gain.has_value() || actual.track_peak.has_value() ||
        actual.album_gain.has_value() || actual.album_peak.has_value() ||
        actual.r128_track.has_value() || actual.r128_album.has_value()) {
        return WriteResult::kVerificationFailed;
    }
    if (actual.title != prior_sentinel.title || actual.artist != prior_sentinel.artist ||
        actual.album != prior_sentinel.album) {
        return WriteResult::kVerificationFailed;
    }
    return WriteResult::kOk;
}

WriteResult RestoreMetadataRegionFd(int fd, TagFormat format, const RegionBackup& backup) {
    if (fd < 0) return WriteResult::kInvalidArgument;
    const auto current_size = DetermineMetadataRegionSize(fd, format);
    if (!current_size.has_value()) {
        ::close(fd);  // FileStream not yet created — we still own this fd
        return WriteResult::kUnknown;
    }

    FsyncGuard fsync_guard(fd);
    TagLib::FileStream stream(fd, /*openReadOnly=*/false);
    if (!stream.isOpen()) {
        // fdopen() failed — TagLib did not take ownership of fd.
        // FsyncGuard holds dup(fd), not fd itself; closing fd here is safe.
        ::close(fd);
        return WriteResult::kPermissionFailure;
    }

    const TagLib::ByteVector data(backup.bytes.data(),
                                  static_cast<unsigned int>(backup.bytes.size()));
    // Replaces exactly `current_size` bytes at the start of the file with
    // the originally-backed-up region — the same primitive TagLib's own
    // save() uses internally to grow/shrink the tag block, so this
    // correctly un-shifts the audio data regardless of which direction the
    // failed write resized things.
    stream.insert(data, /*start=*/0, /*replace=*/static_cast<size_t>(*current_size));

    // FIX Temuan #2 (MEDIUM): verify the insert actually wrote the expected
    // content. TagLib::FileStream::insert() has no error return value; a
    // silent I/O failure (e.g. storage full mid-write) would otherwise cause
    // RestoreMetadataRegionFd to return kOk even when the file is still in
    // an inconsistent state.
    //
    // After insert() returns, TagLib has internally flushed its stdio buffer
    // (its FileStream::flush() calls fflush()), so pread() on the dup'd fd
    // (which shares the same kernel inode / page cache as the TagLib fd)
    // reflects the post-insert file contents. We read back only the first
    // min(4, backup.bytes.size()) bytes — enough to detect a complete no-op
    // I/O failure without re-reading the potentially-large whole backup region.
    if (fsync_guard.Fd() >= 0 && !backup.bytes.empty()) {
        const size_t check_len =
            std::min(backup.bytes.size(), static_cast<size_t>(4));
        unsigned char head[4] = {};
        const ssize_t nread = ::pread(fsync_guard.Fd(), head, check_len, 0);
        if (nread < 0 || static_cast<size_t>(nread) != check_len ||
            std::memcmp(head, backup.bytes.data(), check_len) != 0) {
            // Restore appears to have failed or written wrong data.
            // Do not fsync a potentially inconsistent state; surface failure
            // so Kotlin can report a more severe error than a normal
            // verification mismatch.
            return WriteResult::kWriteFailure;
        }
    }

    fsync_guard.Sync();
    return WriteResult::kOk;
}

}  // namespace replaygain
