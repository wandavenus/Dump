import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// Background audio handler for the [audio_service] package.
///
/// This is the single object that owns the OS media session (Android
/// notification, lockscreen controls, headset buttons).  It is
/// intentionally decoupled from our custom [AudioService] class:
///
/// * Incoming OS events (play, pause, seek …) are forwarded via the
///   static callback fields that [AudioService.initialize] registers.
/// * Outgoing updates ([updateNowPlaying], [pushPlaybackState]) are
///   called from [AudioService] on the [instance] reference.
///
/// This keeps the dependency graph one-directional:
///   AudioService → BackgroundAudioHandler (never the reverse).
class BackgroundAudioHandler extends BaseAudioHandler with SeekHandler {
  // ── Singleton reference ───────────────────────────────────────────────────

  static BackgroundAudioHandler? _instance;

  /// Live handler set in the constructor.
  /// Null before [audio_service]'s `AudioService.init()` completes.
  static BackgroundAudioHandler? get instance => _instance;

  // ── Callbacks registered by AudioService ─────────────────────────────────

  static Future<void> Function()?          onPlayRequested;
  static Future<void> Function()?          onPauseRequested;
  static Future<void> Function()?          onSkipNextRequested;
  static Future<void> Function()?          onSkipPrevRequested;
  static Future<void> Function(Duration)?  onSeekRequested;
  static Future<void> Function()?          onStopRequested;

  /// Called when the lockscreen repeat button is tapped.
  /// AudioService cycles its own loop mode internally.
  static Future<void> Function()?          onSetRepeatRequested;

  /// Called with `true` when shuffle should be enabled, `false` when off.
  static Future<void> Function(bool)?      onSetShuffleRequested;

  // ── Construction ──────────────────────────────────────────────────────────

  BackgroundAudioHandler() {
    _instance = this;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
      ],
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  // ── Push-update API (called by AudioService) ──────────────────────────────

  /// Updates the notification with track metadata.
  ///
  /// Pass `null` for optional fields that are not available for a given song.
  void updateNowPlaying({
    required String  id,
    required String  title,
    String?          artist,
    String?          album,
    Duration?        duration,
    Uri?             artUri,
  }) {
    mediaItem.add(MediaItem(
      id:       id,
      title:    title,
      artist:   artist,
      album:    album,
      duration: duration,
      artUri:   artUri,
    ));
  }

  /// Pushes current play/pause/seek state to the notification and lockscreen.
  ///
  /// [processingState] is just_audio's [ProcessingState]; it is translated
  /// to [AudioProcessingState] internally so callers need not import
  /// [audio_service] directly.
  void pushPlaybackState({
    required bool            playing,
    required ProcessingState processingState,
    Duration                 updatePosition = Duration.zero,
    double                   speed          = 1.0,
  }) {
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions:                const {MediaAction.seek},
      androidCompactActionIndices:  const [0, 1, 2],
      processingState:              _toAudioProcessingState(processingState),
      playing:                      playing,
      updatePosition:               updatePosition,
      speed:                        speed,
    ));
  }

  // ── BaseAudioHandler overrides ────────────────────────────────────────────

  @override
  Future<void> play() async => onPlayRequested?.call();

  @override
  Future<void> pause() async => onPauseRequested?.call();

  @override
  Future<void> skipToNext() async => onSkipNextRequested?.call();

  @override
  Future<void> skipToPrevious() async => onSkipPrevRequested?.call();

  @override
  Future<void> seek(Duration position) async => onSeekRequested?.call(position);

  @override
  Future<void> stop() async => onStopRequested?.call();

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode _) async =>
      onSetRepeatRequested?.call();

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode mode) async =>
      onSetShuffleRequested?.call(mode != AudioServiceShuffleMode.none);

  // ── Internal ──────────────────────────────────────────────────────────────

  static AudioProcessingState _toAudioProcessingState(ProcessingState s) =>
      switch (s) {
        ProcessingState.idle      => AudioProcessingState.idle,
        ProcessingState.loading   => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready     => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      };
}
