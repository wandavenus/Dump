import 'dart:async';
import '../../models/local_song.dart';

/// Enum untuk memilih engine playback yang aktif.
enum PlaybackEngineType {
  media3,
  mediaKit;

  String get displayName => switch (this) {
        PlaybackEngineType.media3   => 'Native Media3',
        PlaybackEngineType.mediaKit => 'media_kit',
      };

  String get prefKey => switch (this) {
        PlaybackEngineType.media3   => 'media3',
        PlaybackEngineType.mediaKit => 'media_kit',
      };

  static PlaybackEngineType fromPrefKey(String key) => switch (key) {
        'media_kit' => PlaybackEngineType.mediaKit,
        _           => PlaybackEngineType.media3,
      };
}

/// Abstraksi engine audio. UI dan AudioService hanya berkomunikasi lewat
/// interface ini — tidak mengetahui apakah engine yang aktif adalah
/// Media3 atau media_kit.
///
/// Format stream yang harus dipenuhi oleh implementasi:
///
/// [playbackStateStream] → Map dengan key:
///   'playing'        : bool
///   'processingState': String ('idle'|'loading'|'buffering'|'ready'|'completed')
///
/// [currentTrackStream] → Map? dengan key:
///   'index'         : int
///   'id'            : int
///   'nextTrackIndex': int (-1 = tidak ada)
///
/// [queueStream] → List<dynamic> berisi Map dari LocalSong.toMap()
///
/// [sleepTimerStream] → Map dengan key:
///   'active'     : bool
///   'endOfSong'  : bool
///   'remainingMs': int
abstract class AbstractAudioEngine {
  Future<void> initialize();
  Future<void> dispose();

  // ── Transport ────────────────────────────────────────────────────────────
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);

  // ── Queue ────────────────────────────────────────────────────────────────
  Future<void> setQueue(List<LocalSong> queue, int index);
  Future<void> skipNext();
  Future<void> skipPrevious();
  Future<void> setTrack(int index);

  // ── Queue mutations ──────────────────────────────────────────────────────
  Future<void> insertNext(LocalSong song);
  Future<void> appendToQueue(LocalSong song);
  Future<void> removeFromQueue(int index);
  Future<void> reorderQueue(int oldIndex, int newIndex);

  // ── Mode ─────────────────────────────────────────────────────────────────
  Future<void> setRepeatMode(String mode);
  Future<void> setShuffleMode(bool enabled);

  // ── Parameters ───────────────────────────────────────────────────────────
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<void> setPitch(double pitch);

  // ── Sleep timer ──────────────────────────────────────────────────────────
  Future<void> setSleepTimer(int durationMs);
  Future<void> setSleepTimerEndOfSong();
  Future<void> cancelSleepTimer();

  // ── State snapshot ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getPlaybackSnapshot();

  // ── Streams ───────────────────────────────────────────────────────────────
  Stream<Map<dynamic, dynamic>> get playbackStateStream;
  Stream<Duration>              get positionStream;
  Stream<Duration>              get durationStream;
  Stream<Map<dynamic, dynamic>?> get currentTrackStream;
  Stream<List<dynamic>>         get queueStream;
  Stream<bool>                  get bufferingStateStream;
  Stream<bool>                  get shuffleModeStream;
  Stream<String>                get repeatModeStream;
  Stream<Map<dynamic, dynamic>> get sleepTimerStream;
  Stream<int>                   get audioSessionIdStream;
}
