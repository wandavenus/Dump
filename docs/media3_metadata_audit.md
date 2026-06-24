# Media3 1.10.1 Metadata Engine — Audit & Architecture

**Date:** June 2026
**Target:** Android 11 (API 29+), MIUI 12/12.1.x, compileSdk 36, Media3 1.10.1

---

## Arsitektur yang Diterapkan

```
MediaStore
    ↓
Media3 MetadataRetriever  (@UnstableApi)
    • TextInformationFrame (TXXX) → ReplayGain / R128 / iTunNORM  [MP3, WAV]
    • VorbisComment               → ReplayGain / R128 / Lyrics     [FLAC, OGG, OPUS]
    • MdtaMetadataEntry "©lyr"    → Lyrics                         [M4A]
    ↓
MetadataCacheDb  (SQLite, WAL, keyed by song_id + file mtime)
    ↓
Flutter
```

---

## Format yang Didukung

### Lirik

| Format | Tag | Kelas Media3 | Status |
|---|---|---|---|
| FLAC | Vorbis `LYRICS` / `UNSYNCEDLYRICS` | `VorbisComment` | ✅ |
| OGG | Vorbis `LYRICS` / `UNSYNCEDLYRICS` | `VorbisComment` | ✅ |
| OPUS | Vorbis `LYRICS` / `UNSYNCEDLYRICS` | `VorbisComment` | ✅ |
| M4A | `©lyr` mdta atom (UTF-8) | `MdtaMetadataEntry` | ✅ |
| MP3 | USLT (ID3v2) | — | ❌ Tidak didukung (tidak ada di library) |

### ReplayGain / Loudness

| Format | Tag | Kelas Media3 | Status |
|---|---|---|---|
| MP3 / WAV | `REPLAYGAIN_TRACK_GAIN` (TXXX) | `TextInformationFrame` | ✅ |
| MP3 / WAV | `REPLAYGAIN_ALBUM_GAIN` (TXXX) | `TextInformationFrame` | ✅ |
| MP3 / WAV | `R128_TRACK_GAIN` (TXXX) | `TextInformationFrame` | ✅ |
| MP3 / WAV | `ITUNNORM` / `ITUN NORM` (TXXX) | `TextInformationFrame` | ✅ |
| FLAC / OGG / OPUS | `REPLAYGAIN_TRACK_GAIN` | `VorbisComment` | ✅ |
| FLAC / OGG / OPUS | `REPLAYGAIN_ALBUM_GAIN` | `VorbisComment` | ✅ |
| FLAC / OGG / OPUS | `R128_TRACK_GAIN` | `VorbisComment` | ✅ |
| FLAC / OGG / OPUS | `R128_ALBUM_GAIN` | `VorbisComment` | ✅ |

---

## Dependensi Gradle

```groovy
implementation 'androidx.media3:media3-exoplayer:1.10.1'
implementation 'androidx.media3:media3-session:1.10.1'
implementation 'androidx.media3:media3-ui:1.10.1'
// MdtaMetadataEntry (M4A ©lyr) ada di artifact terpisah sejak Media3 1.x
implementation 'androidx.media3:media3-container:1.10.1'
```

---

## Kompatibilitas Android 11 + MIUI 12

| Syarat | Mekanisme | Status |
|---|---|---|
| Android 11 (API 30) | minSdk 29; semua API yang dipakai ≥ API 21 | ✅ |
| MIUI 12 / 12.1.x | `Uri.fromFile()` — baca langsung dari filesystem, bypass content resolver MIUI | ✅ |
| Scoped Storage | Path dari MediaStore dapat diakses tanpa `MANAGE_EXTERNAL_STORAGE` | ✅ |
| Tanpa root | Pure MediaStore + file path reads | ✅ |
| Tanpa SAF | Tidak ada `DocumentFile` atau SAF picker | ✅ |

---

## Catatan Kelas API

| Kelas | Artifact | API Status |
|---|---|---|
| `TextInformationFrame` | `media3-extractor` | Public `@UnstableApi` |
| `VorbisComment` | `media3-extractor` | Public `@UnstableApi` |
| `MdtaMetadataEntry` | `media3-container` | Public `@UnstableApi` |

---

## Format Tidak Didukung

**MP3 embedded lyrics (USLT)** tidak diimplementasikan karena:
- Library musik proyek tidak mengandung file MP3.
- Media3 1.10.1 memetakan USLT ke `BinaryFrame`, bukan `UnsynchronizedLyricsFrame` (issue [#922](https://github.com/androidx/media/issues/922), masih open).
- Keputusan proyek: stabilitas build lebih penting dari dukungan format yang tidak digunakan.
