import '../../models/local_song.dart';

enum AudioEngineType {
  media3('media3', 'Native Media3'),
  aaudio('aaudio', 'Native AAudio');

  const AudioEngineType(this.id, this.label);
  final String id;
  final String label;

  static AudioEngineType fromId(String? id) => AudioEngineType.values.firstWhere(
    (type) => type.id == id,
    orElse: () => AudioEngineType.media3,
  );
}

enum AudioEngineState { idle, ready, playing, paused, stopped, buffering, error }

abstract interface class AudioEngine {
  AudioEngineType get type;
  Stream<Map<dynamic, dynamic>> get playbackStateStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<Map<dynamic, dynamic>?> get currentTrackStream;
  Stream<List<dynamic>> get queueStream;
  Stream<bool> get bufferingStateStream;
  Stream<bool> get shuffleModeStream;
  Stream<String> get repeatModeStream;
  Stream<Map<dynamic, dynamic>> get sleepTimerStream;
  Stream<int> get audioSessionIdStream;
  Stream<Map<dynamic, dynamic>> get audioFormatStream;
  Stream<Map<dynamic, dynamic>> get stereoWideningStream;

  Duration get currentPosition;
  Duration get duration;
  AudioEngineState get state;

  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> dispose();

  Future<void> skipNext();
  Future<void> skipPrevious();
  Future<void> setTrack(int index);
  Future<void> setQueue(List<LocalSong> queue, int index);
  Future<void> setRepeatMode(String mode);
  Future<void> setShuffleMode(bool enabled);
}
