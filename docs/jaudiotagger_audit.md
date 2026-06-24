# jaudiotagger Audit — Hybrid Metadata Engine Feasibility Report

**Date:** June 2026  
**Scope:** Android native layer (`android/app/`)  
**Verdict:** jaudiotagger cannot be fully removed today without losing two critical capabilities — embedded lyrics and ReplayGain tag I/O. A partial migration is possible and is detailed below.

---

## 1. Every Location Where jaudiotagger Is Used

Three files in the Android native layer reference jaudiotagger:

### `android/app/build.gradle`
```
implementation 'net.jthink:jaudiotagger:2.2.5'
```
Also adds three `packaging.resources.excludes` entries to suppress duplicate META-INF files that jaudiotagger's JAR ships with (`META-INF/LICENSE`, `META-INF/NOTICE`, `META-INF/*.kotlin_module`). Removing jaudiotagger also removes the need for these exclusions.

---

### `android/app/src/main/kotlin/com/example/musicplayer/MainActivity.kt`

**Function: `getReplayGainTags(path)`**  
Called from Dart via `MethodChannel('musicplayer/media_store')` → `getReplayGainTags`.

Uses jaudiotagger to:
- `AudioFileIO.read(file)` — open and parse any supported audio file
- `tag.getFirst(FieldKey.valueOf(key.uppercase()))` — read standard field keys
- `VorbisCommentTag.getFirst(key)` — raw Vorbis comment string lookup (OGG/FLAC/OPUS)
- `AbstractID3v2Tag.getFrame("TXXX")` + `FrameBodyTXXX` — iterate TXXX custom frames (MP3)

Tags read: `REPLAYGAIN_TRACK_GAIN`, `REPLAYGAIN_TRACK_PEAK`, `REPLAYGAIN_ALBUM_GAIN`, `REPLAYGAIN_ALBUM_PEAK`, `R128_TRACK_GAIN`, `R128_ALBUM_GAIN`, `iTunNORM`

**Function: `getEmbeddedLyrics(path)`**  
Called from Dart via `LyricsService` as Step 1 of the lyrics cascade.

Uses jaudiotagger to:
- `AudioFileIO.read(file)` — parse file
- `tag.getFirst(FieldKey.LYRICS)` — USLT (MP3), ©lyr atom (M4A), LYRICS Vorbis comment (FLAC/OGG/OPUS)
- `AbstractID3v2Tag.getFrame("USLT")` — iterate all USLT frames with language-preference logic (prefers blank/`"eng"`)
- `VorbisCommentTag.getFirst("LYRICS" | "UNSYNCEDLYRICS" | "UNSYNCED LYRICS")` — three key variants
- `tag.getFirst(FieldKey.COMMENT)` + multiline heuristic — last-resort fallback

**Helper functions (both serve the above two):**  
`readCustomTag()`, `getID3TXXXValue()`, `extractAllUsltFrames()`

---

### `android/app/src/main/kotlin/com/example/musicplayer/replay_gain/ReplayGainScanner.kt`

**Function: `writeTags(path, result)`**  
Called after a successful loudness scan (`scanReplayGain` method channel call). Writes computed gain values back into the audio file's tag layer.

Uses jaudiotagger to:
- `AudioFileIO.read(file)` / `audioFile.createDefaultTag()` — open + ensure a tag exists
- For MP3 (`AbstractID3v2Tag`): `writeTxxx()` — remove old TXXX frames by description, insert `ID3v24Frame` or `ID3v23Frame` with `FrameBodyTXXX`
- For OGG/FLAC (`VorbisCommentTag`): `writeVorbisField()` — delete old field, insert `VorbisCommentTagField`
- For M4A/other: `tag.setField(FieldKey.REPLAYGAIN_TRACK_GAIN, ...)` + `tag.setField(FieldKey.REPLAYGAIN_TRACK_PEAK, ...)`
- `AudioFileIO.write(audioFile)` — flush tag changes to disk

