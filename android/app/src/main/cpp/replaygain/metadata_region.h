#ifndef REPLAYGAIN_METADATA_REGION_H
#define REPLAYGAIN_METADATA_REGION_H

#include <cstdint>
#include <optional>
#include <string>

#include "tag_writer.h"  // TagFormat

namespace replaygain {

// ── Exact metadata-region sizing (no fixed-size guess) ───────────────────────
//
// Determines the exact byte length, counted from the start of the file, of
// the container's metadata region for `format`:
//
//   - MP3 (ID3v2):    header (10 bytes) + syncsafe tag size + optional
//                      10-byte footer (ID3v2.4). 0 if no ID3v2 tag exists.
//   - FLAC:           "fLaC" magic (4 bytes) + every metadata block, walked
//                      one 4-byte block header at a time, up to and
//                      including the block with the last-block-flag set.
//                      Handles any number of PICTURE blocks and an
//                      arbitrarily large VORBIS_COMMENT the same way — the
//                      walk only ever reads 4-byte headers and skips by the
//                      declared block length, never the block content.
//   - Ogg Vorbis:     identification + comment + setup header packets (3
//                      packets total), walked page-by-page via the Ogg
//                      page/segment-table structure so an arbitrarily large,
//                      multi-page comment packet (e.g. huge embedded art or
//                      lyrics as a base64 Vorbis comment field) is handled
//                      by simply continuing the walk across more pages.
//   - Ogg Opus:       OpusHead + OpusTags header packets (2 packets total),
//                      same page walk as Vorbis.
//
// Returns std::nullopt whenever the region cannot be determined with
// certainty: truncated/malformed headers, an inconsistent Ogg continuation
// flag, or (Ogg only) a header packet sharing a physical page with the
// first audio packet, which would make a byte-exact split unsafe. Callers
// MUST treat nullopt as "abort the write" — never fall back to a guessed
// size.
//
// Reads via `pread(2)` at absolute offsets, so this does not disturb `fd`'s
// shared file-position — safe to call before or after wrapping `fd` in a
// TagLib::FileStream (which manages its own position independently via
// stdio, see tfilestream.cpp).
std::optional<int64_t> DetermineMetadataRegionSize(int fd, TagFormat format);

// Reads exactly `size` bytes starting at offset 0 of `fd` into `*out`.
// Returns false on any short read or I/O error (out is left unspecified).
bool ReadRegion(int fd, int64_t size, std::string* out);

}  // namespace replaygain

#endif  // REPLAYGAIN_METADATA_REGION_H
