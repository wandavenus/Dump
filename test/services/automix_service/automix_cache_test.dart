import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/services/automix_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The cached-analysis read path is what AutoMix runs on for every already
/// analyzed track, so the fields the transition planner depends on (structure
/// markers and the exit beat grid) must survive being re-hydrated with the
/// current MediaStore metadata.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cached analysis hydration', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('automix_cache_test');
      file = File('${dir.path}/track.mp3');
      await file.writeAsBytes(List<int>.filled(32, 0));
      SharedPreferences.setMockInitialValues(<String, Object>{});
      AutomixService.resetInMemoryState();
    });

    tearDown(() async {
      AutomixService.resetInMemoryState();
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    });

    String identityOf(File f) =>
        '${f.lengthSync()}_${f.statSync().modified.millisecondsSinceEpoch}';

    test('keeps the exit grid and structure markers of a cached entry', () async {
      final song = LocalSong(
        id: 42,
        title: 'Cached',
        artist: 'Artist',
        album: 'Album',
        albumId: 7,
        path: file.path,
        duration: const Duration(minutes: 4),
      );
      final prefs = await SharedPreferences.getInstance();
      // NOTE: 'version' must track AutomixService's private analysis schema
      // version; a stale value here makes the entry a cache miss on purpose.
      await prefs.setString(
        'automix_42',
        jsonEncode(<String, dynamic>{
          'version': 8,
          'ident': identityOf(file),
          'data': <String, dynamic>{
            'id': 42,
            'bpm': 128.0,
            'bc': 0.9,
            'bo': 123.5,
            'dbo': 400.5,
            'tbpm': 126.0,
            'tbo': 245123.0,
            'tdbo': 236400.5,
            'dc': 30000.0,
            'tbkc': 232000.0,
            'dur': 240.0,
            'ie': 0.4,
            'oe': 0.2,
            'af': 1.0,
            'ta': true,
          },
        }),
      );

      final features = await AutomixService.featuresFor(song);

      expect(features.bpm, 128.0);
      expect(features.beatOffsetMs, 123.5);
      expect(features.downbeatOffsetMs, 400.5);
      expect(features.tailBpm, 126.0);
      expect(features.tailBeatOffsetMs, 245123.0);
      expect(features.tailDownbeatOffsetMs, 236400.5);
      expect(features.dropCueMs, 30000.0);
      expect(features.tailBreakdownCueMs, 232000.0);
      expect(features.durationSeconds, 240.0);
      expect(features.introEnergy, 0.4);
      expect(features.outroEnergy, 0.2);
      expect(features.analyzedFraction, 1.0);
      // Metadata still comes from the live MediaStore row.
      expect(features.title, 'Cached');
      expect(features.artist, 'Artist');
    });

    test('a changed file identity is a cache miss, not stale features', () async {
      final song = LocalSong(
        id: 43,
        title: 'Re-encoded',
        artist: 'Artist',
        album: 'Album',
        albumId: 7,
        path: file.path,
        duration: const Duration(minutes: 4),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'automix_43',
        jsonEncode(<String, dynamic>{
          'version': 7,
          'ident': 'stale_identity',
          'data': <String, dynamic>{'id': 43, 'bpm': 90.0, 'tbpm': 90.0},
        }),
      );

      final features = await AutomixService.featuresFor(song);

      // The cached tempo belongs to a file that no longer exists: the engine
      // must see neutral features instead of a wrong BPM.
      expect(features.bpm, isNull);
      expect(features.tailBpm, isNull);
    });
  });
}
