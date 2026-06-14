---
name: jaudiotagger Android
description: Library untuk baca embedded lyrics dari MP3/M4A/FLAC/OGG/WAV; perlu packagingOptions untuk exclude duplicate files.
---

## Dependency
```gradle
// android/app/build.gradle
dependencies {
    implementation 'net.jthink:jaudiotagger:2.2.5'
}
```

## PackagingOptions (wajib)
```gradle
packagingOptions {
    exclude 'META-INF/LICENSE'
    exclude 'META-INF/NOTICE'
    exclude 'META-INF/*.kotlin_module'
}
```

## Usage di MainActivity.kt
```kotlin
import org.jaudiotagger.audio.AudioFileIO
import org.jaudiotagger.tag.FieldKey

private fun getEmbeddedLyrics(path: String): String? {
    val audioFile = AudioFileIO.read(File(path))
    val tag = audioFile?.tag ?: return null
    val lyrics = tag.getFirst(FieldKey.LYRICS)
    if (!lyrics.isNullOrBlank()) return lyrics.trim()
    // fallback COMMENT jika multi-line
    val comment = tag.getFirst(FieldKey.COMMENT)
    return if (!comment.isNullOrBlank() && comment.contains('\n')) comment.trim() else null
}
```

## Formats
- MP3: ID3v2 USLT tag → `FieldKey.LYRICS`
- M4A: iTunes `©lyr` → `FieldKey.LYRICS`
- FLAC/OGG: Vorbis LYRICS field → `FieldKey.LYRICS`
- WAV: ID3 embedded → `FieldKey.LYRICS`

## MethodChannel
Method: `getEmbeddedLyrics` di channel `musicplayer/media_store` (bukan audio_effects).

**Why:** jaudiotagger 2.2.5 adalah versi paling stabil untuk Android (dipakai luas di Android media apps). Versi 3.x masih beta untuk beberapa format.