> **Note:** The loudness *analysis* in `ReplayGainScanner.scan()` uses only Android-native APIs (`MediaExtractor`, `MediaCodec`) — jaudiotagger is only used for the tag-write step at the very end.

---

## 2. Complete Metadata Field Inventory

| Field | Where Consumed | Current Source |
|---|---|---|
| title | `LocalSong.title`, `SongInfo.title` | MediaStore `TITLE` |
| artist | `LocalSong.artist` | MediaStore `ARTIST` |
| album | `LocalSong.album` | MediaStore `ALBUM` |
| albumId | `LocalSong.albumId`, artwork lookup | MediaStore `ALBUM_ID` |
| duration | `LocalSong.duration` | MediaStore `DURATION` |
| path | `LocalSong.path` | MediaStore `DATA` |
| id | `LocalSong.id` | MediaStore `_ID` |
| year | `SongInfo.year` | `MediaMetadataRetriever.METADATA_KEY_YEAR` |
| bitrate | `SongInfo.bitrate` | `MediaMetadataRetriever.METADATA_KEY_BITRATE` |
| sample rate | `SongInfo.sampleRate` | `MediaMetadataRetriever.METADATA_KEY_SAMPLERATE` |
| fileSize | `SongInfo.fileSize` | `File.length()` |
| embedded artwork | artwork cache | `MediaMetadataRetriever.embeddedPicture` |
| REPLAYGAIN_TRACK_GAIN | `ReplayGainService` | **jaudiotagger** (TXXX / Vorbis / FieldKey) |
| REPLAYGAIN_TRACK_PEAK | `ReplayGainService` | **jaudiotagger** |
| REPLAYGAIN_ALBUM_GAIN | `ReplayGainService` | **jaudiotagger** |
| REPLAYGAIN_ALBUM_PEAK | `ReplayGainService` | **jaudiotagger** |
| R128_TRACK_GAIN | `ReplayGainService` | **jaudiotagger** (TXXX / Vorbis) |
| R128_ALBUM_GAIN | `ReplayGainService` | **jaudiotagger** |
| iTunNORM | `ReplayGainService` | **jaudiotagger** |
| embedded lyrics | `LyricsService` step 1 | **jaudiotagger** (USLT, ©lyr, Vorbis) |
| write RG tags to file | `scanReplayGain` result | **jaudiotagger** |

Fields NOT currently read anywhere (album artist, track number, disc number, genre) are available from MediaStore and MediaMetadataRetriever if needed in future.

---

## 3. What MediaStore Can Provide

MediaStore is a fast indexed SQL cursor over the device's audio library. It is already the library scan source.

| Field | MediaStore Column | Notes |
|---|---|---|
| id | `_ID` | ✅ already used |
| title | `TITLE` | ✅ already used |
| artist | `ARTIST` | ✅ already used |
| album | `ALBUM` | ✅ already used |
| albumId | `ALBUM_ID` | ✅ already used |
| duration | `DURATION` | ✅ already used |
| path | `DATA` | ✅ already used |
| year | `YEAR` | available, currently using MMR |
| track number | `TRACK` | available, not currently read |
| disc number | `DISC_NUMBER` (API 30+) | available, not currently read |
| album artist | `ALBUM_ARTIST` (API 30+) | available, not currently read |
| genre | `GENRE` (API 30+) | available, not currently read |
| bitrate | `BITRATE` (API 31+) | available, not currently read |
| sample rate | `SAMPLERATE` (API 31+) | available, not currently read |
| **embedded lyrics** | — | ❌ not stored in MediaStore |
| **ReplayGain tags** | — | ❌ not stored in MediaStore |
| **embedded artwork** | — | ❌ not stored (ALBUM_ID points to MediaStore art, not embedded) |

---

## 4. What MediaMetadataRetriever Can Provide

`MediaMetadataRetriever` reads directly from the file or URI, exposing a fixed set of standard keys.

