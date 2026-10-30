part of '../main.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // Sentry is optional at runtime: a missing DSN or SDK initialization
      // failure must never block the music player from starting.
      try {
        await SentryFlutter.init((options) {
          // DSN is intentionally injected at compile time by the release workflow.
          // ignore: do_not_use_environment
          options.dsn = const String.fromEnvironment('SENTRY_DSN');
          // Runtime release must match symbol uploads from Noisegraph CI.
          // ignore: do_not_use_environment
          const sentryRelease = String.fromEnvironment('SENTRY_RELEASE');
          // ignore: do_not_use_environment
          const sentryDist = String.fromEnvironment('SENTRY_DIST');
          if (sentryRelease.isNotEmpty) options.release = sentryRelease;
          if (sentryDist.isNotEmpty) options.dist = sentryDist;
          options.environment = kReleaseMode ? 'production' : 'development';
          options.sendDefaultPii = false;
          options.enableNativeCrashHandling = true;
          options.enableNativeTraceSync = true;
          options.enableNdkScopeSync = true;
          options.enableAutoNativeBreadcrumbs = true;
          options.enableUserInteractionBreadcrumbs = true;
          options.anrEnabled = true;
          options.enableTombstone = true;
          options.tracesSampleRate = kReleaseMode ? 0.15 : 1.0;
          options.enableAutoPerformanceTracing = true;
          options.enableFramesTracking = true;
          options.enableUserInteractionTracing = true;
          options.enableTimeToFullDisplayTracing = true;
          options.enableExceptionTypeIdentification = true;
          options.privacy.maskAllText = true;
          options.privacy.maskAllImages = true;
          options.privacy.maskAssetImages = true;
        });
      } on Object catch (error, stack) {
        debugPrint('[Sentry] Initialization failed: $error\n$stack');
      }
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

      // L-4 fix: LogService must be initialized before the permission request
      // so the 'Permissions' warning it logs on failure is actually recorded
      // instead of being silently dropped (log() early-returns while
      // loggingEnabled is still false). Reading prefs here is cheap, and the
      // order below still resolves the permission BEFORE the first MediaStore
      // query (MediaStoreService.warmUp) so the first library read is
      // authoritative on a fresh install.
      await LogService.init();

      // Resolve the audio permission before the first MediaStore query.
      // On a fresh install Android can otherwise return an empty library,
      // which gets consumed by the initial widgets before the permission
      // dialog completes. Waiting here makes the first query authoritative.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _requestAudioPermission();
      }

      await Future.wait([
        LanguageManager.instance.init(),
        ThemeController.init(),
        LyricsSettings.init(),
        WatermarkService.init(),
        ArtworkRepository.instance.warmUp(),
        NativePaletteService.warmUp(),
        MediaStoreService.warmUp(),
        HistoryService.warmUp(),
      ]);
      {
        final recentIds = HistoryService.cachedRecentIds ?? const [];
        final cachedSongs = MediaStoreService.cachedSongs ?? const [];
        final albumCoverIds = <int>[];
        final artistCoverIds = <int>[];
        final seenAlbum = <int>{};
        final seenArtist = <String>{};
        for (final s in cachedSongs) {
          if (seenAlbum.add(s.albumId)) albumCoverIds.add(s.id);
          if (seenArtist.add(s.artist)) artistCoverIds.add(s.id);
        }
        final smallPx = ArtworkRepository.instance.resolveTargetPx(170);
        final visibleRecentIds = recentIds.take(4).toList(growable: false);
        final visibleAlbumIds = albumCoverIds.take(4).toList(growable: false);
        final visibleArtistIds = artistCoverIds.take(4).toList(growable: false);
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
      FlutterError.onError = (FlutterErrorDetails details) {
        // Always keep the release console report. The toggle only controls
        // the in-app ring buffer; hiding framework errors made release
        // failures impossible to diagnose.
        FlutterError.presentError(details);
        unawaited(
          Sentry.captureException(details.exception, stackTrace: details.stack),
        );
        LogService.error(
          'Flutter',
          details.exceptionAsString(),
          stackTrace: details.stack?.toString(),
        );
      };
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        FlutterError.presentError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'PlatformDispatcher',
          ),
        );
        unawaited(Sentry.captureException(error, stackTrace: stack));
        LogService.error(
          'Dart',
          error.toString(),
          stackTrace: stack.toString(),
        );
        return true;
      };
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        OpenFileService.registerHandler();
      }
      await PlaybackManager.initialize();
      await DeviceDsp.initialize();
      await AudioEffectsService.init();
      // Recover a persisted AutoMix crossfade override before playback starts.
      // AutoMix's active flag is process-local, so it cannot restore itself
      // after an OS kill unless startup loads its saved settings.
      await AutomixService.loadSettings();
      LyricsService.init();
      await MediaCapabilitiesService.initialize();
      AudioService.initialize();
      AutomixService.initializeAutoMix();
      AudioFocusService.initialize();
      SleepTimerService.initialize();
      unawaited(AudioService.syncFromNative());
      runApp(SentryWidget(child: const MyApp()));
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        unawaited(OpenFileService.checkInitialUri());
      }
    },
    (Object error, StackTrace stack) {
      unawaited(Sentry.captureException(error, stackTrace: stack));
      if (LogService.isInitialized) {
        LogService.error(
          'Zone',
          error.toString(),
          stackTrace: stack.toString(),
        );
      } else {
        // Pre-init: the ring buffer is not ready, but the error must still be
        // visible in release logs.
        debugPrint('[Zone/pre-init] $error\n$stack');
      }
    },
  );
}

Future<void> _requestAudioPermission() async {
  try {
    await Permission.storage.request();
    await Permission.audio.request();
  } on Exception catch (e) {
    LogService.warn('Permissions', 'Request failed: $e');
  }
}
