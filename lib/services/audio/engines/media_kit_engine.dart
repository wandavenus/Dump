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

  // Lookup map: raw path (tanpa prefix 'file://') → index di _queue.
 // media_kit's Media.normalizeURI() selalu strip prefix file:// sehingga
 // Media.uri berupa path mentah, bukan URI penuh.
  // Dibangun ulang setiap kali _queue berubah (setQueue / _rebuildQueue).
  // Menjamin O(1) lookup dan perilaku first-occurrence yang deterministik,
  // konsisten dengan semantik indexWhere() yang digantikannya.
  Map<String, int> _uriToQueueIndex = {};

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

  // Lifecycle guard — set to true as the very first step of dispose().
  // Every callback that touches _player must check this and return early.
  bool _disposed = false;

  // ── Play/pause fade ───────────────────────────────────────────────────────
  // Tracks the volume the user intentionally set (0.0–1.0, default 1.0).
  // The fade temporarily drives player volume below this; setVolume() always
  // updates this field so the next fade-in restores to the correct level.
  double _userVolume = 1.0;

  // Active fade ticker — cancelled and replaced on every new play/pause call
  // so rapid toggling always starts a clean fade from the current position.
  Timer? _fadeTimer;

  // Cancel any in-progress fade without touching player volume.
  void _cancelFade() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
  }

  // Steps player volume from [from] toward the value returned by [getTo]
  // (both in media_kit's 0–100 scale) over ~400 ms (20 steps × 20 ms).
  // [getTo] is evaluated on every tick so that a mid-fade setVolume() call
  // is picked up immediately — the fade retargets smoothly without a restart.
  // Calls [onDone] after the final step.
  // Exits early and cancels itself if the engine is disposed or player gone.
  void _startFade(double from, double Function() getTo, void Function() onDone) {
    _cancelFade();
    const totalSteps = 20;
    int step = 0;
    LogService.verbose(
      'MediaKitEngine',
      '_startFade from=$from → target=${getTo()} (${totalSteps} steps)',
    );
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 20), (t) {
      if (_disposed || _player == null) {
        t.cancel();
        _fadeTimer = null;
        return;
      }
      step++;
      final to  = getTo();
      final vol = from + (to - from) * (step / totalSteps);
      _player?.setVolume(vol.clamp(0.0, 100.0));
      LogService.verbose('MediaKitEngine', '_fade step=$step/$totalSteps vol=${vol.toStringAsFixed(1)}');
      if (step >= totalSteps) {
        t.cancel();
        _fadeTimer = null;
        onDone();
      }
    });
  }

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
    // ① Mark disposed immediately — all callbacks and async continuations
    //    that check _disposed will become no-ops from this point forward.
    _disposed = true;

    // ② Sever the transport handler before any async work so no native
    //    command can reach _handleTransportCommand while we tear down.
    MediaKitServiceBridge.setTransportCommandHandler(null);

    // ③ Cancel sleep timers and any in-progress fade — pure Dart, no await needed.
    _cancelSleepTimerInternal();
    _cancelFade();

    // ④ Capture and null _player NOW, before the first await.
    //
    //    This closes the remaining async race window: an async method
    //    (e.g. _handleTransportCommand, _rebuildQueue) that entered before
    //    _disposed was set and is suspended at an internal `await` will
    //    resume and call `_player?.method()` — which is now a no-op because
    //    _player is already null.  The captured reference is used below to
    //    actually dispose the instance after all other teardown is complete.
    final playerToDispose = _player;
    _player           = null;
    _queue            = [];
    _currentIndex     = 0;
    _uriToQueueIndex  = {};

    // ④.5 Stop playback explicitly, right now, using the captured reference —
    //     do NOT rely on a native "stop" transport event to do this for us.
    //
    //     Previously, playback was actually halted as a side effect of the
    //     native service emitting a "stop" transport command, which flowed
    //     through the (still-active) EventChannel into
    //     _handleTransportCommand('stop') → _player.pause(). That path is
    //     now intentionally severed before this point (_disposed = true and
    //     the transport handler is cleared in steps ①–②), which closes the
    //     dispose race — but it also means nothing else in this method stops
    //     the audio. Without this explicit pause, stopListening()/
    //     stopService() below just tear down the notification/service while
    //     mpv keeps rendering audio, and playerToDispose.dispose() runs on a
    //     player that is still playing.
    //
    //     media_kit's Player.pause() forwards to mpv's `pause` property on
    //     the native platform thread; mpv applies that property change
    //     synchronously before the platform-channel call returns, so the
    //     returned Future only completes once playback has actually been
    //     paused natively. There's no separate "confirmed paused" async
    //     signal to await, so `await pause()` is sufficient here — no
    //     Future.delayed() or extra polling required.
    if (playerToDispose != null) {
      await playerToDispose.pause();
    }

    // ⑤ Cancel the EventChannel subscription BEFORE telling native to stop.
    //    Rationale: the native "release" handler calls updateStateAndEmit("stop")
    //    which enqueues a transport event in the Dart event queue BEFORE
    //    result.success(null) is returned. Cancelling the subscription first
    //    ensures that event is dropped by the channel layer and never reaches
    //    the Dart listener. No deadlock risk: stopService() waits on a
    //    MethodChannel reply, not on any transport event.
    await MediaKitServiceBridge.stopListening();

    // ⑥ Unregister player from settings service.
    MediaKitSettingsService.unregisterPlayer();

    // ⑦ Tell the Android service to remove the notification and stop itself.
    await MediaKitServiceBridge.stopService();

    // ⑧ Cancel player stream subscriptions.
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();

    // ⑨ Dispose the captured player instance last, after all other
    //    teardown is done and _player field is already null.
    await playerToDispose?.dispose();
    LogService.log('MediaKitEngine', 'Disposed — semua resource dibebaskan');
  }

  void _subscribeToPlayer() {
    final p = _player;
    if (p == null) return;

    _subs.addAll([
      // playing / processingState → emit to Dart stream + push to Android service
      p.stream.playing.listen((playing) {
        if (_disposed) return;
        _emitPlaybackState(playing: playing);
        MediaKitServiceBridge.updatePlaybackState(
          isPlaying:  playing,
          positionMs: p.state.position.inMilliseconds,
        );
      }),

      // buffering
      p.stream.buffering.listen((buffering) {
        if (_disposed) return;
        _bufferingCtrl.add(buffering);
        _emitPlaybackState(buffering: buffering);
      }),

      // completed
      p.stream.completed.listen((completed) {
        if (_disposed) return;
        if (!completed) return;
        if (_sleepEndOfSong && _sleepTimerActive) {
          _triggerSleepStop();
          return;
        }
        _emitPlaybackState(completed: true);
      }),

      // position — forward to Dart stream and throttle-push to Android service
      p.stream.position.listen((pos) {
        if (_disposed) return;
        _positionCtrl.add(pos);
        _pushPositionIfDue(pos);
      }),

      // duration
      p.stream.duration.listen((dur) {
        if (_disposed) return;
        _durationCtrl.add(dur);
      }),

      // playlist / current track → emit to Dart stream + push metadata to service
      //
      // IMPORTANT: state.index is the position within media_kit's *native*
      // playlist order. When shuffle is enabled, media_kit/mpv physically
      // reorders its internal playlist — state.index no longer corresponds
      // to the position of that same track in `_queue`, which is always
      // kept in original (unshuffled) order for queue display/persistence.
      // Resolve the actual currently-playing song by matching the native
      // media's URI back to `_queue` instead of assuming the indices align,
      // so metadata sent to Flutter always describes the track that is
      // actually audible — regardless of shuffle state.
      p.stream.playlist.listen((state) {
        if (_disposed) return;
        final idx = state.index;
        if (idx < 0 || idx >= state.medias.length) return;
        final currentUri = state.medias[idx].uri;
        final queueIdx   = _uriToQueueIndex[currentUri] ?? -1;

        if (queueIdx < 0) {
          LogService.warn('MediaKitEngine', 'URI mismatch detected: $currentUri');
          return;
        }
        _currentIndex = queueIdx;
        final song = _queue[queueIdx];
        _currentTrackCtrl.add({
          'index':          queueIdx,
          'id':             song.id,
          'nextTrackIndex': _computeNextIndex(queueIdx),
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
    if (_disposed) return;
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
  // Guard: engine is in the process of being (or has been) disposed.
  // This catches any event that was already queued in the Dart event loop
  // before the subscription was cancelled, preventing calls to a player
  // that is no longer valid.
  if (_disposed) return;

  LogService.verbose(
    'MediaKitEngine',
    'transport command: $action positionMs=$positionMs',
  );

  switch (action) {
    case 'play':
      await play();

    case 'pause':
      await pause();

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
    if (_disposed || _player == null) return;
    // Cancel any fade that was in progress (e.g. a pause fade that hadn't
    // finished yet) so we always start the fade-in from a known state.
    _cancelFade();
    // Set to silent first, then start playback, then fade up.
    // Starting playback before fading ensures there is no audible gap
    // between the setVolume(0) call and the first decoded frame.
    await _player?.setVolume(0);
    await _player?.play();
    _startFade(0, () => _userVolume * 100, () {});
    LogService.verbose('MediaKitEngine', 'play() [fade-in]');
  }

  @override
  Future<void> pause() async {
    if (_disposed || _player == null) return;
    // Capture current volume before cancelling (cancel doesn't touch volume).
    final currentVol = _player!.state.volume; // 0–100
    _cancelFade();
    // Fade to silence, then pause, then restore volume to _userVolume so
    // the next play() fade-in starts from the correct target level.
    _startFade(currentVol, () => 0, () async {
      if (_disposed || _player == null) return;
      await _player?.pause();
      await _player?.setVolume(_userVolume * 100);
    });
    LogService.verbose('MediaKitEngine', 'pause() [fade-out]');
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
    _queue           = List.unmodifiable(queue);
    _currentIndex    = index.clamp(0, queue.length - 1);
    _rebuildUriIndex(_queue);
    await _player?.open(
      Playlist(_buildMediaList(queue), index: _currentIndex),
      play: false,
    );
    // Guard: engine mungkin sudah di-dispose saat open() masih berjalan.
    if (_disposed) return;
    // open() me-reset playlist mpv ke urutan asli — re-apply shuffle agar
    // urutan native mpv konsisten dengan _shuffleEnabled.
    if (_shuffleEnabled) await _player?.setShuffle(true);
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
    final p = _player;
    if (p == null) return;
    // `index` arrives in `_queue`'s original (unshuffled) order — the same
    // space the UI/queue view uses. media_kit's jump() sets mpv's native
    // `playlist-pos` directly, which is in *native* playlist order and gets
    // reordered independently when shuffle is enabled (see the playlist
    // listener above for the same original↔native distinction). Resolve the
    // target song's URI to its actual position in the native playlist so
    // tapping a queue item jumps to the correct track regardless of shuffle
    // state, instead of assuming the two index spaces align.
    final targetUri = _queue[index].path;
    final nativeMedias = p.state.playlist.medias;
    final nativeIdx    = nativeMedias.indexWhere((m) => m.uri == targetUri);
    await p.jump(nativeIdx >= 0 ? nativeIdx : index);
    LogService.verbose(
      'MediaKitEngine',
      'setTrack(queueIdx=$index → nativeIdx=${nativeIdx >= 0 ? nativeIdx : index})',
    );
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
    if (_disposed) return;
    final wasPlaying = _player?.state.playing ?? false;
    final position   = _player?.state.position ?? Duration.zero;
    final prevIndex  = _currentIndex;

    // Determine whether the currently-playing track is still at targetIndex
    // by comparing song IDs, not raw index values.
    final sameTrack = prevIndex  < _queue.length &&
        targetIndex < songs.length &&
        songs[targetIndex].id == _queue[prevIndex].id;

    _queue           = List.unmodifiable(songs);
    _currentIndex    = targetIndex;
    _rebuildUriIndex(_queue);

    await _player?.open(
      Playlist(_buildMediaList(songs), index: _currentIndex),
      play: false,
    );
    // Guard: engine mungkin sudah di-dispose saat open() masih berjalan.
    // Cegah emisi stale (_emitQueueSnapshot, seek, play) ke stream yang
    // sudah closed — simetris dengan guard yang sama di setQueue().
    if (_disposed) return;
    // open() me-reset playlist mpv ke urutan asli — re-apply shuffle agar
    // mpv kembali mengacak urutan native sesuai state yang tersimpan.
    if (_shuffleEnabled) await _player?.setShuffle(true);

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

  final playlist = _player?.state.playlist;
  if (playlist != null &&
      playlist.index >= 0 &&
      playlist.index < playlist.medias.length) {
    final currentUri = playlist.medias[playlist.index].uri;
    final queueIdx   = _uriToQueueIndex[currentUri] ?? -1;

    if (queueIdx >= 0) {
      _currentIndex = queueIdx;

      final song = _queue[queueIdx];

      _currentTrackCtrl.add({
        'index': queueIdx,
        'id': song.id,
        'nextTrackIndex': _computeNextIndex(queueIdx),
      });
    }
  }

  _shuffleCtrl.add(enabled);
  LogService.verbose('MediaKitEngine', 'shuffle=$enabled');
}

  // ── Playback parameters ───────────────────────────────────────────────────

  @override
  Future<void> setVolume(double volume) async {
    _userVolume = volume.clamp(0.0, 1.0);
    // Only push to player immediately when not fading — if a fade is running,
    // the target is already _userVolume * 100 so it will land there naturally.
    if (_fadeTimer == null) {
      await _player?.setVolume(_userVolume * 100.0);
    }
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
    if (_disposed) return;
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

  /// Membangun ulang [_uriToQueueIndex] dari [songs].
  ///
  /// Harus dipanggil setiap kali [_queue] di-assign ulang (setQueue /
  /// _rebuildQueue). Map menjamin O(1) lookup dan perilaku first-occurrence
  /// yang deterministik — konsisten dengan indexWhere() yang digantikannya.
  void _rebuildUriIndex(List<LocalSong> songs) {
    final map = <String, int>{};
    for (var i = 0; i < songs.length; i++) {
      // putIfAbsent memastikan entri pertama (indeks terkecil) yang menang —
      // identik dengan semantik indexWhere() yang hanya menemukan first-match.
      // Gunakan path mentah (tanpa prefix 'file://') karena
      // Media.normalizeURI() selalu strip scheme file:// sebelum menyimpan
      // ke field .uri — jadi state.medias[i].uri == song.path, bukan
      // 'file://' + song.path.
      map.putIfAbsent(songs[i].path, () => i);
    }
    _uriToQueueIndex = map;
  }

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

    // Saat shuffle aktif, mpv memiliki urutan native-nya sendiri yang berbeda
    // dari `_queue`. Resolve "lagu berikutnya" dari posisi native mpv supaya
    // UI menampilkan lagu yang benar-benar akan diputar setelah ini.
    if (_shuffleEnabled) {
      final p = _player;
      if (p != null) {
        final nativeMedias = p.state.playlist.medias;
        // Cari posisi lagu saat ini di urutan native mpv via URI.
        // nativeMedias bisa berisi Media baru (tanpa extras) setelah
        // setShuffle() — URI adalah satu-satunya kunci yang reliabel.
        final currentUri = _queue[current].path;
        final nativeIdx  = nativeMedias.indexWhere((m) => m.uri == currentUri);
        if (nativeIdx >= 0) {
          final nextNativeIdx = nativeIdx + 1;
          if (nextNativeIdx < nativeMedias.length) {
            // Ada lagu berikutnya di urutan shuffle native.
            // Gunakan _uriToQueueIndex untuk O(1) reverse-lookup ke _queue.
            final nextQueueIdx =
                _uriToQueueIndex[nativeMedias[nextNativeIdx].uri] ?? -1;
            if (nextQueueIdx >= 0) return nextQueueIdx;
          } else if (_repeatMode == 'all' && nativeMedias.isNotEmpty) {
            // Akhir playlist shuffle → wrap ke native index 0.
            final nextQueueIdx =
                _uriToQueueIndex[nativeMedias[0].uri] ?? -1;
            if (nextQueueIdx >= 0) return nextQueueIdx;
          }
          return -1; // Akhir shuffle tanpa repeat — tidak ada lagu berikutnya.
        }
      }
    }

    if (current < len - 1) return current + 1;
    if (_repeatMode == 'all') return 0;
    return -1;
  }
}