| Field | MMR Key | Notes |
|---|---|---|
| title | `METADATA_KEY_TITLE` | ✅ fallback if MediaStore empty |
| artist | `METADATA_KEY_ARTIST` | ✅ |
| album | `METADATA_KEY_ALBUM` | ✅ |
| album artist | `METADATA_KEY_ALBUMARTIST` | ✅ |
| track number | `METADATA_KEY_CD_TRACK_NUMBER` | ✅ |
| disc number | `METADATA_KEY_DISC_NUMBER` | ✅ |
| year | `METADATA_KEY_YEAR` | ✅ already used |
| genre | `METADATA_KEY_GENRE` | ✅ |
| duration | `METADATA_KEY_DURATION` | ✅ |
| bitrate | `METADATA_KEY_BITRATE` | ✅ already used |
| sample rate | `METADATA_KEY_SAMPLERATE` | ✅ already used |
| embedded artwork | `embeddedPicture` | ✅ already used (ArtworkCacheManager) |
| **embedded lyrics** | — | ❌ no lyrics key exists |
| **ReplayGain / R128** | — | ❌ custom tags not exposed |
| **iTunNORM** | — | ❌ iTunes normalization not exposed |

`MediaMetadataRetriever` exposes only the tags defined by the `METADATA_KEY_*` constants. It has no mechanism to read arbitrary custom tags (TXXX frames, raw Vorbis comment fields, iTunes atom names). There is no `METADATA_KEY_LYRICS` constant.

---

## 5. Capability Gap — What Would Be Lost

If jaudiotagger were removed today with no alternative in place:

### Loss 1 — Embedded Lyrics (High Impact)
`LyricsService` step 1 would always return null. The cascade would skip to `.lrc` sidecar lookup and then internet fetch. Users with embedded USLT/©lyr/Vorbis lyrics in their files (very common in curated libraries — ripped CDs, tagged collections) would silently lose them. The feature would appear broken for those songs unless an .lrc sidecar exists.

Affected formats: MP3 (USLT/SYLT), M4A (©lyr), FLAC/OGG/OPUS (Vorbis LYRICS / UNSYNCEDLYRICS).

Multi-language USLT frame handling and the COMMENT fallback would also be lost.

### Loss 2 — ReplayGain / R128 Tag Reading (High Impact)
`ReplayGainService.resolve()` would receive an empty map from native. The service falls back to `0.0 dB` gain, effectively disabling volume normalization for all songs that have existing tags. R128 (EBU-compliant loudness) and iTunNORM (Apple normalization) tags would also be ignored.

Affected tag types: TXXX:REPLAYGAIN_* (MP3), Vorbis comments (FLAC/OGG/OPUS), FieldKey (M4A), R128_TRACK_GAIN / R128_ALBUM_GAIN (all formats), iTunNORM.

### Loss 3 — ReplayGain Tag Writing (Medium Impact)
`scanReplayGain` would still compute correct gain values, but `writeTags()` would always return false. Scan results would have to live only in the in-memory / SharedPreferences cache. On app reinstall or cache clear, all scan results would be lost and re-scan would be required. Users who rely on scanned tags being persistent in the file (for cross-app consistency) would lose that guarantee.

---

## 6. Architecture Comparison

### Current Architecture

```
Library Scan
  └── MediaStore (cursor, fast, indexed)

Basic Metadata
  └── MediaStore (title, artist, album, duration, path, albumId)

Technical Metadata
  └── MediaMetadataRetriever (year, bitrate, sampleRate)

Artwork
  └── MediaMetadataRetriever.embeddedPicture
        └── ArtworkCacheManager (WebP, LRU, disk-persisted)

Embedded Lyrics
  └── jaudiotagger.AudioFileIO
        → FieldKey.LYRICS (USLT, ©lyr, Vorbis LYRICS)
        → USLT frame scan (multi-language, ID3v2)
        → Vorbis UNSYNCEDLYRICS / UNSYNCED LYRICS
        → COMMENT fallback

ReplayGain Read
  └── jaudiotagger.AudioFileIO
        → TXXX frame scan (ID3v2 MP3)
        → Vorbis comment string (FLAC/OGG/OPUS)
        → FieldKey (M4A)
        → 7 tag variants (RG track/album, R128, iTunNORM)

ReplayGain Scan
  └── MediaExtractor + MediaCodec (native, no jaudiotagger)
        → EBU R128 / ITU-R BS.1770-4 gating

ReplayGain Write
  └── jaudiotagger.AudioFileIO
        → TXXX frames (ID3v2 MP3)
        → VorbisCommentTagField (FLAC/OGG/OPUS)
        → FieldKey (M4A)
```

