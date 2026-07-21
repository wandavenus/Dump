part of '../playback_manager.dart';

// ── DSP effects (Media3 / ExoPlayer) ─────────────────────────────────────

  static Future<void> setBassBoost(int strength) =>
      Media3PlaybackBridge.setBassBoostStrength(strength);
  static Future<void> setBassBoostEnabled(bool e) =>
      Media3PlaybackBridge.setBassBoostEnabled(e);
  static Future<void> setEqualizerEnabled(bool e) =>
      Media3PlaybackBridge.setEqualizerEnabled(e);
  static Future<void> setEqualizerBandGain(int b, double g) =>
      Media3PlaybackBridge.setEqualizerBandGain(b, g);
  static Future<void> setLoudnessEnabled(bool e) =>
      Media3PlaybackBridge.setLoudnessEnabled(e);
  static Future<void> setLoudnessTargetGain(double g) =>
      Media3PlaybackBridge.setLoudnessTargetGain(g);
  static Future<void> setCrossfadeDuration(double s) =>
      Media3PlaybackBridge.setCrossfadeDuration(s);

  /// Bit-Perfect Mode: switches native playback onto (or off) a dedicated
  /// processing-free ExoPlayer. See Media3PlaybackBridge.setBitPerfectMode.
  static Future<void> setBitPerfectMode(bool enabled) =>
      Media3PlaybackBridge.setBitPerfectMode(enabled);

  /// Cold-start race fix — see `ServiceReadyGate` (native) and
  /// `Media3PlaybackBridge.serviceReadyStream` (bridge).
  ///
  /// Resolves once `Media3PlaybackService.onCreate()` has fully finished
  /// wiring (player, session, managers, TransportCommands, queue restore).
  /// On a fresh install the service does not exist until the user's first
  /// "play"/"setQueue" call creates it — anything that must configure the
  /// engine before that (persisted bass boost / EQ / crossfade / skip-silence
  /// / stereo-widening settings) should await this first instead of firing
  /// immediately and racing `instance` being null.
  static Future<void> waitForServiceReady() =>
      Media3PlaybackBridge.serviceReadyStream.first;

  static Future<EqualizerParameters?> getEqualizerParameters() async {
    try {
      final raw = await Media3PlaybackBridge.getEqualizerParameters();
      return EqualizerParameters(
        minDecibels: raw.minDecibels,
        maxDecibels: raw.maxDecibels,
        bandCount: raw.bands.length,
        centerFrequenciesHz:
            raw.bands.map((b) => b.centerFrequencyHz).toList(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getEffectSupport() =>
      Media3PlaybackBridge.getEffectSupport();

  // ── Capabilities ──────────────────────────────────────────────────────────

  static Future<void> setStereoWidening({
    required bool enabled,
    required double strength,
  }) =>
      Media3PlaybackBridge.setStereoWidening(
        enabled: enabled,
        strength: strength,
      );

  static Future<Map<String, dynamic>?> getPlaybackStats() =>
      Media3PlaybackBridge.getPlaybackStats();

  // ── Audio format ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getAudioFormat() =>
      Media3PlaybackBridge.getAudioFormat();

  // ── Sleep timer ───────────────────────────────────────────────────────────

  static Future<void> setSleepTimer(int ms) =>
      Media3PlaybackBridge.setSleepTimer(ms);
  static Future<void> setSleepTimerEndOfSong() =>
      Media3PlaybackBridge.setSleepTimerEndOfSong();
  static Future<void> cancelSleepTimer() =>
      Media3PlaybackBridge.cancelSleepTimer();

  // ── State snapshot ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getPlaybackSnapshot() =>
      Media3PlaybackBridge.getPlaybackSnapshot();

  // ── Native module access (FFI runtime) ───────────────────────────────────
  //
  // UI and services must never import `lib/services/native/bridges/` or
  // `package:native_audio_runtime` directly — this is the single sanctioned
  // entry point per NATIVE_BRIDGES.md.

  /// Snapshot of every registered native module (id, name, availability).
  static List<NativeModule> get nativeModules => NativeModuleRegistry.all;

  /// Aggregate capability report across all registered native modules.
  static Future<Map<String, List<NativeCapability>>>
      queryNativeCapabilities() => NativeModuleRegistry.queryAllCapabilities();

  // ── FFmpeg decoder (Phase 9) ──────────────────────────────────────────────
  //
  // The only sanctioned entry point for FFmpeg decoder status — see
  // FfmpegDecoderBridge's doc comment for the full architecture. This is the
  // one exception to "native access goes through PlaybackManager only" that
  // still holds: PlaybackManager talks to FfmpegDecoderBridge, never directly
  // to the ffmpeg_decoder MethodChannel/EventChannel.

  /// Capability snapshot detected at startup: whether the bundled FFmpeg
  /// build is available, its version, and which Phase 9 target codecs
  /// (ALAC/DTS/TrueHD/Vorbis/Opus) it actually supports.
  static FfmpegDecoderCapabilities get ffmpegDecoderCapabilities =>
      FfmpegDecoderBridge.instance.capabilities;

  /// Per-track decoder selection diagnostics for the active player — fires
  /// for every decoder init, whether it landed on a built-in MediaCodec or
  /// the FFmpeg fallback, each with a human-readable [FfmpegDecoderInfo.reason].
  static Stream<FfmpegDecoderInfo> get ffmpegDecoderInfoStream =>
      FfmpegDecoderBridge.instance.decoderInfoStream;
