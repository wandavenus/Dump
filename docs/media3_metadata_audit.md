# Media3 1.10.1 Metadata Engine Audit

**Date:** June 2026
**Scope:** Lyrics extraction capability, ReplayGain/R128, compatibility with Android 11 + MIUI 12
**Conclusion:** Pure Media3 lyrics extraction is **NOT fully achievable** in 1.10.1.

---

## 1. Audit of Media3 1.10.1 Public Metadata APIs

### 1.1 Classes Inspected

| Class | Package | Artifact | API Status |
|---|---|---|---|
| `TextInformationFrame` | `androidx.media3.extractor.metadata.id3` | `media3-extractor` | Public `@UnstableApi` |
| `VorbisComment` | `androidx.media3.extractor.metadata.vorbis` | `media3-extractor` | Public `@UnstableApi` |
| `UnsynchronizedLyricsFrame` | `androidx.media3.extractor.metadata.id3` | `media3-extractor` | Public `@UnstableApi` — **exists but extractor does not produce it for MP3 USLT** |
| `BinaryFrame` | `androidx.media3.extractor.metadata.id3` | `media3-extractor` | Public `@UnstableApi` — what MP3 USLT actually becomes |
| `MdtaMetadataEntry` | `androidx.media3.container` | `media3-container` (**separate artifact**) | Public `@UnstableApi` — requires added dependency |
| `SynchronizedLyricsFrame` | `androidx.media3.extractor.metadata.id3` | `media3-extractor` | Public `@UnstableApi` — SYLT timestamped lyrics only |

### 1.2 Per-Lyrics-Format Accessibility

#### USLT — MP3 unsynchronized lyrics (ID3v2 USLT frame)

