import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../../../models/local_song.dart';
import '../engine_abstraction.dart';
import '../../log_service.dart';

/// Engine berbasis media_kit 1.2.6.
///
/// Feature parity notes:
///   ✅ Play / Pause / Stop / Seek
///   ✅ Queue / Playlist
///   ✅ Next / Previous / Jump to track
///   ✅ Shuffle (media_kit native)
///   ✅ Repeat (PlaylistMode)
///   ✅ Background playback (media_kit handles native Android foreground service)
///   ✅ Notification / MediaSession (media_kit_audio platform setup)
///   ✅ Speed / Volume
///   ✅ Pitch (via rate — media_kit tidak memisahkan pitch & speed seperti ExoPlayer;
///             pitch hanya diterapkan sebagai perubahan rate. Lihat TODO di bawah.)
///   ✅ Sleep timer (Dart-side Timer)
///   ✅ Queue persistence (via getPlaybackSnapshot)
///   ✅ Lyrics (positionStream tersedia)
///   ✅ Artwork (dari LocalSong.artworkUri)
///   ⚠️  Lock screen / Bluetooth / Headset: bergantung pada platform integration
///       dari media_kit_audio — berfungsi di Android dengan library native.
///   ❌ Audio effects (EQ, Bass Boost, Virtualizer, Reverb):
///       media_kit tidak mengekspos Android AudioEffect API. Semua efek DSP
///       tetap native dan hanya aktif saat engine Media3 digunakan.
///       TODO: tambahkan Dart-side audio processor bila media_kit
///       mendukung AudioProcessor hook di masa mendatang.
///   ❌ Crossfade: media_kit 1.2.6 tidak mendukung dual-player crossfade.
///       TODO: implementasikan manual dengan dua Player saat media_kit
///       memiliki API AudioProcessor yang stabil.
///   ❌ ReplayGain via LoudnessEnhancer: tidak tersedia di media_kit.
///       TODO: terapkan gain pre-computation di Dart dan atur volume player.
///   ❌ Audio session ID: media_kit tidak mengekspos audioSessionId.
///       audioSessionIdStream memancarkan -1 (tidak ada subscriber yang crash).
///   ⚠️  Hi-Res audio: bergantung pada codec support perangkat via MediaCodec
///       yang digunakan media_kit_libs_android_audio.
class MediaKitEngine implements AbstractAudioEngine {
  Player? _player;
  List<LocalSong> _queue = [];
  int _currentIndex = 0;
  bool _shuffleEnabled = false;
  String _repeatMode = 'off'; // 'off' | 'all' | 'one'

  // Sleep timer (Dart-side, karena tidak ada native Handler di media_kit)
  Timer? _sleepTimer;
  bool  _sleepEndOfSong    = false;
  bool  _sleepTimerActive  = false;
  int   _sleepRemainingMs  = 0;
  Timer? _sleepCountdownTick;

  // StreamControllers — format identik dengan Media3PlaybackBridge
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

  final List<StreamSubscription<dynamic>> _subs = [];

  // ── Initialize ────────────────────────────────────────────────────────────

  @override
  Future<void> initialize() async {
    _player = Player();
    _subscribeToPlayer();
    LogService.log('MediaKitEngine', 'Initialized');
  }

  void _subscribeToPlayer() {
    final p = _player;
    if (p == null) return;

    // playing / processingState
    _subs.add(p.stream.playing.listen((playing) {
      _emitPlaybackState(playing: playing);
    }));

    // buffering
    _subs.add(p.stream.buffering.listen((buffering) {
      _bufferingCtrl.add(buffering);
      _emitPlaybackState(buffering: buffering);
    }));

    // completed (track ended → handle repeat/next)
    _subs.add(p.stream.completed.listen((completed) {
      if (!completed) return;
      if (_sleepEndOfSong && _sleepTimerActive) {
        _triggerSleepStop();
        return;
      }
      _emitPlaybackState(completed: true);
    }));

    // position
    _subs.add(p.stream.position.listen((pos) {
      _positionCtrl.add(pos);
    }));

    // duration
    _subs.add(p.stream.duration.listen((dur) {
      _durationCtrl.add(dur);
    }));

    // playlist / current track
    _subs.add(p.stream.playlist.listen((state) {
      final idx = state.index;
      if (idx < 0 || idx >= _queue.length) return;
      _currentIndex = idx;
      final song = _queue[idx];
      final next = _computeNextIndex(idx);
      _currentTrackCtrl.add({
        'index':          idx,
        'id':             song.id,
        'nextTrackIndex': next,
      });
    }));

    // rate (media_kit menggunakan rate untuk kecepatan)
    // tidak perlu stream khusus, rate diatur via setSpeed

    // Emit audio session stream kosong agar listener tidak hang
    // media_kit tidak mengekspos audioSessionId
    _audioSessionCtrl.add(-1);
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    _cancelSleepTimerInternal();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _player?.dispose();
    _player = null;
    _queue  = [];
    _currentIndex = 0;
    LogService.log('MediaKitEngine', 'Disposed — semua resource dibebaskan');
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
    await _player?.seek(position);
    LogService.verbose('MediaKitEngine', 'seek(${position.inSeconds}s)');
  }

