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
      AutomixService.setAnalysisCacheDirectoryForTesting(dir);
    });

    tearDown(() async {
      AutomixService.setAnalysisCacheDirectoryForTesting(null);
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
            'version': 24,
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
              'sbpm': 126.5,
              'ebpm': 127.5,
              'tsta': 0.77,
              'isl': 4.5,
              'osl': -3.5,
              'dc': 30000.0,
              'tbkc': 232000.0,
              'dur': 240.0,
              'ie': 0.4,
              'oe': 0.2,
              'irms': -18.0,
              'orms': -24.0,
              'iel': -17.5,
              'oel': -23.5,
              'ieo': 1.6,
              'oeo': 0.7,
              'af': 1.0,
              'ta': true,
              'dconf': 0.7,
              'tbconf': 0.9,
              'sreg': 3,
              'sconf': 0.8,
              'tsreg': 4,
              'tsconf': 0.75,
              'mt': 4,
              'tmt': 3,
              'scue': 200000.0,
              'scc': 0.82,
              'vlike': 0.85,
              'vconf': 0.9,
              'chords': <Map<String, dynamic>>[
                <String, dynamic>{'t': 232000.0, 'r': 7, 'q': 'maj', 'c': 0.88},
              ],
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
        expect(features.startBpm, 126.5);
        expect(features.endBpm, 127.5);
        expect(features.tempoStability, 0.77);
        expect(features.introSlope, 4.5);
        expect(features.outroSlope, -3.5);
        expect(features.dropCueMs, 30000.0);
        expect(features.tailBreakdownCueMs, 232000.0);
        expect(features.durationSeconds, 240.0);
        expect(features.introEnergy, 0.4);
        expect(features.outroEnergy, 0.2);
        expect(features.introRmsDb, -18.0);
        expect(features.outroRmsDb, -24.0);
        expect(features.introEdgeLufs, -17.5);
        expect(features.outroEdgeLufs, -23.5);
        expect(features.introEdgeOnsetRate, 1.6);
        expect(features.outroEdgeOnsetRate, 0.7);
        expect(features.analyzedFraction, 1.0);
        expect(features.dropConfidence, 0.7);
        expect(features.tailBreakdownConfidence, 0.9);
        expect(features.structureRegion, 3);
        expect(features.structureConfidence, 0.8);
        expect(features.tailStructureRegion, 4);
        expect(features.tailStructureConfidence, 0.75);
        expect(features.meter, 4);
        expect(features.tailMeter, 3);
        expect(features.tailSectionCueMs, 200000.0);
        expect(features.tailSectionCueConfidence, 0.82);
        expect(features.vocalLikelihood, 0.85);
        expect(features.vocalConfidence, 0.9);
        expect(features.chordProgression, hasLength(1));
        expect(features.chordProgression.single.label, 'Gmaj');
        expect(features.chordProgression.single.startMs, 232000.0);
        expect(features.chordProgression.single.confidence, 0.88);
        // Metadata still comes from the live MediaStore row.
        expect(features.title, 'Cached');
        expect(features.artist, 'Artist');
      },
    );
    test(
      'invalidates v23 entries after the M05 PCM-processing schema bump',
      () async {
        final song = LocalSong(
          id: 49,
          title: 'Pre-M05 cache',
          artist: 'Artist',
          album: 'Album',
          albumId: 7,
          path: file.path,
          duration: const Duration(minutes: 4),
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'automix_49',
          jsonEncode(<String, dynamic>{
            'version': 23,
            'ident': identityOf(file),
            'data': <String, dynamic>{'id': 49, 'bpm': 128.0, 'bc': 0.9},
          }),
        );

        final features = await AutomixService.featuresFor(song);

        expect(features.bpm, isNull);
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
      'invalidates version 17 entries after the ODF timestamp bump',
      () async {
        final song = LocalSong(
          id: 46,
          title: 'Pre-timestamp schema',
          artist: 'Artist',
          album: 'Album',
          albumId: 7,
          path: file.path,
          duration: const Duration(minutes: 4),
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'automix_46',
          jsonEncode(<String, dynamic>{
            'version': 17,
            'ident': identityOf(file),
            'data': <String, dynamic>{
              'id': 46,
              'bpm': 128.0,
              'bc': 0.9,
              'bo': 45.0,
              'ta': true,
            },
          }),
        );

        final features = await AutomixService.featuresFor(song);

        // v17 beat/phrase phases are 60-90 ms early; they must not be reused.
        expect(features.bpm, isNull);
        expect(features.beatOffsetMs, isNull);
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
            'version': 24,
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

    test('reads a per-track file without touching SharedPreferences', () async {
      final song = LocalSong(
        id: 47,
        title: 'File cache',
        artist: 'Artist',
        album: 'Album',
        albumId: 7,
        path: file.path,
        duration: const Duration(minutes: 4),
      );
      final cacheFile = File('${dir.path}/automix_47.json');
      await cacheFile.writeAsString(
        jsonEncode(<String, dynamic>{
          'version': 24,
          'ident': identityOf(file),
          'data': <String, dynamic>{
            'id': 47,
            'bpm': 124.0,
            'bc': 0.9,
            'ta': true,
          },
        }),
        flush: true,
      );

      final features = await AutomixService.featuresFor(song);
      expect(features.bpm, 124.0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('automix_47'), isNull);
    });

    test(
      'migrates a legacy preference entry into a file and removes it',
      () async {
        final song = LocalSong(
          id: 48,
          title: 'Migrated cache',
          artist: 'Artist',
          album: 'Album',
          albumId: 7,
          path: file.path,
          duration: const Duration(minutes: 4),
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'automix_48',
          jsonEncode(<String, dynamic>{
            'version': 24,
            'ident': identityOf(file),
            'data': <String, dynamic>{'id': 48, 'bpm': 122.0, 'bc': 0.9},
          }),
        );

        final features = await AutomixService.featuresFor(song);
        expect(features.bpm, 122.0);
        expect(File('${dir.path}/automix_48.json').existsSync(), isTrue);
        expect(prefs.getString('automix_48'), isNull);
      },
    );

    test('prunes cache files for tracks no longer in the library', () async {
      final valid = File('${dir.path}/automix_50.json');
      final stale = File('${dir.path}/automix_51.json');
      final temp = File('${dir.path}/automix_52.json.tmp');
      for (final cached in <File>[valid, stale, temp]) {
        await cached.writeAsString('{}', flush: true);
      }
      final song = LocalSong(
        id: 50,
        title: 'Kept',
        artist: 'Artist',
        album: 'Album',
        albumId: 7,
        path: file.path,
        duration: const Duration(minutes: 4),
      );

      await AutomixService.pruneAnalysisCacheForTesting([song]);
      expect(valid.existsSync(), isTrue);
      expect(stale.existsSync(), isFalse);
      expect(temp.existsSync(), isFalse);
    });
  });
}
