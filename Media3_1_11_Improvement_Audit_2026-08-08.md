# Media3 1.11.0 Improvement Audit — 2026-08-08

## Scope

Inventory + source-level audit of every Media3/ExoPlayer usage in the repo, looking for
improvements with **zero trade-off**. Baseline: `media3_version = 1.11.0` (stable, 2026-08-05).

## Inventory (files touching androidx.media3)

- **Build:** `android/app/build.gradle` (7 media3 artifacts pinned + Jellyfin ffmpeg-decoder 1.9.0+1).
- **Kotlin (30 files):** `Media3PlaybackService.kt` (dual-player + bit-perfect, MediaSession, 27 imports),
  `ActivePlayerProxy.kt`, `FallbackBitmapLoader.kt`, `NowPlayingOverlayActivity.kt`,
  `ServiceShutdownCoordinator.kt`, `audio_focus/AudioFocusManager.kt`, `audio_offload/AudioOffloadManager.kt`,
  `crossfade/{CrossfadeController,PreloadManager}.kt`, `diagnostics/CrossfadeTimelineLogger.kt`,
  `effects/{NativeDspAudioProcessor,SignalsmithStretchAudioProcessor,StereoWideningAudioProcessor,
  StereoWidthManager,StretchAwareAudioProcessorChain,StretchManager}.kt`, `metadata/{ExoMetadataReader,TagBuilder}.kt`,
  `notification/PlaybackNotificationManager.kt`, `queue/{QueueManager,QueueSync}.kt`,
  `sleep_timer/SleepTimerManager.kt`, `transport/{PlayPauseFadeController,TransportCommands,TransportState}.kt`,
  `utils/{MediaItemFactory,TrackMapper}.kt`, `MainActivity.kt`.
- **Tests:** `android/app/src/test/kotlin/.../ActivePlayerProxyTest.kt` etc.
- **Docs/memory:** `docs/media3_metadata_audit.md`, `docs/audit/docs_media3_migration_audit.md`,
  `.agents/memory/media3-*.md` (migration, transport, foreground-deadline, option-b, 1.11.0 note).

## Method

Cross-referenced every project usage against the official 1.11.0 `-sources.jar` deprecation map
(downloaded from Google Maven for media3-{common,exoplayer,session,extractor,container,inspector,ui}).

## Findings

### Applied (zero trade-off)

| # | Change | Files | Why it is safe |
|---|---|---|---|
| A1 | `FallbackBitmapLoader` now implements `androidx.media3.common.util.BitmapLoader` (was deprecated `androidx.media3.session.BitmapLoader`) | `FallbackBitmapLoader.kt` | `session.BitmapLoader extends common.util.BitmapLoader` with zero added methods; `MediaSession.Builder.setBitmapLoader` already accepts the common type. Behavior identical. |
| A2 | `DefaultAudioSink.Builder.setEnableAudioTrackPlaybackParams` → `setEnableAudioOutputPlaybackParameters` (2 sites: normal + bit-perfect player) | `Media3PlaybackService.kt:982,1123` | Old method is `@Deprecated` in 1.11.0 and delegates to the new one — pure rename, no behavior change. |
| A3 | `DefaultExtractorsFactory().setDisableArtworkMetadata(true)` (2 sites: normal + bit-perfect player) | `Media3PlaybackService.kt:1037,1145` | Repo-wide grep (Kotlin + Dart) confirms **nothing** reads `MediaItem.mediaMetadata.artworkData`. Artwork is served by `ArtworkCacheManager` / `FallbackBitmapLoader` via `MediaMetadataRetriever` / content URIs — independent of the extractor's embedded-artwork parse. Saves memory + parse time on MP3/MP4/FLAC with embedded covers. |

### Checked and intentionally NOT changed (already clean)

- `CommandButton.Builder(int)` — project already uses the new icon-constant API (deprecated no-arg `Builder()` / `setIconResId` unused).
- `TagBuilder.kt` — already reads `TextInformationFrame.values.firstOrNull()` (new API); deprecated `.value` unused.
- `MediaStyleNotificationHelper` — no deprecated no-op calls (`setShowCancelButton`/`setCancelButtonIntent`) present.
- `MediaController`/`MediaSession` — usage is non-deprecated (`buildAsync`, `releaseFuture`, `setMediaButtonPreferences`, `onGetSession`).
- `DefaultLoadControl.Builder` — only stable members used.
- `MediaMetadataRetriever` matches are the Android framework class — unaffected by Media3 1.11.0 removals.

### Rejected (would carry a trade-off)

- `ExoPlayer.Builder.enablePerStreamMediaProgression()` — experimental/`@UnstableApi`; behavioral.
- Changing load-control buffer sizes / PCM buffer defaults — latency↔robustness trade-off.
- HAGC / MP4 chapter metadata / `discSubtitle` — feature additions, not improvements; unused in this app.
- `MediaSessionManager`, `onConnectAsync` — no consumer benefit here (project does not override `onConnect`).

## Verification

- Kotlin compile/build **not** runnable in this Freebuff environment (no Java/Android SDK) — changes are
  mechanical renames/additions verified against the official 1.11.0 sources; must be confirmed via
  `setup-flutter.sh` + `build-apk.sh` (Replit/CI) and a Mi 9T smoke test (crossfade, gapless, artwork
  notification, bit-perfect, stretch/pitch).
- Dart side (`pubspec.yaml` 1.5.15 + `changelog_data.dart` entry): validated with `flutter analyze`.
- No user-visible behavior change: A1/A2 are deprecation-removal renames; A3 only skips parsing data
  that is never consumed.

## Files touched

```
android/app/src/main/kotlin/dev/wndavenz/music/FallbackBitmapLoader.kt
android/app/src/main/kotlin/dev/wndavenz/music/Media3PlaybackService.kt
pubspec.yaml                                    (1.5.14 → 1.5.15)
lib/pages/settings_page/changelog_data.dart     (entry 1.5.15)
.agents/memory/media3-1.11.0-migration.md       (applied-improvements section)
```
