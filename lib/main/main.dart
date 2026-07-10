part of '../main.dart';

Future<void> main() async {
  // ── Zone guard — wraps SELURUH startup + runtime ──────────────────────────
  // Menangkap semua Future/Stream error yang tidak punya .catchError dari
  // inisialisasi awal hingga app berjalan. LogService mungkin belum init
  // saat error paling awal terjadi — debugPrint sebagai fallback.
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

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
    await Future.wait([
      ThemeController.init(),
      LogService.init(),
      LyricsSettings.init(),
      UpNextSettings.init(),
      WatermarkService.init(),
      // Resolves the artwork cache-directory path up front so SongArtwork's
      // synchronous disk check (getProviderSync) works from the very first
      // frame — cached cover art then never flashes a placeholder on cold
      // start (app killed / removed from recents).
      ArtworkRepository.instance.warmUp(),
      // Persisted palette colours (album card backgrounds, player background
      // shader) so they render instantly on cold start too, matching the
      // artwork image's own instant-render behaviour above.
      PaletteExtractor.warmUp(),
      // Hydrates the last-known song list from disk so the very first frame
      // can render the full library (and each song's cached artwork)
      // immediately instead of a spinner while MediaStore re-enumerates.
      // A live MediaStore query still runs right after, in the background.
      MediaStoreService.warmUp(),
      // Hydrates recently-played IDs and artist play counts from
      // SharedPreferences so the home sections can render instantly (no
      // spinner) on the first frame — same rationale as MediaStoreService.warmUp.
      HistoryService.warmUp(),
    ]);

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
    //   • Recently-played carousel → size 250 → full-res (targetSizePx: null)
    //   • Album cards              → size 170 → ResizeImage
    //   • Artist cards             → size 170 → ResizeImage
    {
      final recentIds   = HistoryService.cachedRecentIds ?? const [];
      final cachedSongs = MediaStoreService.cachedSongs  ?? const [];

      // Derive album- and artist-cover IDs the same way the home sections do:
      // first song encountered per albumId / artist name.
      final albumCoverIds  = <int>[];
      final artistCoverIds = <int>[];
      final seenAlbum      = <int>{};
      final seenArtist     = <String>{};
      for (final s in cachedSongs) {
        if (seenAlbum.add(s.albumId))  albumCoverIds.add(s.id);
        if (seenArtist.add(s.artist)) artistCoverIds.add(s.id);
      }

      final dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
final smallPx = (170 * dpr).round();

final visibleRecentIds = recentIds.take(8).toList(growable: false);
final visibleAlbumIds = albumCoverIds.take(4).toList(growable: false);
final visibleArtistIds = artistCoverIds.take(4).toList(growable: false);

// Recently Played (170)
await ArtworkRepository.instance.prewarmImageCache(
  visibleRecentIds,
  targetSizePx: smallPx,
);

// Album (250)
await ArtworkRepository.instance.prewarmImageCache(
  visibleAlbumIds,
);

// Artist (170)
await ArtworkRepository.instance.prewarmImageCache(
  visibleArtistIds,
  targetSizePx: smallPx,
);

// Off-screen
unawaited(
  ArtworkRepository.instance.prewarmImageCache(
    recentIds.skip(8).take(8).toList(growable: false),
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
      LogService.error('Dart', error.toString(), stackTrace: stack.toString());
      return true;
    };

    // Register the open-file channel handler EARLY so warm-restart intents
    // are not dropped before AudioService is ready. The URI is stored on the
    // native side (pendingOpenFileUri) and drained by checkInitialUri() later.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      OpenFileService.registerHandler();
    }

    // MediaKitSettingsService harus diinisialisasi SEBELUM AudioEngineManager
    // agar setting ter-load ke ValueNotifiers sebelum MediaKitEngine.initialize()
    // memanggil MediaKitSettingsService.applyAll().
    await MediaKitSettingsService.initialize();

    // Order matters: AudioEngineManager harus diinisialisasi pertama
    // (memuat pilihan engine dan menginisialisasi engine yang dipilih).
    // AudioEngine (facade efek) harus siap sebelum AudioEffectsService.
    await AudioEngineManager.initialize();
    await AudioEngine.initialize();
    await AudioEffectsService.init();
    LyricsService.init();
    await MediaCapabilitiesService.initialize();
    AudioService.initialize();
    AudioFocusService.initialize();
    SleepTimerService.initialize();

    // Sync playback state dari engine aktif sebelum merender UI.
    unawaited(AudioService.syncFromNative());

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Permission.storage.request();
      await Permission.audio.request();
    }

    // Drain URI from the intent that cold-started the app.
    // Must come AFTER permissions and AudioService.initialize() because
    // _playUri calls AudioService.playSongAt().
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(OpenFileService.checkInitialUri());
    }

    runApp(const MyApp());
  }, (Object error, StackTrace stack) {
    // Zone handler: fallback ke debugPrint jika LogService belum selesai init.
    if (LogService.isInitialized) {
      LogService.error('Zone', error.toString(), stackTrace: stack.toString());
    } else {
      debugPrint('[Zone/pre-init] $error\n$stack');
    }
  });
}
