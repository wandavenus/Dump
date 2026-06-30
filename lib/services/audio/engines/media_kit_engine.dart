// ignore_for_file: close_sinks, unawaited_futures, unused_field

import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../../../models/local_song.dart';
import '../engine_abstraction.dart';
import '../../log_service.dart';
import '../mediakit/mediakit_service_bridge.dart';
import '../mediakit/mediakit_settings_service.dart';

/// Engine berbasis media_kit 1.2.6.
///
/// [Player] adalah satu-satunya kelas media_kit yang diizinkan digunakan
/// di sini. Semua layer di atas hanya berkomunikasi via [AbstractAudioEngine].
///
/// Feature parity notes:
///   ✅ Play / Pause / Stop / Seek
///   ✅ Queue / Playlist / Next / Previous / Jump
///   ✅ Shuffle (media_kit native)
///   ✅ Repeat (PlaylistMode)
///   ✅ Background playback (via media_kit_libs_android_audio)
///   ✅ Speed / Volume
///   ✅ Pitch — independen dari speed via player.setPitch() (PlayerConfiguration pitch:true)
///   ✅ Sleep timer (Dart-side Timer)
///   ✅ Queue persistence (via getPlaybackSnapshot)
///   ✅ Notification / Lock screen / BT controls (via MediaKitPlaybackService)
///   ❌ DSP (EQ, Bass, Reverb, Virtualizer, Crossfade, LoudnessEnhancer):
///      semua DSP method adalah no-op yang aman.
///   ❌ Skip silence / Stereo widening — no-op; stream memancar state lokal.
///   ❌ Audio format stream — tidak tersedia; audioFormatStream kosong.
///   ❌ Playback stats — getPlaybackStats() mengembalikan null.
///   ❌ audioSessionId — memancar -1.
class MediaKitEngine implements AbstractAudioEngine {
  Player? _player;
  List<LocalSong> _queue = [];
  int _currentIndex = 0;
  bool _shuffleEnabled = false;
  String _repeatMode = 'off'; // 'off' | 'all' | 'one'

  // Speed dan pitch disimpan secara terpisah untuk keperluan snapshot/restore.
  // Dengan PlayerConfiguration(pitch:true), player.setRate() dan player.setPitch()
  // adalah dua jalur independen — mengubah satu tidak mempengaruhi yang lain.
  double _speed       = 1.0;
  double _pitchFactor = 1.0; // disimpan untuk snapshot; dikirim via player.setPitch()

  // Position update throttle for the Android MediaSession seek bar.
  // Tracks the wall-clock time (ms) of the last updatePlaybackState call that
  // carried a position update.  Reset to 0 on track change or seek so the
  // first emission after those events is always forwarded immediately.
  int _lastPositionSentMs = 0;

  /// Minimum interval between position-only pushes to the Android service.
  static const int _kPositionUpdateIntervalMs = 5000; // 5 s

  // Sleep timer (Dart-side)
  Timer? _sleepTimer;
  Timer? _sleepCountdownTick;
  bool   _sleepEndOfSong   = false;
  bool   _sleepTimerActive = false;
  int    _sleepRemainingMs = 0;

  // StreamControllers — format identik dengan AbstractAudioEngine contract
  final _playbackStateCtrl  = StreamController<Map<dynamic, dynamic>>.broadcast();
  final _positionCtrl       = StreamController<Duration>.broadcast();
  final _durationCtrl       = StreamController<Duration>.broadcast();
  final _currentTrackCtrl   = StreamController<Map<dynamic, dynamic>?>.broadcast();
  final _queueCtrl          = StreamController<List<dynamic>>.broadcast();
  final _bufferingCtrl      = StreamController<bool>.broadcast();
  final _shuffleCtrl        = StreamController<bool>.broadcast();
  final _repeatCtrl         = StreamController<String>.broadcast();
  final _sleepTimerCtrl     = StreamController<Map<dynamic, dynamic>>.broadcast();
  final _audioSessionCtrl   = StreamController<int>.broadcast();
  final _skipSilenceCtrl    = StreamController<bool>.broadcast();
  final _stereoWideningCtrl = StreamController<Map<dynamic, dynamic>>.broadcast();

  // audioFormatStream — media_kit tidak mengekspos info format; stream ini kosong.
  static const Stream<Map<dynamic, dynamic>> _emptyAudioFormatStream =
      Stream<Map<dynamic, dynamic>>.empty();

