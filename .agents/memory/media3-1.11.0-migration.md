---
name: Media3 1.11.0 migration + audit
description: Upgrade 1.11.0-rc01 → 1.11.0 stable is a one-line version bump, fully safe for this repo (all removed symbols unused, inspector MetadataRetriever already in use); behavior changes to re-test on Mi 9T: dynamic scheduling, 500ms PCM buffer, 100ms audio grace period, MP3 gapless durations, positionOffsetUs now set, onConnect default read-only.
---

# Media3 1.11.0 Migration + Audit (2026-08-08)

## What happened
- Repo history: initial import (`68ec395`) already pinned `1.11.0-rc01` with the code pre-migrated; commit `06fec0f` changed **only** `media3_version = "1.11.0-rc01"` → `"1.11.0"` (1 line).
- 1.11.0 stable released **2026-08-05**; stable == rc01 + bugfixes, no extra API removals. Release notes: `RELEASENOTES.md` in androidx/media@1.11.0.
- Verdict: **bumping the number alone is safe — no code adjustments needed.**

## Audit result (all breaking-change points are CLEAN)

| 1.11.0 breaking change | Project status |
|---|---|
| `androidx.media3.exoplayer.MetadataRetriever` REMOVED → use `media3-inspector` | ✅ `ExoMetadataReader.kt` already imports `androidx.media3.inspector.MetadataRetriever`. All other `MediaMetadataRetriever` matches are the Android framework class (`android.media.*`) — unaffected |
| `AudioSink.configure` params → data class (breaking for `ForwardingAudioSink` overrides) | ✅ no `ForwardingAudioSink`/`AudioSink.configure` overrides in repo |
| `AudioProcessor.StreamMetadata` now carries Timeline + correct `positionOffsetUs` | ✅ no manual construction; `SignalsmithStretchAudioProcessor.kt:734` only *reads* it (behavior change, see below) |
| Stricter `MediaSession` threading (getters throw `IllegalStateException` off app looper; void methods auto-post) | ✅ `Media3PlaybackService` touches session only via `Handler(Looper.getMainLooper())`; `ioExecutor` work posts back; `NowPlayingOverlayActivity` controller on `mainExecutor` |
| `onConnect` default → read-only for untrusted controllers | ⚠️ project does not override `onConnect`, so new default applies — fine for a music player (system media buttons still work) |
| Removed symbols: `MediaExtractorCompat`, `MotionPhotoMetadata` (extractor), `DummyTrackOutput`, `DummyExtractorOutput`, `C.generateAudioSessionIdV21`, `FLAG_READ_MOTION_PHOTO_METADATA`, `FrameExtractor` | ✅ zero usages |

## Behavior changes to re-test on Mi 9T (not breaking)
1. **Dynamic scheduling enabled by default** in ExoPlayer playback work loop.
2. **Default PCM buffer = fixed 500 ms** (`DefaultAudioTrackBufferSizeProvider`).
3. **100 ms grace period** on ready→not-ready in audio renderers — interacts with crossfade/gapless transitions.
4. **MP3 durations now gapless-aware** (Xing/Info) — duration display may change for some MP3s.
5. **`StreamMetadata.positionOffsetUs` now actually set** — stretch/pitch time-based processing may behave differently (this is the intended fix).
6. `Format.channelMask` explicit; `MediaSource.prepareSource` new overload (old still called by default).

## Changes in 1.11.0 that FIX known project pain points
- Artwork double-downscaling blur in notifications fixed (#3134) — relevant to our notification artwork investigations.
- `ForegroundServiceStartNotAllowedException` crashes fixed in `MediaNotificationManager` + `MediaSessionService.stopSelfSafely()` (#3270, #3310).
- Spurious `onMediaItemTransition()` during seek within one item fixed (#3248).
- `MediaNotificationManager` deadlock/`IllegalStateException` + timeline merge crash fixes.

## Jellyfin FFmpeg decoder
- `org.jellyfin.media3:media3-ffmpeg-decoder:1.9.0+1` (latest, built on Media3 1.9.0) stays compatible: media3 stable APIs are binary-compatible; transitive deps already excluded so Gradle resolves to pinned 1.11.0. This combination ran fine on rc01.

## Cleanup done
- `android/app/build.gradle` comments (lines ~33, ~150) updated from "pinned 1.10.1" → "pinned stable versions" (comment-only, 2/2 lines).

## Improvements applied (2026-08-08) — zero-trade-off pass
Based on the 1.11.0 `@Deprecated` map extracted from official `-sources.jar`:
1. **`FallbackBitmapLoader` → `androidx.media3.common.util.BitmapLoader`** — `session.BitmapLoader` is deprecated (extends common.util.BitmapLoader, no added methods); same behavior, future-proof. `MediaSession.Builder.setBitmapLoader` already accepts the common type.
2. **`setEnableAudioTrackPlaybackParams` → `setEnableAudioOutputPlaybackParameters`** — renamed on `DefaultAudioSink.Builder` (both player builds); old name is deprecated in 1.11.0 and delegates to the new one. Behavior identical.
3. **`DefaultExtractorsFactory().setDisableArtworkMetadata(true)`** (both normal + bit-perfect player builds) — zero-trade-off: repo greps confirm NOTHING reads `MediaItem.mediaMetadata.artworkData` (Dart or Kotlin); artwork flows via `ArtworkCacheManager` / `FallbackBitmapLoader` (`MediaMetadataRetriever`) instead. Saves memory/time parsing embedded covers on MP3/MP4/FLAC.
No changes needed: `CommandButton.Builder(int)` already new API; `TagBuilder` already uses `TextInformationFrame.values.firstOrNull()` (not deprecated `.value`); no `MediaStyleNotificationHelper` no-op calls; `MediaController`/`MediaSession` usage is non-deprecated.

## Verification limitations + next steps
- Freebuff env has NO Java/Android SDK → cannot build APK here. Must verify via `setup-flutter.sh` + `build-apk.sh` (Replit/CI) and smoke test on Mi 9T.
- Smoke-test checklist: crossfade transitions, gapless MP3, notification artwork sharpness, offload mode (AudioOffloadManager), ReplayGain/bit-perfect switching, stretch/pitch during seek.
