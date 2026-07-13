#include "tag_writer.h"

#include <sys/stat.h>

#include <algorithm>
#include <cstdio>
#include <fstream>
#include <functional>

#include <fileref.h>
#include <flacfile.h>
#include <flacproperties.h>
#include <id3v2tag.h>
#include <mpegfile.h>
#include <opusfile.h>
#include <opusproperties.h>
#include <textidentificationframe.h>
#include <tfile.h>
#include <tstring.h>
#include <vorbisfile.h>
#include <vorbisproperties.h>
#include <xiphcomment.h>

namespace replaygain {

namespace {

// ── Crash-safe temp-file + atomic-rename write strategy ──────────────────────
//
// TagLib::File::save() rewrites its target file in place. That is NOT
// crash-safe: a process kill, OOM, or power loss mid-save can leave the file
// truncated or with a half-written tag block, corrupting a file that was
// perfectly fine before we touched it. To make every write in this file
// crash-safe, all mutation goes through WithCrashSafeWrite() below, which:
//
//   1. Copies the original file to a same-directory temp file.
//   2. Runs the caller's mutator (open temp file with TagLib, edit tags,
//      save()) against ONLY the temp copy.
//   3. On full success, atomically renames the temp file over the original
//      (same-directory std::rename() is atomic on POSIX/ext4/F2FS — the
//      filesystems backing Android's writable app/media storage).
//   4. On any failure at any step, deletes the temp file and leaves the
//      original completely untouched.
//
// This means the on-disk file is only ever in one of two states as far as
// any other process (or a crash) can observe: the old tags, or the new
// tags — never a partially-written file.

// Builds a same-directory temp path, e.g. "/foo/bar.mp3" -> "/foo/bar.mp3.rgtmp".
// Same directory is required so the final std::rename() is guaranteed to be
// on the same filesystem (a cross-filesystem rename is NOT atomic, and on
// some platforms fails outright).
std::string TempPathFor(const std::string& path) {
    return path + ".rgtmp";
}

// Copies `src` to `dst` byte-for-byte. On any I/O failure, best-effort
// deletes a partially-written `dst` so no truncated temp file is left behind.
bool CopyFile(const std::string& src, const std::string& dst) {
    std::ifstream in(src, std::ios::binary);
    if (!in) return false;

    std::ofstream out(dst, std::ios::binary | std::ios::trunc);
    if (!out) return false;

    out << in.rdbuf();
    const bool read_ok  = !in.bad();
    const bool write_ok = out.good();
    in.close();
    out.close();

    if (!read_ok || !write_ok) {
        std::remove(dst.c_str());
        return false;
    }
    return true;
}

// Copies the original file's POSIX permission bits onto the temp file so a
// rename-based replace doesn't silently change file permissions. Best
// effort: if `stat`/`chmod` fail (e.g. permission-bit APIs unavailable on a
// particular storage layer), the write still proceeds — this is a hardening
// nicety, not a correctness requirement for the crash-safety guarantee.
void PreservePermissions(const std::string& original_path, const std::string& temp_path) {
    struct stat st{};
    if (::stat(original_path.c_str(), &st) == 0) {
        ::chmod(temp_path.c_str(), st.st_mode & 07777);
    }
}

// Runs `mutator` (which opens the temp file at the path it is given, edits
// tags, and calls TagLib::File::save()) against a same-directory temp copy
// of `original_path`, then atomically renames the temp file over the
// original ONLY when `mutator` returns WriteResult::kOk. On any failure the
// temp file is deleted and `original_path` is left byte-for-byte untouched.
WriteResult WithCrashSafeWrite(
    const std::string& original_path,
    const std::function<WriteResult(const std::string& temp_path)>& mutator) {
    const std::string temp_path = TempPathFor(original_path);

    // Always start from a clean temp file — remove any stale leftover from
    // a previous crashed/killed attempt before copying.
    std::remove(temp_path.c_str());

    if (!CopyFile(original_path, temp_path)) {
        std::remove(temp_path.c_str());
        return WriteResult::kWriteFailure;
    }
    PreservePermissions(original_path, temp_path);

    const WriteResult result = mutator(temp_path);
    if (result != WriteResult::kOk) {
        std::remove(temp_path.c_str());
        return result;
    }

    // Commit point. Same-directory rename is atomic on POSIX: this call
    // either fully succeeds (new tags now visible at original_path) or fully
    // fails (original_path is still exactly what it was before this call).
    if (std::rename(temp_path.c_str(), original_path.c_str()) != 0) {
        std::remove(temp_path.c_str());
        return WriteResult::kWriteFailure;
    }
    return WriteResult::kOk;
}

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

WriteResult WriteMp3(const WriteRequest& req, const std::string& target_path) {
    TagLib::MPEG::File file(target_path.c_str());
    if (!file.isValid()) return WriteResult::kCorruptedFile;

    TagLib::ID3v2::Tag* tag = file.ID3v2Tag(true);  // create if missing
    if (tag == nullptr) return WriteResult::kUnsupportedFormat;

    SetTxxx(tag, "REPLAYGAIN_TRACK_GAIN", FormatGainDb(req.track_gain_db));
    SetTxxx(tag, "REPLAYGAIN_TRACK_PEAK", FormatPeak(req.track_peak_linear));
    if (req.has_album) {
        SetTxxx(tag, "REPLAYGAIN_ALBUM_GAIN", FormatGainDb(req.album_gain_db));
        SetTxxx(tag, "REPLAYGAIN_ALBUM_PEAK", FormatPeak(req.album_peak_linear));
    }

    // save(): TagLib rewrites only the ID3v2 header block, shifting audio
    // frames as needed if the tag grows — it never decodes/re-encodes MPEG
    // audio frames. Cover art (APIC), lyrics (USLT), comments, ISRC (TXXX
    // "ISRC" or TSRC frame), disc/track number frames are untouched because
    // we only ever add/replace the two-to-four TXXX frames above.
    if (!file.save()) return WriteResult::kWriteFailure;
    return WriteResult::kOk;
}

WriteResult RemoveMp3(const std::string& target_path) {
    TagLib::MPEG::File file(target_path.c_str());
    if (!file.isValid()) return WriteResult::kCorruptedFile;
    TagLib::ID3v2::Tag* tag = file.ID3v2Tag(false);
    if (tag == nullptr) return WriteResult::kOk;  // nothing to remove
    for (const char* desc : {"REPLAYGAIN_TRACK_GAIN", "REPLAYGAIN_TRACK_PEAK",
                              "REPLAYGAIN_ALBUM_GAIN", "REPLAYGAIN_ALBUM_PEAK",
                              "R128_TRACK_GAIN", "R128_ALBUM_GAIN",
                              // iTunNORM: two spellings seen in the wild;
                              // TagBuilder.kt's reader accepts both.
                              "ITUNNORM", "ITUN NORM"}) {
        RemoveTxxx(tag, desc);
    }
    if (!file.save()) return WriteResult::kWriteFailure;
    return WriteResult::kOk;
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

WriteResult WriteFlac(const WriteRequest& req, const std::string& target_path) {
    TagLib::FLAC::File file(target_path.c_str());
    if (!file.isValid()) return WriteResult::kCorruptedFile;

    // xiphComment(true): FLAC stores Vorbis comments as a metadata block;
    // create=true ensures one exists even for files that never had tags.
    TagLib::Ogg::XiphComment* comment = file.xiphComment(true);
    if (comment == nullptr) return WriteResult::kUnsupportedFormat;

    ApplyReplayGainFields(comment, req, /*is_opus=*/false);

    // FLAC::File::save() rewrites only metadata blocks (VORBIS_COMMENT,
    // PICTURE, etc.) — the STREAMINFO + audio frames are copied verbatim.
    // Existing PICTURE blocks (cover art) and any other Xiph fields
    // (lyrics, ISRC, ALBUMARTIST, DISCNUMBER, COMMENT, ...) are preserved
    // because we only add/replace the specific keys above.
    if (!file.save()) return WriteResult::kWriteFailure;
    return WriteResult::kOk;
}

WriteResult RemoveFlac(const std::string& target_path) {
    TagLib::FLAC::File file(target_path.c_str());
    if (!file.isValid()) return WriteResult::kCorruptedFile;
    TagLib::Ogg::XiphComment* comment = file.xiphComment(false);
    if (comment == nullptr) return WriteResult::kOk;
    RemoveReplayGainFields(comment);
    if (!file.save()) return WriteResult::kWriteFailure;
    return WriteResult::kOk;
}

WriteResult WriteOggVorbis(const WriteRequest& req, const std::string& target_path) {
    TagLib::Ogg::Vorbis::File file(target_path.c_str());
    if (!file.isValid()) return WriteResult::kCorruptedFile;
    TagLib::Ogg::XiphComment* comment = file.tag();
    if (comment == nullptr) return WriteResult::kUnsupportedFormat;
    ApplyReplayGainFields(comment, req, /*is_opus=*/false);
    if (!file.save()) return WriteResult::kWriteFailure;
    return WriteResult::kOk;
}

WriteResult RemoveOggVorbis(const std::string& target_path) {
    TagLib::Ogg::Vorbis::File file(target_path.c_str());
    if (!file.isValid()) return WriteResult::kCorruptedFile;
    TagLib::Ogg::XiphComment* comment = file.tag();
    if (comment == nullptr) return WriteResult::kOk;
    RemoveReplayGainFields(comment);
    if (!file.save()) return WriteResult::kWriteFailure;
    return WriteResult::kOk;
}

WriteResult WriteOggOpus(const WriteRequest& req, const std::string& target_path) {
    TagLib::Ogg::Opus::File file(target_path.c_str());
    if (!file.isValid()) return WriteResult::kCorruptedFile;
    TagLib::Ogg::XiphComment* comment = file.tag();
    if (comment == nullptr) return WriteResult::kUnsupportedFormat;
    ApplyReplayGainFields(comment, req, /*is_opus=*/true);
    if (!file.save()) return WriteResult::kWriteFailure;
    return WriteResult::kOk;
}

WriteResult RemoveOggOpus(const std::string& target_path) {
    TagLib::Ogg::Opus::File file(target_path.c_str());
    if (!file.isValid()) return WriteResult::kCorruptedFile;
    TagLib::Ogg::XiphComment* comment = file.tag();
    if (comment == nullptr) return WriteResult::kOk;
    RemoveReplayGainFields(comment);
    if (!file.save()) return WriteResult::kWriteFailure;
    return WriteResult::kOk;
}

}  // namespace

WriteResult WriteReplayGainTags(const WriteRequest& req) {
    if (req.path.empty()) return WriteResult::kInvalidArgument;
    

    return WithCrashSafeWrite(req.path, [&req](const std::string& target_path) -> WriteResult {
        switch (req.format) {
            case TagFormat::kMp3:       return WriteMp3(req, target_path);
            case TagFormat::kFlac:      return WriteFlac(req, target_path);
            case TagFormat::kOggVorbis: return WriteOggVorbis(req, target_path);
            case TagFormat::kOggOpus:   return WriteOggOpus(req, target_path);
        }
        return WriteResult::kUnsupportedFormat;
    });
}

WriteResult RemoveReplayGainTags(const std::string& path) {
    if (path.empty()) return WriteResult::kInvalidArgument;
    

    const auto ext_pos = path.find_last_of('.');
    std::string ext = (ext_pos == std::string::npos) ? "" : path.substr(ext_pos + 1);
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);

    std::function<WriteResult(const std::string&)> remover;
    if (ext == "mp3") {
        remover = RemoveMp3;
    } else if (ext == "flac") {
        remover = RemoveFlac;
    } else if (ext == "ogg" || ext == "oga") {
        remover = RemoveOggVorbis;
    } else if (ext == "opus") {
        remover = RemoveOggOpus;
    } else {
        return WriteResult::kUnsupportedFormat;
    }

    return WithCrashSafeWrite(path, remover);
}

}  // namespace replaygain