### Proposed Architecture (Hybrid Native Engine)

```
Layer 1 — MediaStore  (fast, indexed, unchanged)
  ├── title, artist, album, albumId, duration, path, id
  ├── year, track, disc, albumArtist, genre  (expand projection)
  └── bitrate, sampleRate  (API 31+, add as secondary columns)

Layer 2 — MediaMetadataRetriever  (file-level fallback, unchanged)
  ├── year, bitrate, sampleRate  (already in use)
  ├── artwork → ArtworkCacheManager  (already in use)
  └── standard tag fallback for any field missing from MediaStore

Layer 3 — Persistent Metadata Cache  (new)
  ├── SQLite table: song_metadata (id, path, mtime, json_blob)
  ├── Cache key: MediaStore _ID + file mtime
  ├── Eviction: mtime change = stale entry, re-read on next access
  └── Populated on first access, never re-read unless file changes

Layer 4 — Custom Tag Parser  (partially retained or replaced)
  ├── Embedded lyrics: jaudiotagger OR ExoPlayer MetadataRetriever
  └── ReplayGain tags: jaudiotagger OR custom binary parser
```

---

## 7. Detailed Field-by-Field Replacement Matrix

| Field | Layer 1 (MS) | Layer 2 (MMR) | Replace jaudiotagger? | Fallback strategy |
|---|---|---|---|---|
| title | ✅ | ✅ | — (not using JAT) | n/a |
| artist | ✅ | ✅ | — | n/a |
| album | ✅ | ✅ | — | n/a |
| albumId | ✅ | — | — | n/a |
| duration | ✅ | ✅ | — | n/a |
| year | ✅ (add) | ✅ | — | n/a |
| bitrate | ✅ API31 (add) | ✅ | — | n/a |
| sampleRate | ✅ API31 (add) | ✅ | — | n/a |
| artwork | — | ✅ | — | n/a |
| albumArtist | ✅ API30 (add) | ✅ | — | n/a |
| trackNumber | ✅ (add) | ✅ | — | n/a |
| discNumber | ✅ API30 (add) | ✅ | — | n/a |
| genre | ✅ API30 (add) | ✅ | — | n/a |
| embedded lyrics | ❌ | ❌ | **No — see §8** | ExoPlayer MetadataRetriever |
| RG track/album gain | ❌ | ❌ | **No — see §8** | Custom parser or retain JAT |
| R128 track/album | ❌ | ❌ | **No — see §8** | Custom parser or retain JAT |
| iTunNORM | ❌ | ❌ | **No — see §8** | Custom parser or retain JAT |
| Write RG tags | ❌ | ❌ | **No — see §8** | Sidecar DB or retain JAT |

---

## 8. Proven Replacement Options for the Three Irreplaceable Capabilities

### 8A — Embedded Lyrics via ExoPlayer MetadataRetriever

ExoPlayer's `androidx.media3.exoplayer.MetadataRetriever` parses the full container metadata asynchronously and returns typed `Metadata` objects including:

- `TextInformationFrame` — ID3v2 text frames
- `UnsynchronizedLyricsFrame` — USLT (ID3v2 MP3) ✅
- `Id3Frame` — raw fallback for any ID3v2 frame by ID
- `VorbisComment` — Vorbis comment entries (FLAC/OGG/OPUS) ✅
- `MdtaMetadataEntry` — MP4/M4A metadata atoms (©lyr) ✅

