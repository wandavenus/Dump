#include "tag_writer.h"

#include <algorithm>
#include <cstdio>

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

void SetTxxx(TagLib::ID3v2::Tag* tag, const char* description, const std::string& value) {
    // Remove any existing TXXX frame with this description first — TagLib
    // does not dedupe by description automatically, so re-scanning a track
    // would otherwise pile up duplicate frames.
    const TagLib::ID3v2::FrameList& frames = tag->frameList("TXXX");
    for (auto it = frames.begin(); it != frames.end(); ++it) {
        auto* txxx = dynamic_cast<TagLib::ID3v2::UserTextIdentificationFrame*>(*it);
        if (txxx != nullptr &&
            txxx->description() == TagLib::String(description, TagLib::String::UTF8)) {
            tag->removeFrame(*it);
            break;
        }
    }
    auto* frame = new TagLib::ID3v2::UserTextIdentificationFrame(TagLib::String::UTF8);
    frame->setDescription(TagLib::String(description, TagLib::String::UTF8));
    frame->setText(TagLib::String(value, TagLib::String::UTF8));
    tag->addFrame(frame);  // tag takes ownership
}

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

WriteResult WriteMp3(const WriteRequest& req) {
    TagLib::MPEG::File file(req.path.c_str());
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

WriteResult RemoveMp3(const std::string& path) {
    TagLib::MPEG::File file(path.c_str());
    if (!file.isValid()) return WriteResult::kCorruptedFile;
    TagLib::ID3v2::Tag* tag = file.ID3v2Tag(false);
    if (tag == nullptr) return WriteResult::kOk;  // nothing to remove
    for (const char* desc : {"REPLAYGAIN_TRACK_GAIN", "REPLAYGAIN_TRACK_PEAK",
                              "REPLAYGAIN_ALBUM_GAIN", "REPLAYGAIN_ALBUM_PEAK",
                              "R128_TRACK_GAIN", "R128_ALBUM_GAIN"}) {
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

WriteResult WriteFlac(const WriteRequest& req) {
    TagLib::FLAC::File file(req.path.c_str());
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

WriteResult RemoveFlac(const std::string& path) {
    TagLib::FLAC::File file(path.c_str());
    if (!file.isValid()) return WriteResult::kCorruptedFile;
    TagLib::Ogg::XiphComment* comment = file.xiphComment(false);
    if (comment == nullptr) return WriteResult::kOk;
    RemoveReplayGainFields(comment);
    if (!file.save()) return WriteResult::kWriteFailure;
    return WriteResult::kOk;
}

WriteResult WriteOggVorbis(const WriteRequest& req) {
    TagLib::Ogg::Vorbis::File file(req.path.c_str());
    if (!file.isValid()) return WriteResult::kCorruptedFile;
    TagLib::Ogg::XiphComment* comment = file.tag();
    if (comment == nullptr) return WriteResult::kUnsupportedFormat;
    ApplyReplayGainFields(comment, req, /*is_opus=*/false);
    if (!file.save()) return WriteResult::kWriteFailure;
    return WriteResult::kOk;
}

WriteResult RemoveOggVorbis(const std::string& path) {
    TagLib::Ogg::Vorbis::File file(path.c_str());
    if (!file.isValid()) return WriteResult::kCorruptedFile;
    TagLib::Ogg::XiphComment* comment = file.tag();
    if (comment == nullptr) return WriteResult::kOk;
    RemoveReplayGainFields(comment);
    if (!file.save()) return WriteResult::kWriteFailure;
    return WriteResult::kOk;
}

WriteResult WriteOggOpus(const WriteRequest& req) {
    TagLib::Ogg::Opus::File file(req.path.c_str());
    if (!file.isValid()) return WriteResult::kCorruptedFile;
    TagLib::Ogg::XiphComment* comment = file.tag();
    if (comment == nullptr) return WriteResult::kUnsupportedFormat;
    ApplyReplayGainFields(comment, req, /*is_opus=*/true);
    if (!file.save()) return WriteResult::kWriteFailure;
    return WriteResult::kOk;
}

WriteResult RemoveOggOpus(const std::string& path) {
    TagLib::Ogg::Opus::File file(path.c_str());
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
    if (!TagLib::File::isWritable(req.path.c_str())) return WriteResult::kPermissionFailure;

    switch (req.format) {
        case TagFormat::kMp3:       return WriteMp3(req);
        case TagFormat::kFlac:      return WriteFlac(req);
        case TagFormat::kOggVorbis: return WriteOggVorbis(req);
        case TagFormat::kOggOpus:   return WriteOggOpus(req);
    }
    return WriteResult::kUnsupportedFormat;
}

WriteResult RemoveReplayGainTags(const std::string& path) {
    if (path.empty()) return WriteResult::kInvalidArgument;
    if (!TagLib::File::isWritable(path.c_str())) return WriteResult::kPermissionFailure;

    const auto ext_pos = path.find_last_of('.');
    std::string ext = (ext_pos == std::string::npos) ? "" : path.substr(ext_pos + 1);
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);

    if (ext == "mp3") return RemoveMp3(path);
    if (ext == "flac") return RemoveFlac(path);
    if (ext == "ogg" || ext == "oga") return RemoveOggVorbis(path);
    if (ext == "opus") return RemoveOggOpus(path);
    return WriteResult::kUnsupportedFormat;
}

}  // namespace replaygain
