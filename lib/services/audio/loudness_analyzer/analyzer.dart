part of '../loudness_analyzer.dart';

/// Analyzes audio track loudness using LUFS (primary) or RMS (fallback).
///
/// Analysis pipeline:
///   1. Check [LoudnessCache] – return immediately if cached.
///   2. Android: invoke native `analyzeLoudness` via MethodChannel
///      (MediaCodec PCM decode → K-weighted LUFS + RMS + true peak).
///   3. Non-Android WAV: pure-Dart PCM parsing (wav_parser.dart).
///   4. If all fail: return null (playback continues without normalisation).
class LoudnessAnalyzer {
  LoudnessAnalyzer._();

  static const MethodChannel _channel = MethodChannel('musicplayer/loudness');

  // ── Public API ────────────────────────────────────────────────────────────

  static Future<LoudnessResult?> analyze(String filePath) async {
    if (filePath.isEmpty) return null;

    try {
      final cached = await LoudnessCache.get(filePath);
      if (cached != null) return LoudnessResult.fromJson(cached);
    } catch (_) {}

    LoudnessResult? result;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      result = await _analyzeNative(filePath);
    }

    if (result == null && !kIsWeb) {
      result = await _analyzeWavDart(filePath);
    }

    if (result != null) {
      try { await LoudnessCache.put(filePath, result.toJson()); } catch (_) {}
      LogService.log('LoudnessAnalyzer', result.toString());
    }
    return result;
  }

  static void analyzeInBackground(List<String> paths) {
    for (final p in paths) {
      analyze(p).catchError((_) => null);
    }
  }

  // ── Native (Android MediaCodec) ───────────────────────────────────────────

  static Future<LoudnessResult?> _analyzeNative(String filePath) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'analyzeLoudness', {'path': filePath},
      );
      if (raw == null) return null;

      final lufs      = (raw['lufs']      as num?)?.toDouble();
      final rms       = (raw['rms']       as num?)?.toDouble();
      final truePeak  = (raw['truePeak']  as num?)?.toDouble();
      final estimated = raw['isEstimated'] as bool? ?? false;

      if (lufs == null || rms == null || truePeak == null) return null;

      return LoudnessResult(
        lufs:            lufs,
        rms:             rms,
        truePeak:        truePeak,
        isLufsEstimated: estimated,
        source:          estimated ? 'rms_native' : 'lufs_native',
      );
    } catch (e) {
      LogService.warn('LoudnessAnalyzer', 'Native failed for $filePath: $e');
      return null;
    }
  }

  // ── Pure-Dart WAV fallback (implementation in wav_parser.dart) ────────────

  static Future<LoudnessResult?> _analyzeWavDart(String filePath) async {
    try {
      final lower = filePath.toLowerCase();
      if (!lower.endsWith('.wav') && !lower.endsWith('.wave')) return null;

      final result = await compute(_wavParseIsolate, filePath);
      return result;
    } catch (e) {
      LogService.warn('LoudnessAnalyzer', 'WAV Dart failed: $e');
      return null;
    }
  }
}