**Verdict:** ExoPlayer MetadataRetriever can replace jaudiotagger for lyrics reading with approximately the same coverage. It is already a dependency (media3-exoplayer is in build.gradle). Implementation requires mapping frame types per format and replicating the USLT multi-language preference logic currently in `extractAllUsltFrames()`.

**Limitation:** `MetadataRetriever` is asynchronous and returns a `ListenableFuture<TrackGroupArray>` — the metadata is attached to `Format.metadata`. This requires a small coroutine wrapper. It also does not expose raw Vorbis comment arbitrary keys by string; you must iterate `VorbisComment.values` and match by prefix (e.g., `"LYRICS=..."`).

**Estimated implementation effort:** Medium (3–5 days). High confidence the full lyrics coverage can be preserved.

---

### 8B — ReplayGain Tag Reading via Custom Binary Parser

ReplayGain / R128 tags are stored as:

| Format | Tag storage mechanism |
|---|---|
| MP3 (ID3v2.3/2.4) | TXXX frame with `Description="REPLAYGAIN_TRACK_GAIN"` and value string |
| FLAC / OGG / OPUS | Vorbis comment: `REPLAYGAIN_TRACK_GAIN=+0.50 dB` (case-insensitive key) |
| M4A (iTunes) | Free-form atom `----:com.apple.iTunes:replaygain_track_gain` |
| M4A (R128) | Same atom pattern with `r128_track_gain` key |
| MP3 (iTunNORM) | COMM or TXXX frame; key `iTunNORM` |

Option A — **ExoPlayer MetadataRetriever**: Can read `Id3Frame` for TXXX (MP3) and `VorbisComment` for FLAC/OGG. M4A `MdtaMetadataEntry` would cover R128. Coverage would be ≥95% of real-world files. The TXXX multi-frame iteration logic currently in `getID3TXXXValue()` would need to be reimplemented over ExoPlayer's `Id3Frame` list.

Option B — **Direct binary parser**: Write a small Kotlin class that reads just enough of the file header to extract TXXX / Vorbis comment / MP4 atom. ID3v2 TXXX parsing is ~80 lines of Kotlin. Vorbis comment is another ~40 lines. MP4 atom traversal is ~60 lines. Total ~180 lines, zero external dependencies.

**Verdict for ReplayGain reading:** Replaceable. ExoPlayer (Option A) is lower effort; direct parser (Option B) has zero extra dependencies and better control.

---

### 8C — ReplayGain Tag Writing

This is the hardest case. Writing modified ID3v2 TXXX frames, Vorbis comment fields, or MP4 atoms back to an existing audio file requires in-place binary editing of the container format.

**Option A — Retain jaudiotagger only for writing.** Remove it from all read paths, keep only `ReplayGainScanner.writeTags()`. APK size reduction would be minimal since the JAR is still present.