  // ── Queue ─────────────────────────────────────────────────────────────────

  @override
  Future<void> setQueue(List<LocalSong> queue, int index) async {
    if (queue.isEmpty) return;
    _queue = List.unmodifiable(queue);
    _currentIndex = index.clamp(0, queue.length - 1);

    final medias = _buildMediaList(queue);
    await _player?.open(
      Playlist(medias, index: _currentIndex),
      play: false,
    );
    _emitQueueSnapshot();
    LogService.log(
      'MediaKitEngine',
      'Queue set: ${queue.length} lagu, index=$_currentIndex',
    );
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
  // media_kit 1.2.6 tidak mendukung mutasi antrian secara langsung pada Player
  // yang sedang berjalan — seluruh mutasi harus rebuild playlist.
  // TODO: perbarui saat media_kit menambahkan API add/remove/move per item.

  @override
  Future<void> insertNext(LocalSong song) async {
    final pos = (_currentIndex + 1).clamp(0, _queue.length);
    final mutable = List<LocalSong>.from(_queue)..insert(pos, song);
    await _rebuildQueue(mutable, _currentIndex);
    LogService.log('MediaKitEngine', 'insertNext: ${song.title}');
  }

  @override
  Future<void> appendToQueue(LocalSong song) async {
    final mutable = List<LocalSong>.from(_queue)..add(song);
    await _rebuildQueue(mutable, _currentIndex);
    LogService.log('MediaKitEngine', 'appendToQueue: ${song.title}');
  }

  @override
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final mutable = List<LocalSong>.from(_queue)..removeAt(index);
    final newIndex = index <= _currentIndex
        ? (_currentIndex - 1).clamp(0, mutable.length - 1)
        : _currentIndex;
    await _rebuildQueue(mutable, newIndex);
    LogService.log('MediaKitEngine', 'removeFromQueue($index)');
  }

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (_queue.length < 2) return;
    final mutable = List<LocalSong>.from(_queue);
    final item    = mutable.removeAt(oldIndex);
    mutable.insert(newIndex, item);

