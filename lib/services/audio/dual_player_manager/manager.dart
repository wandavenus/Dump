part of '../dual_player_manager.dart';

/// Manages two [AudioPlayer] instances — a primary (currently playing)
/// and a secondary (preloading next track).
///
/// ## Circular-dependency contract
/// [DualPlayerManager] does NOT import [AudioEngine].
/// Instead it exposes three callbacks that [AudioEngine] and
/// [AudioService] register before [initialize] is called:
///
/// * [onPrimaryChanged]      — fired when the primary player changes
///                              (init + every promote).  AudioEngine uses
///                              this to update its player references and
///                              re-subscribe to the Android session stream.
/// * [onSecondarySessionId]  — fired with each secondary player's audio
///                              session ID so AudioEngine can pre-attach
///                              native effects before the track becomes
///                              primary.
/// * [onPromoted]            — fired after every promote so AudioService
///                              can advance the queue index.
class DualPlayerManager {
  DualPlayerManager._();

  // ── Callbacks ──────────────────────────────────────────────────────────────

  /// Registered by [AudioEngine.initialize].
  /// Called whenever the PRIMARY player reference changes.
  static void Function()? onPrimaryChanged;

  /// Registered by [AudioEngine.initialize].
  /// Called with each new secondary player's Android audio session ID.
  static void Function(int sessionId)? onSecondarySessionId;

  /// Registered by [AudioService.initialize].
  /// Called after promote so [AudioService._afterPromotion] can run.
  ///
  /// [bool] is `true` when called from a crossfade (secondary was already
  /// playing), `false` for a gapless hand-off (secondary was preloaded but
  /// paused → caller must play).
  static void Function(bool fromCrossfade)? onPromoted;

  // ── Player state ───────────────────────────────────────────────────────────

  static AudioPlayer? _primary;
  static AudioPlayer? _secondary;

  // DSP objects for primary (exposed for AudioEngine delegates).
  static AndroidEqualizer?        _primaryEq;
  static AndroidLoudnessEnhancer? _primaryLe;

  // DSP objects for secondary (mirrored into primary on promote).
  static AndroidEqualizer?        _secondaryEq;
  static AndroidLoudnessEnhancer? _secondaryLe;

  static bool _initialized = false;

  /// The song currently loaded into the secondary player, or null if the
  /// secondary is empty / not yet loaded.  Used by [AudioService.skipNext] to
  /// detect whether the preloaded track matches the intended next song so it
  /// can promote instead of reloading.
  static LocalSong? _preloadedSong;

  // ── Getters ────────────────────────────────────────────────────────────────

  static AudioPlayer get primaryPlayer {
    assert(_initialized, 'DualPlayerManager not initialized');
    return _primary!;
  }

  static AudioPlayer? get secondaryPlayer => _secondary;

  /// The song currently buffered in the secondary player, or null.
  static LocalSong? get preloadedSong => _preloadedSong;

  static AndroidEqualizer?        get primaryEqualizer => _primaryEq;
  static AndroidLoudnessEnhancer? get primaryLoudness  => _primaryLe;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // ── Initialization ─────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_initialized) return;

    final (p, eq, le) = _buildPlayer();
    _primary  = p;
    _primaryEq = eq;
    _primaryLe = le;

    _initialized = true;

    // Notify AudioEngine: set player reference + subscribe to session ID.
    onPrimaryChanged?.call();

    LogService.log('DualPlayer', 'Primary player created');