  final List<StreamSubscription<dynamic>> _subs = [];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  Future<void> initialize() async {
    // pitch:true memungkinkan player.setPitch() bekerja independen dari rate.
    _player = Player(
      configuration: const PlayerConfiguration(pitch: true),
    );

    // Daftarkan player ke MediaKitSettingsService agar setting bisa diterapkan
    // ke engine saat runtime (saat toggle di Settings).
    MediaKitSettingsService.registerPlayer(_player!);

    // Terapkan semua setting yang tersimpan (gapless, replaygain, cache).
    await MediaKitSettingsService.applyAll(_player!);

    // Register transport command handler BEFORE startListening() so no
    // command is missed if the service emits before the subscription is ready.
    MediaKitServiceBridge.setTransportCommandHandler(_handleTransportCommand);

    // Subscribe to player events first so the engine handles any commands
    // that arrive immediately after service start.
    _subscribeToPlayer();

    // Start the Android foreground service (no-op on non-Android platforms).
    await MediaKitServiceBridge.startService();
    await MediaKitServiceBridge.startListening();

    LogService.log('MediaKitEngine', 'Initialized');
  }

  @override
  Future<void> dispose() async {
    _cancelSleepTimerInternal();

    // Hapus referensi player dari settings service sebelum dispose.
    MediaKitSettingsService.unregisterPlayer();

    // Tell the Android service to remove the notification and stop itself
    // before cancelling the event subscription.
    await MediaKitServiceBridge.stopService();
    await MediaKitServiceBridge.stopListening();

    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    await _player?.dispose();
    _player        = null;
    _queue         = [];
    _currentIndex  = 0;
    LogService.log('MediaKitEngine', 'Disposed — semua resource dibebaskan');
  }

  void _subscribeToPlayer() {
    final p = _player;
    if (p == null) return;

    _subs.addAll([
      // playing / processingState → emit to Dart stream + push to Android service
      p.stream.playing.listen((playing) {
        _emitPlaybackState(playing: playing);
        MediaKitServiceBridge.updatePlaybackState(
          isPlaying:  playing,
          positionMs: p.state.position.inMilliseconds,
        );
      }),

      // buffering
      p.stream.buffering.listen((buffering) {
        _bufferingCtrl.add(buffering);
        _emitPlaybackState(buffering: buffering);
      }),

      // completed
      p.stream.completed.listen((completed) {
        if (!completed) return;
        if (_sleepEndOfSong && _sleepTimerActive) {
          _triggerSleepStop();
          return;
        }
        _emitPlaybackState(completed: true);
      }),

      // position — forward to Dart stream and throttle-push to Android service
      p.stream.position.listen((pos) {
        _positionCtrl.add(pos);
        _pushPositionIfDue(pos);
      }),

      // duration
      p.stream.duration.listen(_durationCtrl.add),

      // playlist / current track → emit to Dart stream + push metadata to service
      p.stream.playlist.listen((state) {
        final idx = state.index;
        if (idx < 0 || idx >= _queue.length) return;
        _currentIndex = idx;
        final song = _queue[idx];
        _currentTrackCtrl.add({
          'index':          idx,
          'id':             song.id,
          'nextTrackIndex': _computeNextIndex(idx),
        });
        // Reset position throttle so the first position event for the new
        // track is forwarded immediately (seek bar snaps to 0:00 at once).
        _lastPositionSentMs = 0;
        // Push track metadata to the Android foreground service so the
        // notification and lock-screen controls show the correct song.
        MediaKitServiceBridge.updateMetadata(
          title:      song.title,
          artist:     song.artist,
          artworkUri: song.artworkUri,
          durationMs: song.duration.inMilliseconds,
        );
      }),
    ]);

    // Emit session ID placeholder — media_kit tidak mengekspos audioSessionId.
    _audioSessionCtrl.add(-1);
  }

  // ── Position throttle push ────────────────────────────────────────────────

