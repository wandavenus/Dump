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

  test('same-ID queue never engages the AutoMix transition', () async {
    final result = await AutomixService.startAutomix([
      song(101),
      song(101),
      song(101),
    ], 0);

    expect(result, -1);
    expect(AudioEffectsService.crossfadeDuration.value, 0.0);
    expect(AutomixService.automixActive.value, isFalse);

    expect(
      playbackCalls.map((call) => call.method).toSet(),
      <String>{'setAutomixTransition'},
    );
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