    // Secondary player created in background — non-blocking.
    unawaited(_initSecondary());
  }

  static Future<void> _initSecondary() async {
    try {
      final (p, eq, le) = _buildPlayer();
      _secondary  = p;
      _secondaryEq = eq;
      _secondaryLe = le;
      await _secondary!.setVolume(0.0);

      // Subscribe to secondary's session so AudioEngine can pre-attach
      // native effects before promotion.
      if (isAndroid) {
        _secondary!.androidAudioSessionIdStream
            .where((id) => id != null)
            .distinct()
            .listen((id) => onSecondarySessionId?.call(id!));
      }

      LogService.log('DualPlayer', 'Secondary player created');
    } catch (e) {
      LogService.warn('DualPlayer', 'Secondary init failed: $e');
    }
  }

  // ── Player factory ──────────────────────────────────────────────────────────

  static (AudioPlayer, AndroidEqualizer?, AndroidLoudnessEnhancer?) _buildPlayer() {
    if (isAndroid) {
      final eq = AndroidEqualizer();
      final le = AndroidLoudnessEnhancer();
      return (
        AudioPlayer(
          audioPipeline: AudioPipeline(androidAudioEffects: [le, eq]),
        ),
        eq,
        le,
      );
    }
    return (AudioPlayer(), null, null);
  }

  // ── Preload ─────────────────────────────────────────────────────────────────

  /// Loads [song] into the secondary player without starting playback.
  ///
  /// Uses an **untagged** [AudioSource] (no MediaItem) so the lock-screen
  /// notification is not disturbed during preloading.
  static Future<void> preloadTrack(LocalSong song) async {
    // Skip if the secondary already has this exact song buffered.
    if (_preloadedSong?.id == song.id && _secondary != null) {
      LogService.verbose('DualPlayer', 'Already preloaded: "${song.title}"');
      return;
    }
    if (_secondary == null) await _initSecondary();
    final sec = _secondary;
    if (sec == null) return;
    try {
      await sec.setAudioSource(_preloadSource(song));
      _preloadedSong = song;
      LogService.verbose('DualPlayer', 'Preloaded: "${song.title}"');
    } catch (e) {
      _preloadedSong = null;
      LogService.warn('DualPlayer', 'Preload failed: $e');
    }
  }

  /// Stops any pending preload (called when user skips manually or starts a
  /// fresh playlist).
  static Future<void> cancelPreload() async {
    _preloadedSong = null;
    try { await _secondary?.stop(); } catch (_) {}
  }

  // ── Promote ─────────────────────────────────────────────────────────────────

  /// Atomically swaps secondary → primary.
  ///
  /// [fromCrossfade] = true  → secondary is already playing.
  /// [fromCrossfade] = false → secondary was preloaded but paused;
  ///                           [AudioService] must call play() after this.
  static Future<void> promote({bool fromCrossfade = false}) async {
    final sec = _secondary;
    if (sec == null) {
      LogService.warn('DualPlayer', 'promote() called with no secondary');
      return;
    }

    final oldPrimary = _primary!;

    // ── Swap ─────────────────────────────────────────────────────────────────
    _primary    = sec;
    _primaryEq  = _secondaryEq;
    _primaryLe  = _secondaryLe;
    _secondary  = null;
    _secondaryEq = null;
    _secondaryLe = null;
    _preloadedSong = null; // secondary is now primary; no preloaded song yet

    // Restore new primary to full volume (crossfade may have left it at ~0).
    try { await _primary!.setVolume(1.0); } catch (_) {}

    // ── Notify AudioEngine first (update player reference + session sub) ──────
    onPrimaryChanged?.call();

    // ── Notify AudioService (advance queue, resubscribe streams) ─────────────
    onPromoted?.call(fromCrossfade);

    // ── Async cleanup (no await) ──────────────────────────────────────────────
    unawaited(_disposePlayer(oldPrimary));
    unawaited(_initSecondary());

    LogService.log(
      'DualPlayer',
      'Promoted secondary → primary '
      '(${fromCrossfade ? "crossfade" : "gapless"})',
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Future<void> _disposePlayer(AudioPlayer player) async {
    try {
      await player.stop();
      await player.dispose();
      LogService.verbose('DualPlayer', 'Player disposed');
    } catch (e) {
      LogService.warn('DualPlayer', 'Dispose error: $e');
    }
  }

  static AudioSource _preloadSource(LocalSong song) {
    if (kIsWeb) return AudioSource.uri(Uri.parse(song.path));
    // No MediaItem tag — avoids disturbing the lock-screen notification.
    return AudioSource.file(song.path);
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  static Future<void> dispose() async {
    if (_primary  != null) await _disposePlayer(_primary!);
    if (_secondary != null) await _disposePlayer(_secondary!);
    _primary    = null;
    _secondary  = null;
    _primaryEq  = null;
    _primaryLe  = null;
    _secondaryEq = null;
    _secondaryLe = null;
    _preloadedSong = null;
    _initialized = false;
    onPrimaryChanged     = null;
    onSecondarySessionId = null;
    onPromoted           = null;
    LogService.log('DualPlayer', 'Disposed (primary + secondary)');
  }
}
