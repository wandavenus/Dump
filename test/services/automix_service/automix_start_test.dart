import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/services/audio/audio_effects_service.dart';
import 'package:musicplayer/services/automix_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const automixChannel = MethodChannel('musicplayer/automix');
  const mediaStoreChannel = MethodChannel('musicplayer/media_store');
  const playbackChannel = MethodChannel('musicplayer/media3_playback');

  late List<MethodCall> playbackCalls;

  LocalSong song(int id) => LocalSong(
    id: id,
    title: 'Track $id',
    artist: 'Artist',
    album: 'Album',
    albumId: 1,
    path: '/missing/track_$id.mp3',
    duration: const Duration(minutes: 4),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'automixEnabled': true,
    });
    AutomixService.resetInMemoryState();
    AudioEffectsService.crossfadeDuration.value = 0.0;
    playbackCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(automixChannel, (call) async {
      return <String, Object?>{'success': false};
    });
    messenger.setMockMethodCallHandler(mediaStoreChannel, (call) async => null);
    messenger.setMockMethodCallHandler(playbackChannel, (call) async {
      playbackCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    AutomixService.resetInMemoryState();
    AutomixService.automixEnabled.value = false;
    AudioEffectsService.crossfadeDuration.value = 0.0;
    messenger.setMockMethodCallHandler(automixChannel, null);
    messenger.setMockMethodCallHandler(mediaStoreChannel, null);
    messenger.setMockMethodCallHandler(playbackChannel, null);
  });

  test(
    'withholds outgoing phase when only the whole-track grid is available',
    () {
      const outgoing = AutomixTrackFeatures(
        songId: 201,
        bpm: 120,
        bpmConfidence: 0.9,
        beatOffsetMs: 300,
        downbeatOffsetMs: 900,
        tailAnalyzed: true,
        tailBpmConfidence: 0.1,
      );
      const incoming = AutomixTrackFeatures(
        songId: 202,
        bpm: 122,
        bpmConfidence: 0.9,
        beatOffsetMs: 120,
        downbeatOffsetMs: 480,
      );
      final targets = AutomixService.buildNativeTargetsForTesting(outgoing, [
        incoming,
      ]);
      expect(targets, hasLength(2));
      // Whole-track BPM may still be used for tempo sequencing, but the head
      // phase must never masquerade as the outgoing exit grid.
      expect(targets.first['bpm'], 120.0);
      expect(targets.first.containsKey('beatOffsetMs'), isFalse);
      expect(targets.first.containsKey('downbeatOffsetMs'), isFalse);
      expect(targets[1]['bpm'], 122.0);
      expect(targets[1]['beatOffsetMs'], 120.0);
      expect(targets[1]['downbeatOffsetMs'], 480.0);
    },
  );

  test('publishes the tail grid when the exit estimate is confident', () {
    const outgoing = AutomixTrackFeatures(
      songId: 301,
      bpm: 120,
      bpmConfidence: 0.9,
      beatOffsetMs: 300,
      downbeatOffsetMs: 900,
      tailBpm: 126,
      tailBpmConfidence: 0.9,
      tailBeatOffsetMs: 31250,
      tailDownbeatOffsetMs: 31800,
      tailAnalyzed: true,
    );
    const incoming = AutomixTrackFeatures(
      songId: 302,
      bpm: 126,
      bpmConfidence: 0.9,
    );
    final targets = AutomixService.buildNativeTargetsForTesting(outgoing, [
      incoming,
    ]);
    expect(targets.first['bpm'], 126.0);
    expect(targets.first['beatOffsetMs'], 31250.0);
    expect(targets.first['downbeatOffsetMs'], 31800.0);
  });

  test('publishes the metre of the edge that owns each beat grid', () {
    // The outgoing deck is described by its exit window and every incoming deck
    // by its head window, so native must receive metre 3 for a waltz exit and
    // metre 4 for a 4/4 head instead of one metre for the whole track.
    const outgoing = AutomixTrackFeatures(
      songId: 401,
      bpm: 126,
      bpmConfidence: 0.9,
      meter: 4,
      tailMeter: 3,
      tailBpm: 126,
      tailBpmConfidence: 0.9,
      tailBeatOffsetMs: 31250,
      tailDownbeatOffsetMs: 31800,
      tailAnalyzed: true,
    );
    const incoming = AutomixTrackFeatures(
      songId: 402,
      bpm: 126,
      bpmConfidence: 0.9,
      meter: 4,
      tailMeter: 3,
    );
    final targets = AutomixService.buildNativeTargetsForTesting(outgoing, [
      incoming,
    ]);
    expect(targets.first['meter'], 3);
    expect(targets[1]['meter'], 4);
  });

  test('re-engaging AutoMix does not resend an unchanged duration', () async {
    AutomixService.automixEnabled.value = true;
    AudioEffectsService.crossfadeDuration.value = 4.0;

    // First engagement replaces the user's value, so the native call is real.
    expect(await AutomixService.engageCrossfadeForTesting(4.0), isTrue);
    await pumpEventQueue();
    var calls = playbackCalls
        .where((call) => call.method == 'setCrossfadeDuration')
        .toList();
    expect(calls, hasLength(1));
    expect((calls.single.arguments as Map<Object?, Object?>)['duration'], 4.0);

    // A track advance replans the next pair, usually with the same duration.
    // That must not touch the live crossfade.
    playbackCalls.clear();
    expect(await AutomixService.engageCrossfadeForTesting(4.0), isTrue);
    await pumpEventQueue();
    calls = playbackCalls
        .where((call) => call.method == 'setCrossfadeDuration')
        .toList();
    expect(calls, isEmpty);

    // A genuinely different duration is still forwarded for the next blend.
    expect(await AutomixService.engageCrossfadeForTesting(6.0), isTrue);
    await pumpEventQueue();
    calls = playbackCalls
        .where((call) => call.method == 'setCrossfadeDuration')
        .toList();
    expect(calls, hasLength(1));
    expect((calls.single.arguments as Map<Object?, Object?>)['duration'], 6.0);
  });

  test('same-ID queue never engages the AutoMix transition', () async {
    final result = await AutomixService.startAutomix([
      song(101),
      song(101),
      song(101),
    ], 0);

    expect(result, -1);
    expect(AudioEffectsService.crossfadeDuration.value, 0.0);
    expect(AutomixService.automixActive.value, isFalse);

    expect(playbackCalls.map((call) => call.method).toSet(), <String>{
      'setAutomixTransition',
    });
    final transitions = playbackCalls
        .where((call) => call.method == 'setAutomixTransition')
        .map((call) => call.arguments as Map<Object?, Object?>)
        .toList();
    expect(transitions, isNotEmpty);
    expect(
      transitions.every((args) => args['enabled'] == false),
      isTrue,
      reason: 'same-ID targets must only disarm native AutoMix',
    );
  });
}
