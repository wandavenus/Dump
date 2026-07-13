#include "metadata_region.h"

#include <unistd.h>

#include <cstring>
#include <vector>

namespace replaygain {

namespace {

// Reads exactly `len` bytes at absolute offset `off`. Returns false on any
// short read (including EOF before `len` bytes) or I/O error.
bool PreadExact(int fd, int64_t off, void* buf, size_t len) {
    auto* p = static_cast<unsigned char*>(buf);
    size_t total = 0;
    while (total < len) {
        const ssize_t n = ::pread(fd, p + total, len - total, off + static_cast<int64_t>(total));
        if (n <= 0) return false;  // 0 = EOF, <0 = error
        total += static_cast<size_t>(n);
    }
    return true;
}

// ── MP3 / ID3v2 ───────────────────────────────────────────────────────────────

std::optional<int64_t> DetermineMp3RegionSize(int fd) {
    unsigned char hdr[10];
    if (!PreadExact(fd, 0, hdr, sizeof(hdr))) {
        // File shorter than an ID3v2 header could ever be — treat as "no tag"
        // rather than aborting; a sub-10-byte file has nothing to back up.
        return 0;
    }
    if (std::memcmp(hdr, "ID3", 3) != 0) {
        return 0;  // no ID3v2 tag present — region is empty, not unsafe.
    }
    const uint8_t flags = hdr[5];
    // Each of the four size bytes must be syncsafe (top bit clear). A set
    // top bit means the header is corrupt — abort rather than guess.
    for (int i = 6; i < 10; i++) {
        if (hdr[i] & 0x80) return std::nullopt;
    }
    const int64_t syncsafe_size =
        (static_cast<int64_t>(hdr[6]) << 21) | (static_cast<int64_t>(hdr[7]) << 14) |
        (static_cast<int64_t>(hdr[8]) << 7) | static_cast<int64_t>(hdr[9]);
    int64_t total = 10 + syncsafe_size;
    const bool has_footer = (flags & 0x10) != 0;  // ID3v2.4 footer present
    if (has_footer) total += 10;
    return total;
}

// ── FLAC ──────────────────────────────────────────────────────────────────────

std::optional<int64_t> DetermineFlacRegionSize(int fd) {
    unsigned char magic[4];
    if (!PreadExact(fd, 0, magic, sizeof(magic)) || std::memcmp(magic, "fLaC", 4) != 0) {
        return std::nullopt;  // not a valid FLAC stream — abort.
    }
    int64_t offset = 4;
    // Hard cap on block count: a legitimate FLAC file has a handful of
    // metadata blocks (STREAMINFO, VORBIS_COMMENT, any number of PICTURE
    // blocks, SEEKTABLE, CUESHEET, PADDING). 4096 is far beyond anything
    // real while still bounding a corrupt/adversarial file's parse time.
    for (int guard = 0; guard < 4096; guard++) {
        unsigned char bh[4];
        if (!PreadExact(fd, offset, bh, sizeof(bh))) {
            return std::nullopt;  // truncated mid-block-header — abort.
        }
        const bool is_last = (bh[0] & 0x80) != 0;
        const int64_t block_len = (static_cast<int64_t>(bh[1]) << 16) |
                                   (static_cast<int64_t>(bh[2]) << 8) |
                                   static_cast<int64_t>(bh[3]);
        offset += 4 + block_len;
        if (is_last) return offset;
    }
    return std::nullopt;  // absurd block count — treat as malformed, abort.
}

// ── Ogg (Vorbis / Opus) ───────────────────────────────────────────────────────
//
// Walks Ogg pages from the start of the stream, counting completed logical
// packets (a packet may span multiple pages via the continuation flag and
// 255-valued lacing values), until exactly the expected number of header
// packets (3 for Vorbis: identification+comment+setup; 2 for Opus:
// OpusHead+OpusTags) have completed. The region is only considered safely
// determined if the final header packet's last lacing value is also the
// last entry in that page's segment table — i.e. no audio packet begins on
// the same physical page. If a header packet and the start of audio share a
// page, or anything about the structure looks inconsistent, this aborts
// (returns nullopt) rather than guessing.

struct OggPageInfo {
    int64_t page_start = 0;
    int64_t page_total_size = 0;  // 27 + segment_count + sum(segment table)
    bool continued = false;       // header_type bit 0x01
    std::vector<uint8_t> segments;
};

std::optional<OggPageInfo> ReadOggPage(int fd, int64_t offset) {
    unsigned char base[27];
    if (!PreadExact(fd, offset, base, sizeof(base))) return std::nullopt;
    if (std::memcmp(base, "OggS", 4) != 0) return std::nullopt;
    if (base[4] != 0) return std::nullopt;  // stream_structure_version must be 0

    OggPageInfo info;
    info.page_start = offset;
    info.continued = (base[5] & 0x01) != 0;
    const uint8_t segment_count = base[26];

    std::vector<uint8_t> segment_table(segment_count);
    if (segment_count > 0 &&
        !PreadExact(fd, offset + 27, segment_table.data(), segment_count)) {
        return std::nullopt;
    }
    int64_t data_len = 0;
    for (uint8_t v : segment_table) data_len += v;

    info.segments = std::move(segment_table);
    info.page_total_size = 27 + segment_count + data_len;
    return info;
}

std::optional<int64_t> DetermineOggHeaderRegionSize(int fd, bool is_opus) {
    const int required_packets = is_opus ? 2 : 3;
    int64_t offset = 0;
    int packets_done = 0;
    bool packet_in_progress = false;

    // Hard cap on page count: a huge multi-MB comment packet (large
    // embedded art / lyrics) can legitimately span many pages, but this
    // still bounds parse time against a corrupt/adversarial stream.
    for (int guard = 0; guard < 200000; guard++) {
        const auto page = ReadOggPage(fd, offset);
        if (!page.has_value()) return std::nullopt;

        // The continuation flag must agree with whether we left the
        // previous page mid-packet — any mismatch means the stream isn't
        // structured the way we assume, so abort rather than guess.
        if (page->continued != packet_in_progress) return std::nullopt;

        // Walk the segment table, splitting it into packets: a run of
        // 255-valued segments belongs to one packet and is terminated by
        // the first segment with a value < 255 (0 included — a genuine
        // zero-length terminator segment).
        int completions_this_page = 0;
        int last_completion_index = -1;  // index into segments of the last
                                          // segment that finished a packet
        for (size_t i = 0; i < page->segments.size(); i++) {
            if (page->segments[i] < 255) {
                completions_this_page++;
                last_completion_index = static_cast<int>(i);
            }
        }
        const bool ends_mid_packet =
            !page->segments.empty() && page->segments.back() == 255;

        packets_done += completions_this_page;
        packet_in_progress = ends_mid_packet;

        if (packets_done >= required_packets) {
            if (packets_done > required_packets) {
                // A header packet's completion and further packet(s) — the
                // start of audio — landed on the very same page. Can't
                // split this page byte-exactly between "metadata" and
                // "audio". Abort per policy rather than assume.
                return std::nullopt;
            }
            // packets_done == required_packets exactly. Safe only if the
            // segment that completed the last required packet was also the
            // very last segment in this page's table — otherwise more
            // packet data (the start of audio) follows later in this same
            // page.
            const bool required_packet_is_last_in_page =
                last_completion_index == static_cast<int>(page->segments.size()) - 1;
            if (!required_packet_is_last_in_page) return std::nullopt;
            return page->page_start + page->page_total_size;
        }

        offset = page->page_start + page->page_total_size;
    }
    return std::nullopt;  // pathological page count — treat as malformed.
}

}  // namespace

std::optional<int64_t> DetermineMetadataRegionSize(int fd, TagFormat format) {
    switch (format) {
        case TagFormat::kMp3:
            return DetermineMp3RegionSize(fd);
        case TagFormat::kFlac:
            return DetermineFlacRegionSize(fd);
        case TagFormat::kOggVorbis:
            return DetermineOggHeaderRegionSize(fd, /*is_opus=*/false);
        case TagFormat::kOggOpus:
            return DetermineOggHeaderRegionSize(fd, /*is_opus=*/true);
    }
    return std::nullopt;
}

bool ReadRegion(int fd, int64_t size, std::string* out) {
    if (size < 0 || out == nullptr) return false;
    if (size == 0) {
        out->clear();
        return true;
    }
    out->resize(static_cast<size_t>(size));
    return PreadExact(fd, 0, out->data(), static_cast<size_t>(size));
}

}  // namespace replaygain
