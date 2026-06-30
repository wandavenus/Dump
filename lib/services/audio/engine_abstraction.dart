import 'dart:async';
import '../../models/local_song.dart';

// ─── Shared engine types ───────────────────────────────────────────────────────

/// Engine-agnostic equalizer parameter set.
///
/// Returned by [AbstractAudioEngine.getEqualizerParameters].
/// Engines that do not support EQ return null.
class EngineEqualizerParameters {
  final double minDecibels;
  final double maxDecibels;
  final int bandCount;

  const EngineEqualizerParameters({
    required this.minDecibels,
    required this.maxDecibels,
    required this.bandCount,
  });
}

// ─── Engine type enum ──────────────────────────────────────────────────────────

/// Enum untuk memilih engine playback yang aktif.
enum PlaybackEngineType {
  media3,
  mediaKit;

  String get displayName => switch (this) {
        PlaybackEngineType.media3   => 'Native Media3',
        PlaybackEngineType.mediaKit => 'Media_kit',
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

// ─── AbstractAudioEngine ──────────────────────────────────────────────────────

/// Full contract for a playback engine.
///
/// UI dan semua shared service hanya berkomunikasi lewat interface ini
/// melalui [AudioEngineManager] — tidak ada yang mengetahui apakah engine
/// yang aktif adalah Media3 atau media_kit.
///
/// Implementasi engine yang tidak mendukung suatu fitur harus mengembalikan
/// Future.value() (untuk commands) atau null (untuk queries), dan memancarkan
/// stream kosong (untuk streams opsional).
///
/// Stream format contracts
/// ──────────────────────
/// [playbackStateStream] → Map:
///   'playing'          : bool
///   'processingState'  : String ('idle'|'loading'|'buffering'|'ready'|'completed')
///
/// [currentTrackStream] → Map?:
///   'index'            : int
///   'id'               : int
///   'nextTrackIndex'   : int (-1 = tidak ada)
///
/// [queueStream] → List berisi Map dari LocalSong.toMap()
///
/// [sleepTimerStream] → Map:
///   'active'           : bool
///   'endOfSong'        : bool
///   'remainingMs'      : int
///
/// [audioFormatStream] → Map (opsional — memancar hanya saat format berubah):
///   'sampleRate'       : int   (Hz, 0 jika tidak tersedia)
///   'channelCount'     : int   (1=Mono, 2=Stereo, ...)
///   'bitrate'          : int   (bits/s, 0 untuk lossless)
///   'mimeType'         : String
///   'codecs'           : String
///   'pcmEncoding'      : int   (0 = compressed)
///
/// [skipSilenceStream] → bool  (status setelah setiap set/konfirmasi native)
///
/// [stereoWideningStream] → Map:
///   'enabled'          : bool
///   'strength'         : double (0.0–1.0)
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

  // ── Playback parameters ──────────────────────────────────────────────────
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<void> setPitch(double pitch);

  // ── DSP effects ──────────────────────────────────────────────────────────
  /// Engines yang tidak mendukung DSP mengembalikan Future.value() (no-op).
  Future<void> setBassBoost(int strength);
  Future<void> setBassBoostEnabled(bool enabled);
  Future<void> setVirtualizerEnabled(bool enabled);
  Future<void> setVirtualizerStrength(int strength);
  Future<void> setReverbPreset(int preset);
  Future<void> setEqualizerEnabled(bool enabled);
  Future<void> setEqualizerBandGain(int band, double gainDb);
  Future<void> setLoudnessEnabled(bool enabled);
  Future<void> setLoudnessTargetGain(double gainMb);
  Future<void> setCrossfadeDuration(double seconds);

  /// Mengembalikan null jika engine tidak mendukung EQ.
  Future<EngineEqualizerParameters?> getEqualizerParameters();

  /// Mengembalikan map effect support flags.
  /// Engine yang tidak mendukung mengembalikan semua flag false.
  Future<Map<String, dynamic>?> getEffectSupport();

  // ── Capabilities ─────────────────────────────────────────────────────────
  /// Engines yang tidak mendukung mengembalikan Future.value() (no-op).
  Future<void> setSkipSilence(bool enabled);
  Future<void> setStereoWidening({required bool enabled, required double strength});

  /// Mengembalikan null jika engine tidak mendukung atau belum ada sesi.
  Future<Map<String, dynamic>?> getPlaybackStats();

  // ── Audio format ─────────────────────────────────────────────────────────
  /// Mengembalikan null jika engine tidak menyediakan audio format info.
  Future<Map<String, dynamic>?> getAudioFormat();

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

  /// Memancar saat format audio berubah (track change/decode change).
  /// Engine yang tidak mendukung harus mengembalikan Stream kosong.
  Stream<Map<dynamic, dynamic>> get audioFormatStream;

  /// Memancar setiap kali skip-silence state berubah.
  /// Engine yang tidak mendukung harus mengembalikan Stream kosong.
  Stream<bool> get skipSilenceStream;

  /// Memancar setiap kali stereo-widening state berubah.
  /// Engine yang tidak mendukung harus mengembalikan Stream kosong.
  Stream<Map<dynamic, dynamic>> get stereoWideningStream;
}
