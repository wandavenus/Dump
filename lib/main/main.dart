part of '../main.dart';

Future<void> main() async {
  BootTrace.log('ENTER main()');
  // ── Zone guard — wraps SELURUH startup + runtime ──────────────────────────
  // Menangkap semua Future/Stream error yang tidak punya .catchError dari
  // inisialisasi awal hingga app berjalan. LogService mungkin belum init
  // saat error paling awal terjadi — debugPrint sebagai fallback.
  await runZonedGuarded(
    () async {
      BootTrace.log('BEFORE WidgetsFlutterBinding.ensureInitialized()');
      WidgetsFlutterBinding.ensureInitialized();
      BootTrace.log('AFTER  WidgetsFlutterBinding.ensureInitialized()');

      if (!kIsWeb) {
        unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
        SystemChrome.setSystemUIOverlayStyle(
          const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
          ),
        );
      }

      // Empat service ini independen satu sama lain (masing-masing hanya
      // memuat pengaturan sendiri dari SharedPreferences), jadi dijalankan
      // paralel untuk mempercepat waktu ke first frame.
      BootTrace.log('BEFORE Future.wait([ThemeController.init, LogService.init, '
          'LyricsSettings.init, UpNextSettings.init, WatermarkService.init, '
          'ArtworkRepository.warmUp, PaletteExtractor.warmUp, '
          'MediaStoreService.warmUp, HistoryService.warmUp])');
      await Future.wait([
        BootTrace.step('ThemeController.init', ThemeController.init),
        BootTrace.step('LogService.init', LogService.init),
        BootTrace.step('LyricsSettings.init', LyricsSettings.init),
        BootTrace.step('UpNextSettings.init', UpNextSettings.init),
        BootTrace.step('WatermarkService.init', WatermarkService.init),
        // Resolves the artwork cache-directory path up front so SongArtwork's
        // synchronous disk check (getProviderSync) works from the very first
        // frame — cached cover art then never flashes a placeholder on cold
        // start (app killed / removed from recents).
        BootTrace.step(
            'ArtworkRepository.warmUp', ArtworkRepository.instance.warmUp),
        // Persisted palette colours (album card backgrounds, player background
        // shader) so they render instantly on cold start too, matching the
        // artwork image's own instant-render behaviour above.
        BootTrace.step('PaletteExtractor.warmUp', PaletteExtractor.warmUp),
        // Hydrates the last-known song list from disk so the very first frame
        // can render the full library (and each song's cached artwork)
        // immediately instead of a spinner while MediaStore re-enumerates.
        // A live MediaStore query still runs right after, in the background.
        BootTrace.step('MediaStoreService.warmUp', MediaStoreService.warmUp),
        // Hydrates recently-played IDs and artist play counts from
        // SharedPreferences so the home sections can render instantly (no
        // spinner) on the first frame — same rationale as MediaStoreService.warmUp.
        BootTrace.step('HistoryService.warmUp', HistoryService.warmUp),
      ]);
      BootTrace.log('AFTER  Future.wait([...warm-up services...])');

      // ── Pre-warm Flutter's ImageCache for home-screen artwork ───────────────
      // After all warmUps above, _diskCachedIds and song/history caches are
      // ready. We kick off async disk reads + WebP decodes HERE — before
      // runApp() — so the decoded bitmaps are ready (or nearly ready) by the
      // time the first frame is composed.
      //
      // Sizes must mirror SongArtwork's targetSizePx logic:
      //   widget.size >= 250  →  null  (full-res FileImage, no ResizeImage)
      //   widget.size < 250   →  (size * dpr).round()  (ResizeImage)
      //
      // Home sections that render on frame 1:
      //   • Recently-played carousel → size 170 → ResizeImage
      //   • Album cards              → size 250 → full-res (targetSizePx: null)
      //   • Artist cards             → size 170 → ResizeImage
      {
        final recentIds = HistoryService.cachedRecentIds ?? const [];
        final cachedSongs = MediaStoreService.cachedSongs ?? const [];

        // Derive album- and artist-cover IDs the same way the home sections do:
        // first song encountered per albumId / artist name.
        final albumCoverIds = <int>[];
        final artistCoverIds = <int>[];
        final seenAlbum = <int>{};
        final seenArtist = <String>{};
        for (final s in cachedSongs) {
          if (seenAlbum.add(s.albumId)) albumCoverIds.add(s.id);
          if (seenArtist.add(s.artist)) artistCoverIds.add(s.id);
        }

        // Resolved via ArtworkRepository so this and every SongArtwork
        // instance's later devicePixelRatio read are guaranteed identical —
        // see resolveTargetPx() doc for why a mismatch here silently causes
        // the "sometimes zero-delay, sometimes reload" flicker.
        final smallPx = ArtworkRepository.instance.resolveTargetPx(170);

        // Only the first few Recently Played cards are visible on the first
        // frame.  Keep this awaited batch small so MIUI cold-start disk I/O
        // does not race eight decodes at once and time out before runApp().
        final visibleRecentIds = recentIds.take(4).toList(growable: false);
        final visibleAlbumIds = albumCoverIds.take(4).toList(growable: false);
        final visibleArtistIds = artistCoverIds.take(4).toList(growable: false);

        // Recently Played / Album / Artist — all three are above-the-fold on
        // the very first frame, so they share one consistent timeout policy
        // and run CONCURRENTLY (not sequentially) so the worst case is one
        // batch's timeout, not the sum of three.
        //
        // The cap is 3 s, up from the old 900 ms (2 s for Recently Played):
        // right after a MIUI system-kill, storage I/O can be heavily
        // contended by other apps also cold-starting, so a decode that
        // normally takes <100 ms can occasionally take well over 900 ms-2 s.
        // When the timeout fires early, main() proceeds to runApp() with
        // that image NOT yet in ImageCache — SongArtwork then falls back to
        // its async _load() path and the user sees exactly the inconsistent
        // "sometimes zero-delay, sometimes reload" flicker this guards
        // against. The decode itself never blocks the UI thread (it's the
        // disk-read/webp-decode await), so a longer cap only ever costs time
        // on genuinely slow cold boots, never on the common warm/fast path —
        // and running the three batches concurrently keeps that worst case
        // bounded to ~3 s total instead of ~3 s per section.
        const priorityPrewarmTimeout = Duration(milliseconds: 3000);
        await Future.wait([
          ArtworkRepository.instance.prewarmImageCache(
            visibleRecentIds,
            targetSizePx: smallPx,
            timeout: priorityPrewarmTimeout,
          ),
          ArtworkRepository.instance.prewarmImageCache(
            visibleAlbumIds,
            timeout: priorityPrewarmTimeout,
          ),
          ArtworkRepository.instance.prewarmImageCache(
            visibleArtistIds,
            targetSizePx: smallPx,
            timeout: priorityPrewarmTimeout,
          ),
        ]);

        // Off-screen
        unawaited(
          ArtworkRepository.instance.prewarmImageCache(
            recentIds.skip(4).take(12).toList(growable: false),
            targetSizePx: smallPx,
            timeout: const Duration(milliseconds: 2000),
          ),
        );

        unawaited(
          ArtworkRepository.instance.prewarmImageCache(
            albumCoverIds.skip(4).take(8).toList(growable: false),
            timeout: const Duration(milliseconds: 2000),
          ),
        );

        unawaited(
          ArtworkRepository.instance.prewarmImageCache(
            artistCoverIds.skip(4).take(8).toList(growable: false),
            targetSizePx: smallPx,
            timeout: const Duration(milliseconds: 2000),
          ),
        );
      }

      NativeLogBridge.init();

      // ── Global error hooks (dipasang setelah LogService siap) ───────────────
      //
      // Hook 1 — Flutter framework errors: widget null-ref, layout overflow, dll.
      // presentError dipanggil dulu agar output debug default tetap muncul di
      // console, lalu baru disimpan ke LogService.
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        LogService.error(
          'Flutter',
          details.exceptionAsString(),
          stackTrace: details.stack?.toString(),
        );
      };

      // Hook 2 — Dart VM errors yang tidak ter-catch: platform channel exception,
      // isolate uncaught error, dll. Return true = error dianggap sudah ditangani,
      // VM tidak crash.
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        LogService.error(
          'Dart',
          error.toString(),
          stackTrace: stack.toString(),
        );
        return true;
      };

      // Register the open-file channel handler EARLY so warm-restart intents
      // are not dropped before AudioService is ready. The URI is stored on the
      // native side (pendingOpenFileUri) and drained by checkInitialUri() later.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        OpenFileService.registerHandler();
      }

      // Order matters: PlaybackManager harus diinisialisasi pertama
      // agar EventChannel stream siap sebelum AudioEffectsService.
      // DeviceDsp (DSP capability helper) diinisialisasi setelahnya.
      BootTrace.log('BEFORE await PlaybackManager.initialize()');
      await BootTrace.step(
          'PlaybackManager.initialize', PlaybackManager.initialize);
      BootTrace.log('AFTER  await PlaybackManager.initialize()');

      BootTrace.log('BEFORE await DeviceDsp.initialize()');
      await BootTrace.step('DeviceDsp.initialize', DeviceDsp.initialize);
      BootTrace.log('AFTER  await DeviceDsp.initialize()');

      BootTrace.log('BEFORE await AudioEffectsService.init()');
      await BootTrace.step('AudioEffectsService.init', AudioEffectsService.init);
      BootTrace.log('AFTER  await AudioEffectsService.init()');

      BootTrace.log('BEFORE LyricsService.init() (sync)');
      LyricsService.init();
      BootTrace.log('AFTER  LyricsService.init() (sync)');

      BootTrace.log('BEFORE await MediaCapabilitiesService.initialize()');
      await BootTrace.step(
          'MediaCapabilitiesService.initialize', MediaCapabilitiesService.initialize);
      BootTrace.log('AFTER  await MediaCapabilitiesService.initialize()');

      BootTrace.log('BEFORE AudioService.initialize() (sync)');
      AudioService.initialize();
      BootTrace.log('AFTER  AudioService.initialize() (sync)');

      BootTrace.log('BEFORE AudioFocusService.initialize() (sync)');
      AudioFocusService.initialize();
      BootTrace.log('AFTER  AudioFocusService.initialize() (sync)');

      BootTrace.log('BEFORE SleepTimerService.initialize() (sync)');
      SleepTimerService.initialize();
      BootTrace.log('AFTER  SleepTimerService.initialize() (sync)');

      // Sync playback state dari engine aktif sebelum merender UI.
      unawaited(AudioService.syncFromNative());

      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        BootTrace.log('BEFORE await Permission.storage.request()');
        await Permission.storage.request();
        BootTrace.log('AFTER  await Permission.storage.request()');
        BootTrace.log('BEFORE await Permission.audio.request()');
        await Permission.audio.request();
        BootTrace.log('AFTER  await Permission.audio.request()');
      }

      // Drain URI from the intent that cold-started the app.
      // Must come AFTER permissions and AudioService.initialize() because
      // _playUri calls AudioService.playSongAt().
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        unawaited(OpenFileService.checkInitialUri());
      }

      BootTrace.log('BEFORE runApp(MyApp)');
      runApp(const MyApp());
      BootTrace.log('AFTER  runApp(MyApp) — main() reached the end');
    },
    (Object error, StackTrace stack) {
      // Zone handler: fallback ke debugPrint jika LogService belum selesai init.
      if (LogService.isInitialized) {
        LogService.error(
          'Zone',
          error.toString(),
          stackTrace: stack.toString(),
        );
      } else {
        debugPrint('[Zone/pre-init] $error\n$stack');
      }
    },
  );
}
