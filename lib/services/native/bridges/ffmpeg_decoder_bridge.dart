import 'package:native_audio_runtime/native_audio_runtime.dart';

import '../contracts/native_module.dart';
import '../models/native_module_status.dart';

/// FFI bridge for a future FFmpeg-backed decoder module.
///
/// ## Intended future responsibilities
///
/// When implemented, this bridge will:
///   - Provide decoding for formats not natively supported by ExoPlayer
///     (e.g. FLAC 32-bit, DSD, Opus in unusual containers, APE, WavPack).
///   - Report per-format decoder availability at runtime.
///   - Allow registration of format-specific decoder factories that
///     ExoPlayer's `RenderersFactory` can delegate to.
///
/// ## Current state (Phase 3)
///
/// FFmpeg is still not bundled — no native binaries, no `ffmpeg_kit_flutter`
/// dependency. What changed from Phase 2.5: this bridge now talks to the
/// real shared native runtime (`package:native_audio_runtime`) for lifecycle
/// and capability reporting, instead of being a pure Dart stub. All decoder
/// capabilities remain `supported: false` until FFmpeg is actually linked.
/// See `NATIVE_RUNTIME.md` for the architecture and unverified assumptions
/// (no Android NDK available in this environment to cross-compile against).
///
/// ## Integration plan (future)
///
/// 1. Add FFmpeg dependency (e.g. `ffmpeg_kit_flutter_audio`) OR a custom
///    CMake build of FFmpeg wired into `native_audio_runtime`'s build hook.
/// 2. Extend `NativeAudioRuntime` with decoder-specific FFI calls.
/// 3. Wire `canDecodeFormat()` into `MediaStoreService` format probing.
/// 4. Register FFmpeg-backed renderers in `Media3PlaybackService.kt`
///    `RenderersFactory` — Kotlin stays Android-framework-only; FFmpeg
///    itself is never routed through Kotlin per NATIVE_RUNTIME.md.
///
/// ## Extension points
///
/// ```
/// // Runtime format probe (future)
/// Future<bool> canDecodeFormat(String mimeType) → FFI call
///
/// // Decoder factory registration (future)
/// Future<void> registerDecoderFactory(String mimeType, ...) → FFI call
///
/// // ReplayGain / loudness scan via FFmpeg (future)
/// Future<LoudnessData> scanLoudness(String filePath) → FFI call
/// ```
class FfmpegDecoderBridge implements NativeModule {
  FfmpegDecoderBridge._();

  static final FfmpegDecoderBridge instance = FfmpegDecoderBridge._();

  static const String _moduleId = 'ffmpeg_decoder';

  NativeModuleStatus _status = NativeModuleStatus.uninitialized;

  // ── NativeModule contract ─────────────────────────────────────────────────

  @override
  String get moduleId => _moduleId;

  @override
  String get displayName => 'FFmpeg Decoder';

  @override
  bool get isAvailable => _status == NativeModuleStatus.available;

  @override
  Future<void> initialize() async {
    if (_status != NativeModuleStatus.uninitialized) return;

    try {
      // Shared singleton — idempotent even if NativeDspBridge already
      // initialized it first (registration order comes from PlaybackManager).
      await NativeAudioRuntime.instance.initialize();

      if (!NativeAudioRuntime.instance.isAvailable) {
        _status = NativeModuleStatus.unavailable;
        return;
      }

      final regStatus =
          NativeAudioRuntime.instance.registerModule(_moduleId);
      switch (regStatus) {
        case NativeRuntimeStatus.ok:
        case NativeRuntimeStatus.duplicateModule:
          _status = NativeModuleStatus.available;
        default:
          _status = NativeModuleStatus.unavailable;
      }
    } catch (_) {
      _status = NativeModuleStatus.error;
    }
  }

  @override
  Future<void> dispose() async {
    if (_status == NativeModuleStatus.disposed) return;

    // Shared runtime lifecycle owned collectively — see NativeDspBridge for
    // why this does not call NativeAudioRuntime.instance.dispose() itself.
    _status = NativeModuleStatus.disposed;
  }

  @override
  Future<List<NativeCapability>> queryCapabilities() async {
    if (!isAvailable) {
      return const [
        NativeCapability(key: 'decoder.flac_hires', supported: false),
        NativeCapability(key: 'decoder.dsd', supported: false),
        NativeCapability(key: 'decoder.ape', supported: false),
        NativeCapability(key: 'decoder.wavpack', supported: false),
        NativeCapability(key: 'decoder.opus', supported: false),
        NativeCapability(key: 'scan.replaygain', supported: false),
        NativeCapability(key: 'scan.loudness_ebur128', supported: false),
      ];
    }

    return NativeAudioRuntime.instance.capabilities
        .map((c) => NativeCapability(key: c.key, supported: c.supported))
        .toList();
  }

  // ── Extension points (future decoder API surface) ─────────────────────────

  /// Future: check if FFmpeg can decode a given MIME type on this device.
  /// Returns `false` until FFmpeg is integrated.
  Future<bool> canDecodeFormat(String mimeType) async {
    // TODO(phase-ffmpeg): route through a dedicated FFI call once FFmpeg exists.
    return false;
  }

  /// Future: register a decoder factory for a specific MIME type so that
  /// Media3 `RenderersFactory` can pick it up.
  Future<void> registerDecoderFactory(String mimeType) async {
    // TODO(phase-ffmpeg): route through a dedicated FFI call once FFmpeg exists.
  }

  /// Future: full-file loudness scan (EBU R128 / ReplayGain via FFmpeg).
  Future<Map<String, dynamic>?> scanLoudness(String filePath) async {
    // TODO(phase-ffmpeg): route through a dedicated FFI call once FFmpeg exists.
    return null;
  }
}