    int newCurrent = _currentIndex;
    if (oldIndex == _currentIndex) {
      newCurrent = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      newCurrent = _currentIndex - 1;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      newCurrent = _currentIndex + 1;
    }
    await _rebuildQueue(mutable, newCurrent);
    LogService.log('MediaKitEngine', 'reorderQueue($oldIndex → $newIndex)');
  }

  Future<void> _rebuildQueue(List<LocalSong> songs, int index) async {
    final wasPlaying = _player?.state.playing ?? false;
    final position   = _player?.state.position ?? Duration.zero;
    _queue        = List.unmodifiable(songs);
    _currentIndex = index.clamp(0, songs.isNotEmpty ? songs.length - 1 : 0);

    await _player?.open(
      Playlist(_buildMediaList(songs), index: _currentIndex),
      play: false,
    );
    if (_currentIndex == index) await _player?.seek(position);
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
    LogService.verbose('MediaKitEngine', 'setRepeatMode($mode)');
  }

  @override
  Future<void> setShuffleMode(bool enabled) async {
    _shuffleEnabled = enabled;
    await _player?.setShuffle(enabled);
    _shuffleCtrl.add(enabled);
    LogService.verbose('MediaKitEngine', 'setShuffleMode($enabled)');
  }

  // ── Parameters ────────────────────────────────────────────────────────────

  @override
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0) * 100.0;
    await _player?.setVolume(clamped);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player?.setRate(speed.clamp(0.25, 4.0));
  }

  // TODO: media_kit 1.2.6 tidak memisahkan pitch dari rate.
  // Pitch diubah dengan mengalikan rate saat ini dengan faktor pitch.
  // Ini mengakibatkan perubahan kecepatan juga. Implementasi pitch
  // independen membutuhkan SoX atau audio processor tambahan.
  @override
  Future<void> setPitch(double pitch) async {
    final currentRate = _player?.state.rate ?? 1.0;
    await _player?.setRate((currentRate * pitch).clamp(0.25, 4.0));
    LogService.verbose(
      'MediaKitEngine',
      'setPitch($pitch) — diterapkan sebagai rate multiplier (limitation)',
    );
  }

  // ── Sleep timer (Dart-side) ───────────────────────────────────────────────

  @override
  Future<void> setSleepTimer(int durationMs) async {
    _cancelSleepTimerInternal();
    _sleepEndOfSong   = false;
    _sleepTimerActive = true;
    _sleepRemainingMs = durationMs;

    _emitSleepTimer();

    // Countdown tick setiap detik untuk UI
    _sleepCountdownTick = Timer.periodic(const Duration(seconds: 1), (_) {
      _sleepRemainingMs = (_sleepRemainingMs - 1000).clamp(0, durationMs);
      _emitSleepTimer();
    });

    _sleepTimer = Timer(Duration(milliseconds: durationMs), _triggerSleepStop);
    LogService.log('MediaKitEngine', 'Sleep timer: ${durationMs}ms');
  }

  @override
  Future<void> setSleepTimerEndOfSong() async {
    _cancelSleepTimerInternal();
    _sleepEndOfSong   = true;
    _sleepTimerActive = true;
    _sleepRemainingMs = 0;
    _emitSleepTimer();
    LogService.log('MediaKitEngine', 'Sleep timer: end-of-song mode');
  }

  @override
  Future<void> cancelSleepTimer() async {
    _cancelSleepTimerInternal();
    _emitSleepTimer();
    LogService.log('MediaKitEngine', 'Sleep timer cancelled');
  }

  void _cancelSleepTimerInternal() {
    _sleepTimer?.cancel();
    _sleepCountdownTick?.cancel();
    _sleepTimer       = null;
    _sleepCountdownTick = null;
    _sleepTimerActive = false;
    _sleepEndOfSong   = false;
    _sleepRemainingMs = 0;
  }

  Future<void> _triggerSleepStop() async {
    _cancelSleepTimerInternal();
    _emitSleepTimer();
    await _player?.pause();
    LogService.log('MediaKitEngine', 'Sleep timer triggered — playback paused');
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
      'queue':         _queue.map((s) => s.toMap()).toList(),
      'currentIndex':  _currentIndex,
      'isPlaying':     p.state.playing,
      'processingState': _processingStateString(p),
      'positionMs':    p.state.position.inMilliseconds,
      'durationMs':    p.state.duration.inMilliseconds,
      'shuffleEnabled': _shuffleEnabled,
      'repeatMode':    _repeatMode,
      'sleepTimerActive':      _sleepTimerActive,
      'sleepTimerRemainingMs': _sleepRemainingMs,
    };
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  @override
  Stream<Map<dynamic, dynamic>> get playbackStateStream =>
      _playbackStateCtrl.stream;

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<Duration> get durationStream => _durationCtrl.stream;

  @override
  Stream<Map<dynamic, dynamic>?> get currentTrackStream =>
      _currentTrackCtrl.stream;

  @override
  Stream<List<dynamic>> get queueStream => _queueCtrl.stream;

  @override
  Stream<bool> get bufferingStateStream => _bufferingCtrl.stream;

  @override
  Stream<bool> get shuffleModeStream => _shuffleCtrl.stream;

  @override
  Stream<String> get repeatModeStream => _repeatCtrl.stream;

  @override
  Stream<Map<dynamic, dynamic>> get sleepTimerStream =>
      _sleepTimerCtrl.stream;

  @override
  Stream<int> get audioSessionIdStream => _audioSessionCtrl.stream;

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

    final isPlaying  = playing ?? p.state.playing;
    final isBuffering = buffering ?? p.state.buffering;
    final isCompleted = completed ?? false;

    final String state;
    if (_queue.isEmpty) {
      state = 'idle';
    } else if (isCompleted) {
      state = 'completed';
    } else if (isBuffering) {
      state = 'buffering';
    } else if (isPlaying || p.state.position > Duration.zero) {
      state = 'ready';
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
