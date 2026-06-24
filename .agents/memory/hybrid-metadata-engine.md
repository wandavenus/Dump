---
name: Hybrid metadata engine
description: jaudiotagger replacement — ExoMetadataReader + MetadataCacheDb; covers all 6 migration phases including what each new file does and key design constraints.
---

## Decision
jaudiotagger (net.jthink:jaudiotagger:2.2.5) fully removed. Replaced with:
- **Layer 1**: MediaStore expanded projection in `getSongs()` (year, track, album_artist, genre API30+, bitrate/samplerate API31+)
- **Layer 2**: `MetadataCacheDb` — SQLite via SQLiteOpenHelper, WAL mode, mtime-keyed invalidation
- **Layer 3**: `ExoMetadataReader` — ExoPlayer `MetadataRetriever.retrieveMetadata()` reads ID3v2 TXXX, USLT, Vorbis comments, MdtaMetadataEntry in one pass for both RG tags + lyrics
- **Layer 4**: Scan results written to `MetadataCacheDb` instead of back into the audio file

## Why
jaudiotagger's `AudioFileIO.write()` silently fails on Android 10+ / MIUI 11+ for files outside app sandbox (scoped storage). ExoPlayer MetadataRetriever is already a dependency (media3-exoplayer) and reads the same native C++ demuxer used for playback.

## New files
- `android/.../metadata/MetadataCacheDb.kt` — singleton SQLiteOpenHelper; `mtime()` in companion object; `LYRICS_NONE = "\u0000NONE\u0000"` sentinel; `putByPath()` uses `path.hashCode()` as synthetic ID
- `android/.../metadata/ExoMetadataReader.kt` — `@OptIn(UnstableApi::class)` object; `read(context, path)` blocks up to 10s; always call from background thread

## How to apply
- `getReplayGainTags` and `getEmbeddedLyrics` MethodChannel handlers MUST be wrapped in `Thread { } + runOnUiThread { result.success() }` — ExoPlayer MetadataRetriever blocks
- First read (cache miss) populates BOTH rg tags AND lyrics in one ExoPlayer pass — avoids double parse
- `"genre"` projection column only on API 30+ (R); `"bitrate"/"samplerate"` only on API 31+ (S); `"album_artist"` safe on all API levels as string literal
- MediaStore TRACK field: if `rawTrack > 1000` then disc = rawTrack/1000, track = rawTrack%1000
- `SongMetadataService` fast path: if `song.bitrate != null || song.sampleRate != null` → skip native `getAudioMetadata()` call entirely; fileSize read via `dart:io File.lengthSync()`
- `LocalSong` now has 7 optional fields: year, trackNumber, discNumber, albumArtist, genre, bitrate, sampleRate

## Constraints
- `dart:io` added as import to `song_metadata_service.dart` barrel (not the part file — part files can't declare imports)
- Only ONE `companion object` per Kotlin class — `mtime()` must live inside the main companion object of `MetadataCacheDb`
- M4A ReplayGain via iTunes free-form `----` atoms: ExoPlayer may or may not surface these as `MdtaMetadataEntry` — handled with `contains()` key matching as best-effort