- `UnsynchronizedLyricsFrame` **class exists** in `media3-extractor:1.10.1`.
- `UnsynchronizedLyricsFrame` has public fields: `language` (ISO 639-2), `description`, `lyrics` (String).
- **HOWEVER**: The Media3 MP3 ID3 parser in 1.10.1 does **not produce `UnsynchronizedLyricsFrame`** instances. USLT frames arrive as `BinaryFrame` with `id = "USLT"` and opaque `data: ByteArray`.
- This is tracked in: **[androidx/media issue #922](https://github.com/androidx/media/issues/922)** — "Add support for ID3 USLT unsynced lyrics tag" — **OPEN**, labelled "low priority".
- Related: **[androidx/media issue #1435](https://github.com/androidx/media/issues/1435)** — "Provide Option to read unsynced lyrics using Metadata or ID3Tags" — **OPEN**.
- **Verdict: USLT via Media3 is IMPOSSIBLE in 1.10.1.** `MediaMetadataRetriever` is required.

#### M4A `©lyr` — iTunes lyrics atom

- `MdtaMetadataEntry` is **publicly accessible** in `media3-container:1.10.1`.
- Requires adding `implementation 'androidx.media3:media3-container:1.10.1'` to `build.gradle`.
- `MdtaMetadataEntry.key == "©lyr"` with `typeIndicator = TYPE_INDICATOR_STRING (1)` carries lyrics as UTF-8 bytes.
- **Verdict: M4A ©lyr IS accessible via Media3.** Added to `ExoMetadataReader` with MMR fallback.

#### FLAC / OGG / OPUS `LYRICS` / `UNSYNCEDLYRICS` (Vorbis Comments)

- `VorbisComment` is public in `media3-extractor:1.10.1`. Already in use.
- Keys `LYRICS`, `UNSYNCEDLYRICS`, `UNSYNCED LYRICS` are all handled.
- **Verdict: FULLY accessible via Media3.** No change needed; working correctly pre-audit.

### 1.3 Is `BinaryFrame` a viable raw-decode fallback for MP3 USLT?

No. The USLT ID3 frame structure is:

```
Text encoding   $xx
Language        $xx xx xx   (3 bytes ISO 639-2)
Content descriptor  <text string> $00 (00)   (NUL-terminated, encoding-aware)
Lyrics/text     <full text string according to encoding>
```

Manually decoding raw `BinaryFrame.data` as `String(data)` is unreliable because:
1. The encoding byte (Latin-1 vs UTF-16 vs UTF-8) is embedded in the frame.
2. The content descriptor field of variable length precedes the lyrics.
3. Different taggers (Mp3tag, MusicBrainz Picard, Beets, etc.) write different encodings.

`MediaMetadataRetriever` handles all encoding variants transparently via the platform's native metadata parser. This is the correct and only reliable approach for MP3 USLT in 1.10.1.

---

## 2. Media3 1.10.1 Limitations — Evidence

### 2.1 Issue #922 (Primary Evidence)

**URL:** https://github.com/androidx/media/issues/922
**Title:** "Add support for ID3 USLT unsynced lyrics tag"
**Opened:** December 27, 2023
**Status:** OPEN
**Labels:** `enhancement`, `low priority`

> *"when I read the tag in the audio with MetadataRetriever, it works well in FLAC, but it cannot read the contents of the UNSYNCEDLYRICS tag in MP3, it is classified into BinaryFrame and cannot parse the data inside."*

### 2.2 Issue #1435 (Corroborating Evidence)

**URL:** https://github.com/androidx/media/issues/1435
**Title:** "Provide Option to read unsynced lyrics using Metadata or ID3Tags"
**Status:** OPEN
**Context:** Developers request a first-class API for USLT; existing workarounds check `BinaryFrame.id == "USLT"` and manually decode bytes — which is brittle (see §1.3 above).

### 2.3 Why `UnsynchronizedLyricsFrame` exists but is never produced

The class was added to the public API surface as part of a forward-design, but the MP3 extractor (`Mp3Extractor.kt` → `Id3Decoder.kt`) was not updated to instantiate it. The ID3 decoder's `switch` statement on frame ID still routes `USLT` through the generic binary path. This split between API class existence and extractor behaviour is the root cause of the confusion.

---

## 3. Support Validation Matrix

### Lyrics

| Format | Tag | Source in 1.10.1 | Status |
|---|---|---|---|
| MP3 | USLT (ID3v2) | `MediaMetadataRetriever` | ✅ Working (MMR required) |
| FLAC | Vorbis `LYRICS` | Media3 `VorbisComment` | ✅ Working |
| FLAC | Vorbis `UNSYNCEDLYRICS` | Media3 `VorbisComment` | ✅ Working |
| OGG | Vorbis `LYRICS` | Media3 `VorbisComment` | ✅ Working |
| OPUS | Vorbis `LYRICS` | Media3 `VorbisComment` | ✅ Working |
| M4A | `©lyr` atom | Media3 `MdtaMetadataEntry` + MMR fallback | ✅ Working |

### ReplayGain / Loudness

| Format | Tag | Source in 1.10.1 | Status |
|---|---|---|---|
| MP3 | `REPLAYGAIN_TRACK_GAIN` (TXXX) | Media3 `TextInformationFrame` | ✅ Working |
| MP3 | `REPLAYGAIN_ALBUM_GAIN` (TXXX) | Media3 `TextInformationFrame` | ✅ Working |
| MP3 | `R128_TRACK_GAIN` (TXXX) | Media3 `TextInformationFrame` | ✅ Working |
| MP3 | `ITUNNORM` (TXXX) | Media3 `TextInformationFrame` | ✅ Working |
| FLAC | `REPLAYGAIN_TRACK_GAIN` | Media3 `VorbisComment` | ✅ Working |
| FLAC | `REPLAYGAIN_ALBUM_GAIN` | Media3 `VorbisComment` | ✅ Working |
| FLAC | `R128_TRACK_GAIN` | Media3 `VorbisComment` | ✅ Working |
| OGG | `REPLAYGAIN_TRACK_GAIN` | Media3 `VorbisComment` | ✅ Working |
| OGG | `R128_TRACK_GAIN` | Media3 `VorbisComment` | ✅ Working |
| OPUS | `REPLAYGAIN_TRACK_GAIN` | Media3 `VorbisComment` | ✅ Working |
| OPUS | `R128_TRACK_GAIN` | Media3 `VorbisComment` | ✅ Working |
| M4A | `iTunNORM` (freeform `----` atom) | Not extracted — freeform atoms not in `MdtaMetadataEntry` | ⚠️ Not supported |
| M4A | `REPLAYGAIN_TRACK_GAIN` (freeform) | Not extracted by Media3 extractor | ⚠️ Not supported |

**Note on M4A loudness:** iTunNORM and ReplayGain in M4A files are stored in QuickTime freeform (`----`) atoms, not `mdta` atoms. Media3 1.10.1 does not surface freeform atoms as structured entries. If M4A loudness normalisation is required, it must be added via `MediaMetadataRetriever` key `METADATA_KEY_CD_TRACK_NUMBER` workaround (unreliable) or via a native freeform atom parser.

---

## 4. Android 11 + MIUI 12 Compatibility Assessment

| Requirement | Mechanism | Compatible |
|---|---|---|
| Android 11 (API 30) support | `minSdk 29`; all APIs used are ≥ API 21 | ✅ |
| MIUI 12 / 12.1.x | `Uri.fromFile()` bypasses MIUI content resolver bugs | ✅ |
| Scoped storage | File path from MediaStore is app-accessible without MANAGE_EXTERNAL_STORAGE | ✅ |
| No MANAGE_EXTERNAL_STORAGE | Not requested; MediaStore provides paths | ✅ |
| No root required | Pure MediaStore + file path reads | ✅ |
| No SAF interaction | `Uri.fromFile` + direct path; no `DocumentFile` or SAF picker | ✅ |
| Content:// permission regression | Avoided by `Uri.fromFile` for ExoPlayer; MMR uses direct path via `setDataSource(String)` | ✅ |

---

## 5. Final Architecture Decision

```
MediaStore
    ↓
Layer A — android.media.MediaMetadataRetriever
    Scope: MP3 + M4A/AAC only (skipped for FLAC/OGG/OPUS)
    Tags:  USLT lyrics (MP3), ©lyr fallback (M4A)
    Why:   Media3 issue #922 — MP3 USLT → BinaryFrame. Not fixable
           in 1.10.1 without upstream patch.
    ↓
Layer B — androidx.media3.exoplayer.MetadataRetriever  (@UnstableApi)
    Tags:  TextInformationFrame (TXXX) → ReplayGain/R128/iTunNORM  [MP3]
           VorbisComment                → ReplayGain/R128 + LYRICS  [FLAC/OGG/OPUS]
           UnsynchronizedLyricsFrame   → MP3 USLT  [future-proof; no-op in 1.10.1]
           MdtaMetadataEntry "©lyr"    → M4A lyrics [media3-container:1.10.1]
    ↓
MetadataCacheDb  (SQLite, song_id + mtime key, WAL mode)
    ↓
Flutter
```

**Pure Media3 is NOT achievable in 1.10.1 for MP3 USLT.**
`MediaMetadataRetriever` is a necessary component of the production architecture until Media3 issue #922 is resolved upstream and released in a new stable version.

---

## 6. Future Migration Path

When Media3 issue #922 is resolved (the MP3 ID3 parser is updated to emit `UnsynchronizedLyricsFrame` instead of `BinaryFrame` for USLT):

1. The `UnsynchronizedLyricsFrame` branch in `ExoMetadataReader.TagBuilder.consume()` will activate automatically — no code change needed.
2. The `needsMmrLyrics` guard in `ExoMetadataReader.read()` can then have `"mp3"` removed from its condition set.
3. `MediaMetadataRetriever` can then be removed entirely if M4A is also covered (check `MdtaMetadataEntry` parity at that time).

To check if the fix is available: search for the issue #922 PR merge in the Media3 `RELEASENOTES.md` and look for `UnsynchronizedLyricsFrame` in the extractor changelog.
