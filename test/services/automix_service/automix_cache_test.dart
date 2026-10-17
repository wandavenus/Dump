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

  group('AutoMix DSP retry backoff', () {
    test('increases retry delay and caps repeated failures', () {
      expect(automixAnalysisRetryDelay(0), Duration.zero);
      expect(automixAnalysisRetryDelay(1), const Duration(seconds: 30));
      expect(automixAnalysisRetryDelay(2), const Duration(minutes: 1));
      expect(automixAnalysisRetryDelay(3), const Duration(minutes: 2));
      expect(automixAnalysisRetryDelay(4), const Duration(minutes: 4));
      expect(automixAnalysisRetryDelay(5), const Duration(minutes: 8));
      expect(automixAnalysisRetryDelay(6), const Duration(minutes: 15));
      expect(automixAnalysisRetryDelay(20), const Duration(minutes: 15));
    });
  });

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
        '${f.absolute.path}_${f.lengthSync()}_${f.statSync().modified.millisecondsSinceEpoch}';

    test(
      'keeps the exit grid and structure markers of a cached entry',
      () async {
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
            'version': 11,
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
              'dconf': 0.7,
              'tbconf': 0.9,
              'sreg': 3,
              'sconf': 0.8,
              'tsreg': 4,
              'tsconf': 0.75,
              'vlike': 0.85,
              'vconf': 0.9,
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
        expect(features.dropConfidence, 0.7);
        expect(features.tailBreakdownConfidence, 0.9);
        expect(features.structureRegion, 3);
        expect(features.structureConfidence, 0.8);
        expect(features.tailStructureRegion, 4);
        expect(features.tailStructureConfidence, 0.75);
        expect(features.vocalLikelihood, 0.85);
        expect(features.vocalConfidence, 0.9);
        // Metadata still comes from the live MediaStore row.
        expect(features.title, 'Cached');
        expect(features.artist, 'Artist');
      },
    );

    test(
      'invalidates version 8 entries after the vocal/structure schema bump',
      () async {
        final song = LocalSong(
          id: 44,
          title: 'Old schema',
          artist: 'Artist',
          album: 'Album',
          albumId: 7,
          path: file.path,
          duration: const Duration(minutes: 4),
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'automix_44',
          jsonEncode(<String, dynamic>{
            'version': 8,
            'ident': identityOf(file),
            'data': <String, dynamic>{
              'id': 44,
              'bpm': 128.0,
              'bc': 0.9,
              'vlike': 0.99,
              'vconf': 0.99,
              'sreg': 3,
              'sconf': 0.99,
              'ta': true,
            },
          }),
        );

        final features = await AutomixService.featuresFor(song);

        // MethodChannel analysis is unavailable in this unit test; rejection
        // must leave neutral features rather than reusing schema-v8 metadata.
        expect(features.bpm, isNull);
        expect(features.vocalLikelihood, 0);
        expect(features.vocalConfidence, 0);
        expect(features.structureRegion, 0);
        expect(features.structureConfidence, 0);
      },
    );

    test(
      'invalidates in-memory features when the same song file changes',
      () async {
        final song = LocalSong(
          id: 45,
          title: 'Edited source',
          artist: 'Artist',
          album: 'Album',
          albumId: 7,
          path: file.path,
          duration: const Duration(minutes: 4),
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'automix_45',
          jsonEncode(<String, dynamic>{
            'version': 11,
            'ident': identityOf(file),
            'data': <String, dynamic>{
              'id': 45,
              'bpm': 128.0,
              'bc': 0.9,
              'ta': true,
            },
          }),
        );

        final beforeEdit = await AutomixService.featuresFor(song);
        expect(beforeEdit.bpm, 128.0);

        await file.writeAsBytes(List<int>.filled(64, 1), flush: true);
        final afterEdit = await AutomixService.featuresFor(song);
        expect(afterEdit.bpm, isNull);
      },
    );

    test(
      'a changed file identity is a cache miss, not stale features',
      () async {
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
      },
    );
  });
}