  /// Conditionally forwards [pos] to the Android [MediaKitPlaybackService] so
  /// the lock-screen / Wear OS seek bar stays accurate during playback.
  ///
  /// Strategy: piggyback on the existing [p.stream.position] subscription
  /// (which media_kit already fires ~every 100 ms while playing) instead of
  /// running a separate [Timer.periodic].  This avoids waking the Dart isolate
  /// on a separate schedule and naturally stops when [p.stream.position] goes
  /// quiet (i.e., when playback is paused or the player is idle).
  ///
  /// Two gates prevent unnecessary [MethodChannel] traffic:
  ///   1. **Playing guard** — skipped immediately if the player is not
  ///      currently playing (paused, stopped, or buffering with no audio).
  ///   2. **Timestamp gate** — skipped if fewer than [_kPositionUpdateIntervalMs]
  ///      ms have elapsed since the last successful push.
  ///
  /// [_lastPositionSentMs] is reset to 0 on track change and after a manual
  /// seek so those events always produce an immediate update.
  void _pushPositionIfDue(Duration pos) {
    if (!(_player?.state.playing ?? false)) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastPositionSentMs < _kPositionUpdateIntervalMs) return;
    _lastPositionSentMs = nowMs;
    // Fire-and-forget — we deliberately do not await so the stream listener
    // returns immediately. Errors are swallowed inside updatePlaybackState.
    MediaKitServiceBridge.updatePlaybackState(
      isPlaying:  true,
      positionMs: pos.inMilliseconds,
    );
  }

  // ── Transport command handler (from native via EventChannel) ──────────────

  /// Handles transport commands emitted by [MediaKitPlaybackService] when the
  /// user interacts with the lock screen, BT device, or notification buttons.
  Future<void> _handleTransportCommand(String action, int? positionMs) async {
  LogService.verbose(
    'MediaKitEngine',
    'transport command: $action positionMs=$positionMs',
  );

  switch (action) {
    case 'play':
      await _player?.play();

    case 'pause':
      await _player?.pause();

    case 'next':
      await _player?.next();

    case 'previous':
      final pos = _player?.state.position ?? Duration.zero;
      if (pos.inSeconds >= 3) {
        await _player?.seek(Duration.zero);
      } else {
        await _player?.previous();
      }

    case 'seek':
      if (positionMs != null) {
        _lastPositionSentMs = 0;
        await _player?.seek(Duration(milliseconds: positionMs));
      }

    case 'stop':
      await _player?.pause();
      await _player?.seek(Duration.zero);

    default:
      LogService.warn(
        'MediaKitEngine',
        'Unknown transport command: $action',
      );
  }
}

  // ── Transport ─────────────────────────────────────────────────────────────

  @override
  Future<void> play() async {
    await _player?.play();
    LogService.verbose('MediaKitEngine', 'play()');
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
    LogService.verbose('MediaKitEngine', 'pause()');
  }

  @override
  Future<void> stop() async {
    await _player?.pause();
    await _player?.seek(Duration.zero);
    _emitPlaybackState(playing: false);
    LogService.verbose('MediaKitEngine', 'stop()');
  }

  @override
  Future<void> seek(Duration position) async {
    // Reset throttle so the next position event (emitted by media_kit right
    // after the seek completes) is forwarded to the service immediately,
    // keeping the lock-screen seek bar accurate after a manual seek.
    _lastPositionSentMs = 0;
    await _player?.seek(position);
    LogService.verbose('MediaKitEngine', 'seek(${position.inSeconds}s)');
  }

  // ── Queue ─────────────────────────────────────────────────────────────────

  @override
  Future<void> setQueue(List<LocalSong> queue, int index) async {
    if (queue.isEmpty) return;
    _queue        = List.unmodifiable(queue);
    _currentIndex = index.clamp(0, queue.length - 1);
    await _player?.open(
      Playlist(_buildMediaList(queue), index: _currentIndex),
      play: false,
    );
    _emitQueueSnapshot();
    // Push the initial track metadata to the service immediately after setQueue
    // so the notification shows the correct song before playback starts.
    final song = _queue[_currentIndex];
    await MediaKitServiceBridge.updateMetadata(
      title:      song.title,
      artist:     song.artist,
      artworkUri: song.artworkUri,
      durationMs: song.duration.inMilliseconds,
    );
    LogService.log('MediaKitEngine', 'Queue: ${queue.length} lagu, idx=$_currentIndex');
  }

  @override
  Future<void> skipNext() async {
    await _player?.next();
    LogService.verbose('MediaKitEngine', 'skipNext()');
  }

  @override
  Future<void> skipPrevious() async {
    final pos = _player?.state.position ?? Duration.zero;
    if (pos.inSeconds >= 3) {
      await _player?.seek(Duration.zero);
    } else {
      await _player?.previous();
    }
    LogService.verbose('MediaKitEngine', 'skipPrevious()');
  }

  @override
  Future<void> setTrack(int index) async {
    if (index < 0 || index >= _queue.length) return;
    await _player?.jump(index);
    LogService.verbose('MediaKitEngine', 'setTrack($index)');
  }

  // ── Queue mutations ───────────────────────────────────────────────────────
  // media_kit 1.2.x tidak mendukung mutasi antrian in-place —
  // seluruh mutasi rebuild playlist.
  // TODO: perbarui saat media_kit menambahkan API add/remove/move per item.

  @override
  Future<void> insertNext(LocalSong song) async {
    final pos   = (_currentIndex + 1).clamp(0, _queue.length);
    final songs = List<LocalSong>.from(_queue)..insert(pos, song);
    await _rebuildQueue(songs, _currentIndex);
    LogService.log('MediaKitEngine', 'insertNext: ${song.title}');
  }

  @override
  Future<void> appendToQueue(LocalSong song) async {
    final songs = List<LocalSong>.from(_queue)..add(song);
    await _rebuildQueue(songs, _currentIndex);
    LogService.log('MediaKitEngine', 'appendToQueue: ${song.title}');
  }

  @override
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final songs    = List<LocalSong>.from(_queue)..removeAt(index);
    final newIndex = (index < _currentIndex)
        ? (_currentIndex - 1).clamp(0, songs.length - 1)
        : _currentIndex.clamp(0, songs.isNotEmpty ? songs.length - 1 : 0);
    await _rebuildQueue(songs, newIndex);
    LogService.log('MediaKitEngine', 'removeFromQueue($index)');
  }

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (_queue.length < 2) return;
    final songs = List<LocalSong>.from(_queue);
    final item  = songs.removeAt(oldIndex);
    songs.insert(newIndex, item);

    int newCurrent = _currentIndex;
    if (oldIndex == _currentIndex) {
      newCurrent = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      newCurrent = _currentIndex - 1;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      newCurrent = _currentIndex + 1;
    }
    await _rebuildQueue(songs, newCurrent.clamp(0, songs.length - 1));
    LogService.log('MediaKitEngine', 'reorderQueue($oldIndex → $newIndex)');
  }

  /// Rebuilds the media_kit [Playlist] from [songs], jumping to [targetIndex].
  ///
  /// Position is restored only when the currently-playing track is still at
  /// [targetIndex] in the new list — identified by song ID, not index value.
  /// This fixes the bug where removing an item BEFORE the current track shifts
  /// the index, causing position restoration to be incorrectly skipped.
  Future<void> _rebuildQueue(List<LocalSong> songs, int targetIndex) async {
    final wasPlaying = _player?.state.playing ?? false;
    final position   = _player?.state.position ?? Duration.zero;
    final prevIndex  = _currentIndex;

    // Determine whether the currently-playing track is still at targetIndex
    // by comparing song IDs, not raw index values.
    final sameTrack = prevIndex  < _queue.length &&
        targetIndex < songs.length &&
        songs[targetIndex].id == _queue[prevIndex].id;

    _queue        = List.unmodifiable(songs);
    _currentIndex = targetIndex;

    await _player?.open(
      Playlist(_buildMediaList(songs), index: _currentIndex),
      play: false,
    );

    if (sameTrack && position > Duration.zero) await _player?.seek(position);
    if (wasPlaying) await _player?.play();
    _emitQueueSnapshot();
  }

  // ── Mode ──────────────────────────────────────────────────────────────────

  @override
  Future<void> setRepeatMode(String mode) async {
    _repeatMode = mode;
    final pm = switch (mode) {
      'all' => PlaylistMode.loop,
      'one' => PlaylistMode.single,
      _     => PlaylistMode.none,
    };
    await _player?.setPlaylistMode(pm);
    _repeatCtrl.add(mode);
    LogService.verbose('MediaKitEngine', 'repeatMode=$mode');
  }

  @override
  Future<void> setShuffleMode(bool enabled) async {
    _shuffleEnabled = enabled;
    await _player?.setShuffle(enabled);
    _shuffleCtrl.add(enabled);
    LogService.verbose('MediaKitEngine', 'shuffle=$enabled');
  }

  // ── Playback parameters ───────────────────────────────────────────────────

  @override
  Future<void> setVolume(double volume) async {
    await _player?.setVolume(volume.clamp(0.0, 1.0) * 100.0);
  }

  /// Mengatur kecepatan putar. Rate dikirim langsung ke player.
  ///
  /// Dengan [PlayerConfiguration(pitch: true)], rate dan pitch adalah
  /// parameter terpisah — mengubah rate tidak mempengaruhi pitch.
  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed.clamp(0.25, 4.0);
    await _player?.setRate(_speed);
    LogService.verbose('MediaKitEngine', 'setSpeed($_speed)');
  }

  /// Mengatur pitch secara independen dari rate.
  ///
  /// Menggunakan [Player.setPitch()] yang tersedia karena
  /// [PlayerConfiguration(pitch: true)] diaktifkan saat inisialisasi.
  /// Pitch 1.0 = normal, 0.5 = satu oktaf lebih rendah, 2.0 = satu oktaf lebih tinggi.
  @override
  Future<void> setPitch(double pitch) async {
    _pitchFactor = pitch;
    await _player?.setPitch(pitch.clamp(0.05, 8.0));
    LogService.verbose('MediaKitEngine', 'setPitch($pitch)');
  }

  // ── DSP effects (no-op — media_kit tidak mengekspos Android AudioEffect) ──

  @override Future<void> setBassBoost(int strength) async {}
  @override Future<void> setBassBoostEnabled(bool enabled) async {}
  @override Future<void> setVirtualizerEnabled(bool enabled) async {}
  @override Future<void> setVirtualizerStrength(int strength) async {}
  @override Future<void> setReverbPreset(int preset) async {}
  @override Future<void> setEqualizerEnabled(bool enabled) async {}
  @override Future<void> setEqualizerBandGain(int band, double gainDb) async {}
  @override Future<void> setLoudnessEnabled(bool enabled) async {}
  @override Future<void> setLoudnessTargetGain(double gainMb) async {}
  @override Future<void> setCrossfadeDuration(double seconds) async {}

  @override
  Future<EngineEqualizerParameters?> getEqualizerParameters() async => null;

  @override
  Future<Map<String, dynamic>?> getEffectSupport() async => {
        'virtualizerSupported': false,
        'bassBoostSupported':   false,
        'reverbSupported':      false,
      };

  // ── Capabilities (no-op — media_kit tidak mendukung) ─────────────────────

  /// Skip silence tidak tersedia di media_kit.
  /// Stream memancar nilai yang di-set agar UI tidak hang.
  @override
  Future<void> setSkipSilence(bool enabled) async {
    _skipSilenceCtrl.add(enabled);
  }

  /// Stereo widening tidak tersedia di media_kit.
  /// Stream memancar nilai yang di-set agar UI tidak hang.
  @override
  Future<void> setStereoWidening({
    required bool enabled,
    required double strength,
  }) async {
    _stereoWideningCtrl.add({'enabled': enabled, 'strength': strength});
  }

  @override
  Future<Map<String, dynamic>?> getPlaybackStats() async => null;

  // ── Audio format ─────────────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>?> getAudioFormat() async => null;

  // ── Sleep timer (Dart-side) ───────────────────────────────────────────────

  @override
  Future<void> setSleepTimer(int durationMs) async {
    _cancelSleepTimerInternal();
    _sleepEndOfSong   = false;
    _sleepTimerActive = true;
    _sleepRemainingMs = durationMs;
    _emitSleepTimer();

    _sleepCountdownTick = Timer.periodic(const Duration(seconds: 1), (_) {
      _sleepRemainingMs = (_sleepRemainingMs - 1000).clamp(0, durationMs);
      _emitSleepTimer();
    });
    _sleepTimer = Timer(Duration(milliseconds: durationMs), _triggerSleepStop);
    LogService.log('MediaKitEngine', 'sleepTimer: ${durationMs}ms');
  }

  @override
  Future<void> setSleepTimerEndOfSong() async {
    _cancelSleepTimerInternal();
    _sleepEndOfSong   = true;
    _sleepTimerActive = true;
    _sleepRemainingMs = 0;
    _emitSleepTimer();
    LogService.log('MediaKitEngine', 'sleepTimer: endOfSong mode');
  }

  @override
  Future<void> cancelSleepTimer() async {
    _cancelSleepTimerInternal();
    _emitSleepTimer();
    LogService.log('MediaKitEngine', 'sleepTimer cancelled');
  }

  void _cancelSleepTimerInternal() {
    _sleepTimer?.cancel();
    _sleepCountdownTick?.cancel();
    _sleepTimer         = null;
    _sleepCountdownTick = null;
    _sleepTimerActive   = false;
    _sleepEndOfSong     = false;
    _sleepRemainingMs   = 0;
  }

  Future<void> _triggerSleepStop() async {
    _cancelSleepTimerInternal();
    _emitSleepTimer();
    await _player?.pause();
    LogService.log('MediaKitEngine', 'sleepTimer triggered — paused');
  }

  void _emitSleepTimer() {
    _sleepTimerCtrl.add({
      'active':      _sleepTimerActive,
      'endOfSong':   _sleepEndOfSong,
      'remainingMs': _sleepRemainingMs,
    });
  }

  // ── State snapshot ────────────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>?> getPlaybackSnapshot() async {
    final p = _player;
    if (p == null || _queue.isEmpty) return null;
    return {
      'queue':                   _queue.map((s) => s.toMap()).toList(),
      'currentIndex':            _currentIndex,
      'isPlaying':               p.state.playing,
      'processingState':         _processingStateString(p),
      'positionMs':              p.state.position.inMilliseconds,
      'durationMs':              p.state.duration.inMilliseconds,
      'shuffleEnabled':          _shuffleEnabled,
      'repeatMode':              _repeatMode,
      'sleepTimerActive':        _sleepTimerActive,
      'sleepTimerRemainingMs':   _sleepRemainingMs,
    };
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  @override Stream<Map<dynamic, dynamic>> get playbackStateStream => _playbackStateCtrl.stream;
  @override Stream<Duration>              get positionStream       => _positionCtrl.stream;
  @override Stream<Duration>              get durationStream       => _durationCtrl.stream;
  @override Stream<Map<dynamic, dynamic>?> get currentTrackStream => _currentTrackCtrl.stream;
  @override Stream<List<dynamic>>         get queueStream          => _queueCtrl.stream;
  @override Stream<bool>                  get bufferingStateStream => _bufferingCtrl.stream;
  @override Stream<bool>                  get shuffleModeStream    => _shuffleCtrl.stream;
  @override Stream<String>               get repeatModeStream     => _repeatCtrl.stream;
  @override Stream<Map<dynamic, dynamic>> get sleepTimerStream     => _sleepTimerCtrl.stream;
  @override Stream<int>                  get audioSessionIdStream  => _audioSessionCtrl.stream;

  /// Media_kit tidak menyediakan audio format stream.
  @override
  Stream<Map<dynamic, dynamic>> get audioFormatStream =>
      _emptyAudioFormatStream;

  /// Memancar saat [setSkipSilence] dipanggil.
  @override
  Stream<bool> get skipSilenceStream => _skipSilenceCtrl.stream;

  /// Memancar saat [setStereoWidening] dipanggil.
  @override
  Stream<Map<dynamic, dynamic>> get stereoWideningStream =>
      _stereoWideningCtrl.stream;

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<Media> _buildMediaList(List<LocalSong> songs) =>
      songs.map((s) => Media('file://${s.path}')).toList();

  void _emitQueueSnapshot() {
    _queueCtrl.add(_queue.map((s) => s.toMap()).toList());
  }

  void _emitPlaybackState({
    bool? playing,
    bool? buffering,
    bool? completed,
  }) {
    final p = _player;
    if (p == null) return;

    final isPlaying   = playing  ?? p.state.playing;
    final isBuffering = buffering ?? p.state.buffering;
    final isCompleted = completed ?? false;

    final String state;
    if (_queue.isEmpty) {
      state = 'idle';
    } else if (isCompleted) {
      state = 'completed';
    } else if (isBuffering) {
      state = 'buffering';
    } else {
      state = 'ready';
    }

    _playbackStateCtrl.add({
      'playing':         isPlaying,
      'processingState': state,
    });
  }

  String _processingStateString(Player p) {
    if (_queue.isEmpty) return 'idle';
    if (p.state.buffering) return 'buffering';
    return 'ready';
  }

  int _computeNextIndex(int current) {
    final len = _queue.length;
    if (len == 0) return -1;
    if (_repeatMode == 'one') return current;
    if (current < len - 1) return current + 1;
    if (_repeatMode == 'all') return 0;
    return -1;
  }
}
