import '../contracts/native_module.dart';
import '../models/native_module_status.dart';

/// Stub bridge for a future FFmpeg-backed decoder module.
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
/// ## Current state (Phase 2.5)
///
/// This is a **pure stub** — FFmpeg is not bundled.
/// No native binaries, no JNI code, no `mobile_ffmpeg` or
/// `ffmpeg_kit_flutter` dependency exists.
/// Compile-time clean; all methods are safe no-ops.
///
/// ## Integration plan (future)
///
/// 1. Add FFmpeg dependency (e.g. `ffmpeg_kit_flutter_audio` or a custom
///    build via `android/app/src/main/cpp/ffmpeg/`).
/// 2. Expose MethodChannel `musicplayer/ffmpeg_decoder` in MainActivity.kt.
/// 3. Replace stub bodies with channel / FFI calls.
/// 4. Wire `canDecodeFormat()` into `MediaStoreService` format probing.
/// 5. Register FFmpeg-backed renderers in `Media3PlaybackService.kt`
///    `RenderersFactory`.
///
/// ## Extension points
///
/// ```
/// // Runtime format probe (future)
/// Future<bool> canDecodeFormat(String mimeType) → channel call
///
/// // Decoder factory registration (future)
/// Future<void> registerDecoderFactory(String mimeType, ...) → channel call
///
/// // ReplayGain / loudness scan via FFmpeg (future)
/// Future<LoudnessData> scanLoudness(String filePath) → channel call
/// ```
class FfmpegDecoderBridge implements NativeModule {
  FfmpegDecoderBridge._();

  static final FfmpegDecoderBridge instance = FfmpegDecoderBridge._();

  NativeModuleStatus _status = NativeModuleStatus.uninitialized;

  // ── NativeModule contract ─────────────────────────────────────────────────

  @override
  String get moduleId => 'ffmpeg_decoder';

  @override
  String get displayName => 'FFmpeg Decoder';

  @override
  bool get isAvailable => _status == NativeModuleStatus.available;

  @override
  Future<void> initialize() async {
    if (_status != NativeModuleStatus.uninitialized) return;

    // TODO(phase-ffmpeg): Open MethodChannel 'musicplayer/ffmpeg_decoder'.
    // TODO(phase-ffmpeg): Query FFmpeg version string from native side.
    // TODO(phase-ffmpeg): Build supported-format map from codec registry.

    // Stub: FFmpeg is not bundled yet.
    _status = NativeModuleStatus.unavailable;
  }

  @override
  Future<void> dispose() async {
    if (_status == NativeModuleStatus.disposed) return;

    // TODO(phase-ffmpeg): Release native FFmpeg context.

    _status = NativeModuleStatus.disposed;
  }

  @override
  Future<List<NativeCapability>> queryCapabilities() async {
    // Stub — format support unknown until FFmpeg is actually linked.
    return const [
      NativeCapability(key: 'decoder.flac_hires', supported: false),
      NativeCapability(key: 'decoder.dsd',        supported: false),
      NativeCapability(key: 'decoder.ape',         supported: false),
      NativeCapability(key: 'decoder.wavpack',     supported: false),
      NativeCapability(key: 'decoder.opus',        supported: false),
      NativeCapability(key: 'scan.replaygain',     supported: false),
      NativeCapability(key: 'scan.loudness_ebur128',supported: false),
    ];
  }

  // ── Extension points (future decoder API surface) ─────────────────────────

  /// Future: check if FFmpeg can decode a given MIME type on this device.
  /// Returns `false` until FFmpeg is integrated.
  Future<bool> canDecodeFormat(String mimeType) async {
    // TODO(phase-ffmpeg): channel.invokeMethod('canDecodeFormat', {'mime': mimeType});
    return false;
  }

  /// Future: register a decoder factory for a specific MIME type so that
  /// Media3 `RenderersFactory` can pick it up.
  Future<void> registerDecoderFactory(String mimeType) async {
    // TODO(phase-ffmpeg): channel.invokeMethod('registerDecoderFactory', {'mime': mimeType});
  }

  /// Future: full-file loudness scan (EBU R128 / ReplayGain via FFmpeg).
  Future<Map<String, dynamic>?> scanLoudness(String filePath) async {
    // TODO(phase-ffmpeg): channel.invokeMethod('scanLoudness', {'path': filePath});
    return null;
  }
}
