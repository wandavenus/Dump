import 'dart:async';

import 'package:flutter/services.dart';

import '../contracts/native_module.dart';
import '../models/native_module_status.dart';

/// Capability snapshot reported by the native FFmpeg decoder module.
///
/// [available] reflects `FfmpegLibrary.isAvailable()` on the Kotlin side,
/// which is only true when the `media3-decoder-ffmpeg` module was vendored
/// AND its native `.so` loaded successfully at runtime. [moduleLinked]
/// distinguishes "class not found" (module not vendored at all) from
/// "class found but native lib failed to load" — useful for diagnostics,
/// but callers almost always just want [available].
class FfmpegDecoderCapabilities {
  final bool available;
  final bool moduleLinked;
  final String? version;

  /// Human-readable codec names (e.g. `'ALAC'`, `'DTS'`) the bundled FFmpeg
  /// build actually supports, as probed live via `FfmpegLibrary.supportsFormat`.
  /// Empty when [available] is false.
  final List<String> supportedCodecs;

  const FfmpegDecoderCapabilities({
    required this.available,
    required this.moduleLinked,
    required this.version,
    required this.supportedCodecs,
  });

  static const unavailable = FfmpegDecoderCapabilities(
    available: false,
    moduleLinked: false,
    version: null,
    supportedCodecs: [],
  );

  factory FfmpegDecoderCapabilities.fromMap(Map<dynamic, dynamic> map) {
    return FfmpegDecoderCapabilities(
      available: map['available'] as bool? ?? false,
      moduleLinked: map['moduleLinked'] as bool? ?? false,
      version: map['version'] as String?,
      supportedCodecs: (map['supportedCodecs'] as List?)?.cast<String>() ?? const [],
    );
  }

  @override
  String toString() => 'FfmpegDecoderCapabilities(available=$available, '
      'moduleLinked=$moduleLinked, version=$version, codecs=$supportedCodecs)';
}

/// Per-track decoder selection diagnostics, emitted every time ExoPlayer
/// initializes an audio decoder for the currently active player.
class FfmpegDecoderInfo {
  /// Raw decoder name as reported by ExoPlayer, e.g. `'OMX.google.raw.decoder'`
  /// or `'ffmpeg6.0-alac'`.
  final String decoderName;

  /// Sample MIME type being decoded, e.g. `'audio/alac'`. May be null if the
  /// input format event hadn't fired yet when the decoder initialized.
  final String? mimeType;

  /// True when [decoderName] identifies the bundled FFmpeg software decoder
  /// rather than an on-device MediaCodec.
  final bool isFfmpegDecoder;

  /// How long decoder initialization took, in milliseconds.
  final int initializationDurationMs;

  /// Human-readable explanation of why this decoder was selected — surfaced
  /// in debug UIs so a fallback to FFmpeg is never a silent, unexplained event.
  final String reason;

  const FfmpegDecoderInfo({
    required this.decoderName,
    required this.mimeType,
    required this.isFfmpegDecoder,
    required this.initializationDurationMs,
    required this.reason,
  });

  factory FfmpegDecoderInfo.fromMap(Map<dynamic, dynamic> map) {
    return FfmpegDecoderInfo(
      decoderName: map['decoderName'] as String? ?? 'unknown',
      mimeType: map['mimeType'] as String?,
      isFfmpegDecoder: map['isFfmpegDecoder'] as bool? ?? false,
      initializationDurationMs: (map['initializationDurationMs'] as num?)?.toInt() ?? 0,
      reason: map['reason'] as String? ?? '',
    );
  }

  @override
  String toString() => 'FfmpegDecoderInfo($decoderName, mime=$mimeType, '
      'isFfmpeg=$isFfmpegDecoder, ${initializationDurationMs}ms)';
}

/// Dedicated abstraction over the official Media3 FFmpeg decoder extension.
///
/// ## Phase 9 architecture
///
/// Decoding itself never touches Dart or the `native_audio_runtime` FFI
/// package — it runs entirely inside ExoPlayer via Google's own
/// `androidx.media3:media3-decoder-ffmpeg` extension (`FfmpegAudioRenderer`),
/// registered automatically by `DefaultRenderersFactory`'s
/// `EXTENSION_RENDERER_MODE_ON` + `setEnableDecoderFallback(true)` (already
/// configured in `Media3PlaybackService.kt`). PCM produced by that renderer
/// flows through the exact same `NativeDspAudioProcessor` chain as PCM from
/// any built-in decoder — the DSP pipeline (`native_audio_runtime`) requires
/// no changes and is untouched by this module.
///
/// This class exists so that **all** Dart-side code — `PlaybackManager`
/// included — talks to a single, stable API for FFmpeg decoder status,
/// regardless of how that status is actually sourced on the native side.
/// Internally it owns a small dedicated MethodChannel/EventChannel pair
/// (`musicplayer/ffmpeg_decoder`, `musicplayer/ffmpeg_decoder_events`) to
/// query the Media3 FFmpeg extension via Kotlin reflection
/// (`FfmpegCapabilityProbe.kt`) — nobody else should reach for those channels
/// directly.
///
/// ## Scope (Phase 9, "official path only")
///
/// Covers formats Media3 can already demux but has no on-device MediaCodec
/// decoder for: ALAC, DTS/DTS-HD, TrueHD, Vorbis, Opus edge cases. APE,
/// WavPack, TAK, and Monkey's Audio are explicitly out of scope — Media3 has
/// no container `Extractor` for them at all, which is a categorically bigger
/// (and unproven) undertaking. Tracked as a separate follow-up.
///
/// ## Build-time state
///
/// The native `media3-decoder-ffmpeg` module is not vendored in this
/// environment (no Android NDK available to build it) and is not on Maven
/// Central. Until someone runs the build documented in
/// `docs/PHASE_9_FFMPEG_DECODER_INTEGRATION.md` on a machine with the NDK and
/// flips `ffmpegDecoderEnabled=true` in `local.properties`, [isAvailable]
/// will always be `false` — that is the correct, fail-open answer, not a bug.
class FfmpegDecoderBridge implements NativeModule {
  FfmpegDecoderBridge._();