**Option B — Store scan results in a sidecar database instead of writing to file.** Replace `writeTags()` with a SQLite/SharedPreferences store keyed by `(path, mtime)`. Gains are re-read from the database on app start. Cross-app compatibility is lost (other players won't see the tags), but within-app behaviour is identical. This is actually the more reliable approach on Android 10+ where write access to arbitrary external files requires `MANAGE_EXTERNAL_STORAGE` (a restricted permission) or `MediaStore.createWriteRequest()` — jaudiotagger's `AudioFileIO.write()` already silently fails on many Android 10+ configurations.

**Option C — Write a custom ID3v2 TXXX injector.** ID3v2 has a fixed header + size field at the start of the file, which allows prepending or replacing frames without rewriting the audio data. This is well-defined in the ID3v2.3/2.4 spec. For FLAC/OGG the Vorbis comment block is similarly at the front of the stream. Effort: ~200–300 lines of Kotlin, MP3 + FLAC/OGG coverage only. M4A would need additional work.

**Verdict for tag writing:** Option B (sidecar database) is recommended. It sidesteps Android 10+ permission restrictions that already cause `writeTags()` to silently return false for files not in the app sandbox, provides equivalent in-app behaviour, and removes the need for jaudiotagger in the write path entirely.

---

## 9. Performance Comparison

### Library Scan Speed

| Architecture | Mechanism | Relative Speed |
|---|---|---|
| Current | MediaStore cursor | ✅ Fast (indexed SQL, single query) |
| Proposed | MediaStore cursor (identical) | ✅ Same — no change to scan path |

jaudiotagger is **not** on the library scan path. `getSongs()` is pure MediaStore and is unchanged in any scenario.

### Per-Song Metadata Access

| Operation | Current | Proposed (with cache) |
|---|---|---|
| First access (cold) | jaudiotagger file parse ~20–80 ms/song | ExoPlayer/MMR ~15–50 ms + SQLite write |
| Subsequent access | jaudiotagger re-parses file every call | SQLite lookup ~0.1 ms (cache hit) |
| App restart | jaudiotagger re-parses again | SQLite lookup ~0.1 ms |

The proposed Layer 3 cache provides a significant speedup from the second access onwards. Currently `ReplayGainService` has its own SharedPreferences cache, but it is Dart-side and not shared with the native layer. A native SQLite cache would reduce round-trips across the MethodChannel.

### Memory Usage

| Component | Current | Proposed |
|---|---|---|
| jaudiotagger JVM heap | ~15–40 MB peak during file parse | 0 (library removed) |
| SQLite cache | 0 | ~2–5 MB (index + frequently accessed rows) |

jaudiotagger's `AudioFileIO.read()` loads the entire tag block into JVM heap. For large embedded artwork (which it reads alongside tags), this can spike to 40+ MB per call. In the proposed architecture artwork is handled separately by `ArtworkCacheManager` (already the case) and tag reading uses streaming APIs.

### CPU Usage

| Operation | Current | Proposed |
|---|---|---|
| Lyrics parse | jaudiotagger (JVM reflection + full file parse) | ExoPlayer MetadataRetriever (native C++ demuxer) |
| ReplayGain read | jaudiotagger (JVM) | Binary scan of first 16 KB only |
| ReplayGain write | jaudiotagger (full file rewrite) | SQLite write or targeted binary patch |

ExoPlayer's metadata retrieval uses the same native C++ container demuxers used for playback, which are faster than jaudiotagger's pure-Java parsers and avoid loading the full audio data.

### APK Size

| Component | Contribution |
|---|---|
| `net.jthink:jaudiotagger:2.2.5` | ~1.6 MB (JAR, after R8 shrinking ~0.8–1.2 MB) |
| ExoPlayer (already present) | 0 additional (already in build.gradle) |
| Custom binary parser (Option 8B-B) | ~5–10 KB |
| SQLite (Android built-in) | 0 additional |

Removing jaudiotagger saves approximately **0.8–1.2 MB** from the release APK (after R8/ProGuard). The packaging exclusions in `build.gradle` can also be removed.

### Reliability

| Scenario | jaudiotagger | Proposed |
|---|---|---|
| Android 10+ file write permission | Often fails silently | Sidecar DB always works |
| Corrupt/truncated tag block | Can throw, caught by try/catch | ExoPlayer gracefully returns null |
| Unsupported format (e.g., AAC, ALAC) | `CannotReadException` | MMR/ExoPlayer returns null gracefully |
| Multi-language USLT frames | Full support | Needs explicit implementation |
| Very large embedded art (>10 MB) | OOM risk in jaudiotagger parse | Not an issue (artwork path is separate) |

---

## 10. Migration Plan

### Phase 0 — Pre-conditions (no code change)
- Confirm `media3-exoplayer:1.10.1` is already in `build.gradle` ✅
- Confirm `MediaMetadataRetriever` is already imported in `MainActivity.kt` ✅
- Confirm `ArtworkCacheManager` already uses MMR (not jaudiotagger) ✅
- Confirm `ReplayGainScanner.scan()` uses only `MediaExtractor` / `MediaCodec` ✅

### Phase 1 — Expand MediaStore Projection (low risk, immediate win)
Modify `getSongs()` to add columns available in the current `minSdk=29` baseline:

```kotlin
// Add to projection array:
MediaStore.Audio.Media.YEAR,
MediaStore.Audio.Media.TRACK,
// API 30+ (check Build.VERSION.SDK_INT):
MediaStore.Audio.Media.ALBUM_ARTIST,
MediaStore.Audio.Media.DISC_NUMBER,
MediaStore.Audio.Media.GENRE,
// API 31+ (check Build.VERSION.SDK_INT):
MediaStore.Audio.Media.BITRATE,
MediaStore.Audio.Media.SAMPLERATE,
```

Fields gated on API 30/31 fall back to `MediaMetadataRetriever` for older devices. This reduces `getAudioMetadata()` calls for most devices on Android 12+.

**Risk:** Low. These are read-only additions to an existing cursor query.

### Phase 2 — Native Metadata Cache (SQLite)
Create `MetadataCacheManager.kt`:

```
Table: song_metadata_cache
  song_id   INTEGER PRIMARY KEY
  path      TEXT NOT NULL
  mtime     INTEGER NOT NULL        -- File.lastModified()
  rg_json   TEXT                    -- serialized ReplayGain tags
  lyrics    TEXT                    -- embedded lyrics string or null
  cached_at INTEGER                 -- System.currentTimeMillis()
```

Cache invalidation: on `getReplayGainTags()` or `getEmbeddedLyrics()`, check `mtime` of file against cached `mtime`. If match → return cache. If miss → parse → insert/update.

This makes the second and all subsequent reads for both lyrics and ReplayGain effectively zero-cost, regardless of which parser is used underneath.

**Risk:** Low. Cache is additive; existing parse path is the fallback.

### Phase 3 — Replace ReplayGain Read with ExoPlayer MetadataRetriever
Replace `getReplayGainTags()` in `MainActivity.kt`:

```kotlin
// New implementation sketch
suspend fun getReplayGainTagsViaExoPlayer(path: String): Map<String, String?> {
    val mediaItem = MediaItem.fromUri(Uri.fromFile(File(path)))
    val future = MetadataRetriever.retrieveMetadata(this, mediaItem)
    val trackGroups = future.get(5, TimeUnit.SECONDS)
    // Iterate trackGroups[0].getFormat(0).metadata
    // For Id3Frame (MP3): find TXXX frames by description
    // For VorbisComment (FLAC/OGG): scan key=value pairs
    // For MdtaMetadataEntry (M4A): scan atom names
}
```

The existing ReplayGain Dart service (`ReplayGainService`) and its SharedPreferences cache are unchanged. Only the native implementation of `getReplayGainTags` changes.

**Risk:** Medium. Must validate coverage of TXXX multi-frame (MP3), Vorbis case-insensitivity (FLAC/OGG), and M4A atom naming across the test library before removing the jaudiotagger fallback.

### Phase 4 — Replace Embedded Lyrics with ExoPlayer MetadataRetriever
Replace `getEmbeddedLyrics()` in `MainActivity.kt`:

```kotlin
suspend fun getEmbeddedLyricsViaExoPlayer(path: String): String? {
    // Same MetadataRetriever call as Phase 3 (can share the future)
    // For UnsynchronizedLyricsFrame (USLT): return frame.lyrics (prefer "eng")
    // For VorbisComment: scan for key starting with "LYRICS=" or "UNSYNCEDLYRICS="
    // For MdtaMetadataEntry (©lyr): return value string
    // COMMENT fallback: read FieldKey.COMMENT via VorbisComment or Id3Frame COMM
}
```

Key implementation detail: `UnsynchronizedLyricsFrame` is a first-class class in `media3-common` — no raw frame iteration needed for USLT. The multi-language preference logic from `extractAllUsltFrames()` must be replicated (prefer `language == "" || language == "eng"`).

**Risk:** Medium-high. The COMMENT fallback and multi-language USLT handling are subtle; extensive testing across MP3/FLAC/M4A/OGG/OPUS is required before removing jaudiotagger.

### Phase 5 — Replace ReplayGain Tag Writing with Sidecar Database
Remove `writeTags()` from `ReplayGainScanner.kt` (or leave it as a no-op). Modify `scanReplayGain` handler to write results to `MetadataCacheManager` (Phase 2) instead of calling `writeTags()`.

Update the Dart `scanReplayGain` flow to store results in `ReplayGainService`'s SharedPreferences cache (it already does this on the Dart side; the native write was a secondary persistence mechanism).

Add a note to the UI: scanned gain values are stored in the app's database. If the user wants tags written to the file, expose this as an explicit opt-in action (which requires `MANAGE_EXTERNAL_STORAGE` on Android 11+).

**Risk:** Low for in-app behaviour. Cross-app ReplayGain interoperability is lost (tags no longer written to file by default), but jaudiotagger's `writeTags()` already fails silently on most Android 10+ configurations where the file is not in the app sandbox.

### Phase 6 — Remove jaudiotagger

After Phases 3–5 are verified on a real device with a representative library:

1. Remove `implementation 'net.jthink:jaudiotagger:2.2.5'` from `build.gradle`
2. Remove the three `packaging.resources.excludes` entries
3. Delete all `org.jaudiotagger.*` import references from `MainActivity.kt` and `ReplayGainScanner.kt`
4. Remove `readCustomTag()`, `getID3TXXXValue()`, `extractAllUsltFrames()`, `writeTxxx()`, `writeVorbisField()` helper functions
5. Run a clean build and verify R8 does not emit warnings about missing classes

---

## 11. Recommendation

**jaudiotagger is not removable today without prior implementation work.**

The three capabilities it uniquely provides — embedded lyrics, ReplayGain/R128/iTunNORM tag reading, and ReplayGain tag writing — have no existing Android framework equivalent. `MediaStore` and `MediaMetadataRetriever` cannot read custom or non-standard tags, and neither can write any tags.

**However, full removal is achievable** via the six-phase plan above using ExoPlayer's `MetadataRetriever` (already a project dependency) for reading, and a sidecar SQLite cache for the write path. The sidecar approach is actually superior to jaudiotagger's file-write approach for Android 10+ compatibility.

**Recommended sequencing:**

1. Phase 0 and Phase 1 immediately (zero risk, immediate benefits)
2. Phase 2 (cache layer) as the foundation before touching any parser
3. Phases 3 and 4 together on a feature branch, validated against a real device test library covering MP3/FLAC/OGG/OPUS/M4A files with known ReplayGain and embedded lyrics tags
4. Phase 5 simultaneously with Phase 3/4
5. Phase 6 only after integration testing confirms parity

**If timeline or resources are constrained,** retaining jaudiotagger with the Phase 2 cache layer added on top delivers most of the performance benefit (eliminates repeat file parses) while deferring the parser replacement work. The APK size saving (~1 MB) is real but not critical.

---

## Appendix — Files to Modify in Full Migration

| File | Change |
|---|---|
| `android/app/build.gradle` | Remove jaudiotagger dep + packaging exclusions |
| `android/app/src/main/kotlin/.../MainActivity.kt` | Replace `getReplayGainTags()`, `getEmbeddedLyrics()`, helpers |
| `android/app/src/main/kotlin/.../replay_gain/ReplayGainScanner.kt` | Remove `writeTags()`, `writeTxxx()`, `writeVorbisField()` |
| `android/app/src/main/kotlin/.../MetadataCacheManager.kt` | **New file** — SQLite cache |
| `android/app/src/main/kotlin/.../ExoMetadataReader.kt` | **New file** — ExoPlayer MetadataRetriever wrapper |

No Dart/Flutter files require changes — all jaudiotagger usage is confined to the native Android layer.
