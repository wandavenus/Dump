part of '../main.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
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
      await Future.wait([
        LanguageManager.instance.init(),
        ThemeController.init(),
        LogService.init(),
        LyricsSettings.init(),
        UpNextSettings.init(),
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
        unawaited(ArtworkRepository.instance.prewarmImageCache(
          recentIds.skip(4).take(12).toList(growable: false),
          targetSizePx: smallPx,
          timeout: const Duration(milliseconds: 2000),
        ));
        unawaited(ArtworkRepository.instance.prewarmImageCache(
          albumCoverIds.skip(4).take(8).toList(growable: false),
          timeout: const Duration(milliseconds: 2000),
        ));
        unawaited(ArtworkRepository.instance.prewarmImageCache(
          artistCoverIds.skip(4).take(8).toList(growable: false),
          targetSizePx: smallPx,
          timeout: const Duration(milliseconds: 2000),
        ));
      }
      NativeLogBridge.init();
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        LogService.error('Flutter', details.exceptionAsString(), stackTrace: details.stack?.toString());
      };
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        LogService.error('Dart', error.toString(), stackTrace: stack.toString());
        return true;
      };
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        OpenFileService.registerHandler();
      }
      await PlaybackManager.initialize();
      await DeviceDsp.initialize();
      await AudioEffectsService.init();
      LyricsService.init();
      await MediaCapabilitiesService.initialize();
      AudioService.initialize();
      AudioFocusService.initialize();
      SleepTimerService.initialize();
      unawaited(AudioService.syncFromNative());
      runApp(const MyApp());
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        unawaited(_requestPermissionsThenOpenPendingUri());
      }
    },
    (Object error, StackTrace stack) {
      if (LogService.isInitialized) {
        LogService.error('Zone', error.toString(), stackTrace: stack.toString());
      } else {
        debugPrint('[Zone/pre-init] $error\n$stack');
      }
    },
  );
}

Future<void> _requestPermissionsThenOpenPendingUri() async {
  try {
    await Permission.storage.request();
    await Permission.audio.request();
  } on Exception catch (e) {
    LogService.warn('Permissions', 'Request failed: $e');
  }

  try {
    await MediaStoreService.refreshSongs();
    MediaStoreService.rescanNotifier.value++;
  } catch (e, stackTrace) {
    LogService.warn(
      'MediaStore',
      'Initial post-permission refresh failed: $e',
      stackTrace: stackTrace.toString(),
    );
  }

  await OpenFileService.checkInitialUri();
}
