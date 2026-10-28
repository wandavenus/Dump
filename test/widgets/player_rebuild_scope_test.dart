import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/l10n/app_localizations.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/services/audio_playback_state.dart';
import 'package:musicplayer/services/audio_service.dart';
import 'package:musicplayer/services/player_sheet_controller.dart';
import 'package:musicplayer/themes/app_themes.dart';
import 'package:musicplayer/widgets/player/player_content.dart';
import 'package:musicplayer/widgets/player/player_song_header.dart';

const List<Locale> _locales = [Locale('en'), Locale('id')];

const List<LocalizationsDelegate<Object>> _delegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

final _song = LocalSong(
  id: 1,
  title: 'Rebuild Scope Song',
  artist: 'Test Artist',
  album: 'Test Album',
  albumId: 10,
  path: '',
  duration: const Duration(minutes: 3),
);

Future<void> _pumpPlayer(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(393, 852);
  addTearDown(tester.view.reset);

  PlayerSheetController.progress.value = 1.0;
  addTearDown(() => PlayerSheetController.progress.value = 0.0);

  AudioService.playbackState.value = AudioPlaybackState(
    currentSong: _song,
    currentPlaylist: [_song],
    isPlaying: true,
    duration: const Duration(minutes: 3),
    position: const Duration(seconds: 30),
    processingState: ProcessingState.ready,
  );
  addTearDown(
    () => AudioService.playbackState.value = const AudioPlaybackState(),
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemes.dark,
      localizationsDelegates: _delegates,
      supportedLocales: _locales,
      home: Scaffold(
        body: SizedBox.expand(
          child: PlayerContent(
            song: _song,
            formatTime: (duration) => '${duration.inSeconds}s',
            showLyrics: false,
            onLyricsToggle: () {},
            showQueue: false,
            onQueueToggle: () {},
            hideArtwork: true,
          ),
        ),
      ),
    ),
  );

  // Let the initial lyric lookup and first frame settle. The marquee delay is
  // two seconds, so this stays below that timer.
  await tester.pump(const Duration(milliseconds: 450));
}

/// Captures rebuild logs while [action] runs. `debugPrintRebuildDirtyWidgets`
/// is a Flutter debug facility intended for exactly this kind of regression
/// check; it is restored even when the action throws.
Future<List<String>> _captureRebuilds(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  final logs = <String>[];
  final previousDebugPrint = debugPrint;

  debugPrint = (message, {wrapWidth}) {
    if (message != null) logs.add(message);
  };
  debugPrintRebuildDirtyWidgets = true;

  try {
    await action();
  } finally {
    debugPrintRebuildDirtyWidgets = false;
    debugPrint = previousDebugPrint;
  }

  return logs;
}

bool _containsWidget(List<String> logs, String name) =>
    logs.any((line) => line.contains(name));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    const channel = MethodChannel('musicplayer/media_store');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getExplicitStatus') return false;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });

  testWidgets('position ticks update time without rebuilding PlayerContent', (
    tester,
  ) async {
    await _pumpPlayer(tester);
    expect(find.byType(PlayerSongHeader), findsOneWidget);

    final logs = await _captureRebuilds(tester, () async {
      AudioService.playbackState.value = AudioService.playbackState.value
          .copyWith(position: const Duration(seconds: 31));
      await tester.pump();
    });

    // The position-dependent progress section must still update...
    expect(find.text('31s'), findsOneWidget);

    // ...but position-only updates must not rebuild the player or its header.
    expect(_containsWidget(logs, 'PlayerContent'), isFalse);
    expect(_containsWidget(logs, 'PlayerSongHeader'), isFalse);
  });

  testWidgets('transport still follows isPlaying changes', (tester) async {
    await _pumpPlayer(tester);

    expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);

    AudioService.playbackState.value = AudioService.playbackState.value
        .copyWith(isPlaying: false);
    await tester.pump();

    expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);
  });

  testWidgets('sheet progress only rebuilds progress-dependent wrappers', (
    tester,
  ) async {
    await _pumpPlayer(tester);

    final logs = await _captureRebuilds(tester, () async {
      PlayerSheetController.progress.value = 0.65;
      await tester.pump();
    });

    // Song info fades with the sheet, so its opacity must reflect the new
    // progress even though PlayerContent itself was not rebuilt.
    final opacityValues = tester
        .widgetList<Opacity>(
          find.descendant(
            of: find.byKey(const ValueKey('songInfo')),
            matching: find.byType(Opacity),
          ),
        )
        .map((widget) => widget.opacity);
    expect(opacityValues, contains(closeTo((0.65 - 0.15) / 0.85, 0.001)));

    // Stable children must not be reconstructed by a sheet-progress tick.
    expect(_containsWidget(logs, 'PlayerContent'), isFalse);
    expect(_containsWidget(logs, 'PlayerSongHeader'), isFalse);
    expect(_containsWidget(logs, 'PlayerProgressSection'), isFalse);
  });
}
