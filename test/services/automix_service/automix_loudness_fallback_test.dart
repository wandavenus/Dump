import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/models/loudness_data.dart';
import 'package:musicplayer/services/automix_service.dart';
import 'package:musicplayer/services/replay_gain_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('automix_lufs_fallback_test');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const mediaStoreChannel = MethodChannel('musicplayer/media_store');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mediaStoreChannel, (call) async {
          if (call.method != 'getReplayGainFileIdentity') return null;
          final arguments = call.arguments as Map<Object?, Object?>;
          final file = File(arguments['path']! as String);
          final stat = file.statSync();
          return <String, Object>{
            'size': file.lengthSync(),
            'mtimeMs': stat.modified.millisecondsSinceEpoch,
          };
        });
    AutomixService.resetInMemoryState();
    AutomixService.setAnalysisCacheDirectoryForTesting(dir);
    ReplayGainService.clearCache();
  });

  tearDown(() async {
    AutomixService.setAnalysisCacheDirectoryForTesting(null);
    AutomixService.resetInMemoryState();
    ReplayGainService.clearCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('musicplayer/media_store'),
          null,
        );
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Future<(LocalSong, File)> createSong(int id, String title) async {
    final file = File('${dir.path}/$id.mp3');
    await file.writeAsBytes(<int>[1, 2, 3, 4]);
    return (
      LocalSong(
        id: id,
        title: title,
        artist: 'Ambient Artist',
        album: 'Ambient Album',
        albumId: id,
        path: file.path,
        duration: const Duration(minutes: 3),
      ),
      file,
    );
  }

  Future<void> cacheReplayGain(LocalSong song, File file, double lufs) async {
    final prefs = await SharedPreferences.getInstance();
    final identity = file.statSync();
    // ReplayGain gain is target LUFS (-18) minus the measured integrated LUFS.
    await prefs.setString('rg_${song.id}_path', song.path);
    await prefs.setInt('rg_${song.id}_size', file.lengthSync());
    await prefs.setInt(
      'rg_${song.id}_mtime',
      identity.modified.millisecondsSinceEpoch,
    );
    await prefs.setString('rg_${song.id}_gain', (-18.0 - lufs).toString());
    await prefs.setInt(
      'rg_${song.id}_src',
      LoudnessSource.replayGainTrack.index,
    );
  }

  String identityOf(File file) =>
      '${file.absolute.path}_${file.lengthSync()}_'
      '${file.statSync().modified.millisecondsSinceEpoch}';

  test(
    'preserves quiet ReplayGain LUFS when matching an ambient seam',
    () async {
      final (ambient, ambientFile) = await createSong(901, 'Quiet ambient');
      final (reference, referenceFile) = await createSong(902, 'Reference');
      await cacheReplayGain(ambient, ambientFile, -30.0);
      await cacheReplayGain(reference, referenceFile, -23.0);

      final ambientFeatures = await AutomixService.featuresFor(ambient);
      final referenceFeatures = await AutomixService.featuresFor(reference);
      expect(ambientFeatures.loudnessLufs, -30.0);
      expect(ambientFeatures.loudnessLufs!.isFinite, isTrue);

      final cue = automixTransitionCue(
        outgoing: referenceFeatures,
        incoming: ambientFeatures,
        settings: const AutomixSettings(),
      );
      expect(cue.outgoingTrim, lessThan(0.6));
      expect(cue.outgoingTrim, greaterThanOrEqualTo(0.5));
      expect(cue.incomingTrim, 1.0);
    },
  );

  test(
    'keeps valid analyzed LUFS instead of replacing it with fallback',
    () async {
      final (song, file) = await createSong(903, 'Analyzed track');
      await cacheReplayGain(song, file, -35.0);
      await File('${dir.path}/automix_${song.id}.json').writeAsString(
        jsonEncode(<String, Object>{
          'version': 24,
          'ident': identityOf(file),
          'data': <String, Object>{'id': song.id, 'lufs': -20.0},
        }),
        flush: true,
      );

      final features = await AutomixService.featuresFor(song);

      expect(features.loudnessLufs, -20.0);
    },
  );
}