  static final FfmpegDecoderBridge instance = FfmpegDecoderBridge._();

  static const String _moduleId = 'ffmpeg_decoder';

  static const MethodChannel _channel = MethodChannel('musicplayer/ffmpeg_decoder');
  static const EventChannel _decoderInfoEvents = EventChannel('musicplayer/ffmpeg_decoder_events');

  NativeModuleStatus _status = NativeModuleStatus.uninitialized;
  FfmpegDecoderCapabilities _capabilities = FfmpegDecoderCapabilities.unavailable;

  StreamSubscription<dynamic>? _decoderInfoSub;
  final _decoderInfoCtrl = StreamController<FfmpegDecoderInfo>.broadcast();

  /// Per-track decoder selection diagnostics for the active player. Emits
  /// even when [isAvailable] is false — the built-in-decoder case is a valid,
  /// useful diagnostic event too (`isFfmpegDecoder == false`).
  Stream<FfmpegDecoderInfo> get decoderInfoStream => _decoderInfoCtrl.stream;

  /// Latest capability snapshot from startup detection. See [initialize].
  FfmpegDecoderCapabilities get capabilities => _capabilities;

  // ── NativeModule contract ─────────────────────────────────────────────────

  @override
  String get moduleId => _moduleId;

  @override
  String get displayName => 'FFmpeg Decoder';

  @override
  bool get isAvailable => _capabilities.available;

  @override
  Future<void> initialize() async {
    if (_status != NativeModuleStatus.uninitialized) return;

    _decoderInfoSub = _decoderInfoEvents.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          _decoderInfoCtrl.add(FfmpegDecoderInfo.fromMap(event));
        }
      },
      onError: (_) {
        // Native side never emits an error payload today; guard defensively
        // so a future change there can't crash this bridge's subscription.
      },
    );

    try {
      // Automatic capability detection at startup — availability, native
      // library version if loaded, and which of the Phase 9 target codecs
      // the bundled FFmpeg build actually supports.
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('queryStatus');
      _capabilities = result != null
          ? FfmpegDecoderCapabilities.fromMap(result)
          : FfmpegDecoderCapabilities.unavailable;
      _status = _capabilities.available
          ? NativeModuleStatus.available
          : NativeModuleStatus.unavailable;
    } catch (_) {
      // Channel missing/failed (e.g. platform not Android) — fail open.
      _capabilities = FfmpegDecoderCapabilities.unavailable;
      _status = NativeModuleStatus.unavailable;
    }
  }

  @override
  Future<void> dispose() async {
    if (_status == NativeModuleStatus.disposed) return;
    await _decoderInfoSub?.cancel();
    _decoderInfoSub = null;
    _status = NativeModuleStatus.disposed;
  }

  @override
  Future<List<NativeCapability>> queryCapabilities() async {
    const targetCodecs = ['ALAC', 'DTS', 'DTS-HD', 'TrueHD', 'Vorbis', 'Opus'];
    return targetCodecs
        .map((codec) => NativeCapability(
              key: 'decoder.${codec.toLowerCase().replaceAll('-', '_')}',
              supported: _capabilities.supportedCodecs.contains(codec),
              version: _capabilities.available ? _capabilities.version : null,
            ))
        .toList();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Whether the bundled FFmpeg build reports support for [mimeType]
  /// (e.g. `'audio/alac'`). Checks the codec name mapping used by
  /// `FfmpegCapabilityProbe`; unknown MIME types always return false.
  bool canDecodeFormat(String mimeType) {
    if (!isAvailable) return false;
    final codec = _mimeToCodecLabel[mimeType];
    return codec != null && _capabilities.supportedCodecs.contains(codec);
  }

  static const Map<String, String> _mimeToCodecLabel = {
    'audio/alac': 'ALAC',
    'audio/vnd.dts': 'DTS',
    'audio/vnd.dts.hd': 'DTS-HD',
    'audio/true-hd': 'TrueHD',
    'audio/vorbis': 'Vorbis',
    'audio/opus': 'Opus',
  };
}
