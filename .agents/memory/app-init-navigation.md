---
name: App Init & Navigation
description: Full main.dart init sequence, app_state.dart lifecycle, and navigation/routing architecture.
---

# App Init & Navigation

## main.dart — Full Init Sequence

```
runZonedGuarded {
  1. WidgetsFlutterBinding.ensureInitialized()
     + SentryFlutter.init() using compile-time SENTRY_DSN
     + edge-to-edge UI, transparent bars

  2. Future.wait (parallel warm-up):
     - ThemeController.init()
     - LogService.init()
     - LyricsSettings.init()
     - WatermarkService.init()
     - ArtworkRepository.instance.warmUp()      ← resolves cache dir
     - PaletteExtractor.warmUp()                ← hydrates persisted palette
     - MediaStoreService.warmUp()               ← hydrates last-known song list
     - HistoryService.warmUp()                  ← hydrates recently played IDs

  3. Image cache pre-warm (async, non-blocking):
     ArtworkRepository.instance.prewarmImageCache()
     ← first 4 items: Recently Played, Albums, Artists (3s shared timeout)

  4. Error hooks:
     FlutterError.onError → Sentry.captureException + LogService
     PlatformDispatcher.instance.onError → Sentry.captureException + LogService
     runZonedGuarded callback → Sentry.captureException + LogService

  5. OpenFileService.registerHandler()   ← Android intent handling

  6. Sequential audio engine init:
     a. PlaybackManager.initialize()    ← FIRST (sets up EventChannels)
     b. DeviceDsp.initialize()
     c. AudioEffectsService.init()
     d. LyricsService.init()
     e. MediaCapabilitiesService.initialize()
     f. AudioService.initialize()
     g. AudioFocusService.initialize()
     h. SleepTimerService.initialize()

  7. AudioService.syncFromNative()
  8. Storage + audio permission requests (Android)
  9. OpenFileService.checkInitialUri()
  10. runApp(const MyApp())
}
```

**Critical rule:** `PlaybackManager.initialize()` must be first in step 6 — EventChannels must be registered before any other service tries to consume state from native.

**Web safety:** `BootTrace.step` rethrows — any web-unsafe warm-up step in Future.wait aborts `runApp()` silently → blank web preview. All platform-specific warm-up must be guarded.

## lib/main/ File Structure

`lib/main.dart` uses `part` files:
- `main.dart` — entry point
- `edge.dart` — edge-to-edge setup
- `scroll_behavior.dart` — custom scroll physics
- `app.dart` — `MyApp` widget
- `app_state.dart` — `_MyAppState` lifecycle

## app_state.dart — Lifecycle & State

`_MyAppState` (private state of `MyApp`):

| Concern | Handler | Action |
|---------|---------|--------|
| `resumed` | `didChangeAppLifecycleState` | Apply edge-to-edge, `AudioService.syncFromNative()`, `OpenFileService.onResume()` |
| `paused/detached` | `didChangeAppLifecycleState` | Clear `PaletteExtractor` memory cache, flush `LyricsSettings` |
| Watermark | `ValueListenableBuilder<WatermarkService.visible>` | Overlay `WatermarkService.text` on app |
| Disposal | `dispose()` | Cancel `MediaCapabilitiesService` subscriptions, remove observers |

Static field: `_appTheme` (immutable `ThemeData`).

## Navigation Architecture

**Router:** `onGenerateRoute` in `app_state.dart`

| Route | Widget | Transition |
|-------|--------|-----------|
| `/firstpage` | `WebView(child: FirstPage())` | `ZoomFadeRoute` (pure fade) |
| `/settings` | `SettingsPage()` | `ZoomFadeRoute` |

**`ZoomFadeRoute`** — defined in `lib/utils/zoom_fade_route.dart`; `PageRouteBuilder` with fade transition.

**Initial route:** `/firstpage`

**Bottom nav:** `lib/bottom_nav_bar/bottom_nav.dart` → `FirstPage` with inner Navigators per tab (Home, Browse, Library, Search, Radio).

**LyricsPage:** Full-screen route (not modal); opened via `Navigator.push` with `SlideTransition` from bottom; has lyrics appearance button (`_LyricsAppearanceSheet`).


## Scroll-driven Floating Pill Dock

The root `NotificationListener<ScrollNotification>` in `lib/bottom_nav_bar/bottom_nav/state.dart` forwards vertical root-viewport deltas to `FloatingPillTransitionController`. The shared progress drives both `FloatingPillNavBar` geometry and the collapsed `UnifiedMorphPlayer`; it is disabled while full-player progress is active and reset when the mini-player exits.


## Sentry Observability

- Dependency: sentry_flutter ^10.2.0 (Dart 3.12+; app constraint is Dart >=3.13.5 and Android minSdk is 29).
- DSN is compiled from --dart-define=SENTRY_DSN=...; empty DSN disables event delivery and Sentry initialization failures fail open.
- Environment is production in release mode and development otherwise.
- PII collection is disabled; performance tracing is not enabled. Native crash handling is enabled for Android Java/Kotlin/C/C++.
- Custom Flutter, PlatformDispatcher, and root-zone handlers explicitly forward exceptions to Sentry as they replace/augment the app's existing LogService hooks.
- Build handoff: Dump's trigger-public-builder.yml reads vars.SENTRY_DSN from the production environment and forwards the DSN to the Noisegraph build-apk.yml dispatch payload. Never pass SENTRY_AUTH_TOKEN to the app or dispatch payload.
- The APK build uses --obfuscate --split-debug-info; upload the generated Dart debug symbols separately to Sentry for readable obfuscated Dart stack traces.
