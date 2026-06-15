part of '../loudness_analyzer.dart';

/// Analyzes audio track loudness using LUFS (primary) or RMS (fallback).
///
/// Analysis pipeline:
///   1. Check [LoudnessCache] – return immediately if cached.
///   2. Android: invoke native `analyzeLoudness` via MethodChannel
///      (MediaCodec PCM decode → K-weighted LUFS + RMS + true peak).
///   3. Non-Android WAV: pure-Dart PCM parsing.
///   4. If all fail: return null (playback continues without normalisation).
///
/// Results are cached by file path + last-modified timestamp so re-scans
/// only happen when a file actually changes.
class LoudnessAnalyzer {
  LoudnessAnalyzer._();

  static const MethodChannel _channel = MethodChannel('musicplayer/loudness');

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns a [LoudnessResult] for [filePath], or null if analysis fails.
  /// Safe to call from any isolate context; heavy work is off-main-thread.
  static Future<LoudnessResult?> analyze(String filePath) async {
    if (filePath.isEmpty) return null;

    // 1. Cache hit
    try {
      final cached = await LoudnessCache.get(filePath);
      if (cached != null) return LoudnessResult.fromJson(cached);
    } catch (_) {}

    LoudnessResult? result;

    // 2. Android native analysis (preferred – full LUFS via MediaCodec)
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      result = await _analyzeNative(filePath);
    }

    // 3. Pure-Dart WAV fallback
    if (result == null && !kIsWeb) {
      result = await _analyzeWavDart(filePath);
    }

    // 4. Cache & return
    if (result != null) {
      try { await LoudnessCache.put(filePath, result.toJson()); } catch (_) {}
      LogService.log('LoudnessAnalyzer', result.toString());
    }
    return result;
  }

  /// Fire-and-forget background analysis for a list of paths.
  static void analyzeInBackground(List<String> paths) {
    for (final p in paths) {
      analyze(p).catchError((_) => null);
    }
  }

  // ── Native (Android MediaCodec) ───────────────────────────────────────────

  static Future<LoudnessResult?> _analyzeNative(String filePath) async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'analyzeLoudness',
        {'path': filePath},
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

  // ── Pure-Dart WAV parser ──────────────────────────────────────────────────

  static Future<LoudnessResult?> _analyzeWavDart(String filePath) async {
    try {
      final lower = filePath.toLowerCase();
      if (!lower.endsWith('.wav') && !lower.endsWith('.wave')) return null;

      // Run in separate isolate so UI stays responsive
      final result = await compute(_parseWavIsolate, filePath);
      return result;
    } catch (e) {
      LogService.warn('LoudnessAnalyzer', 'WAV Dart failed: $e');
      return null;
    }
  }

  /// Top-level function required by [compute].
  static LoudnessResult? _parseWavIsolate(String filePath) {
    try {
      final bytes = File(filePath).readAsBytesSync();
      return _parseWav(bytes);
    } catch (_) {
      return null;
    }
  }

  static LoudnessResult? _parseWav(Uint8List bytes) {
    if (bytes.length < 44) return null;
    final data = ByteData.sublistView(bytes);

    // Verify RIFF header
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (riff != 'RIFF' || wave != 'WAVE') return null;

    // Parse fmt chunk
    int offset = 12;
    int dataOffset = -1;
    int dataSize   = -1;
    int audioFormat  = 0;
    int numChannels  = 0;
    int sampleRate   = 0;
    int bitsPerSample = 0;

    while (offset < bytes.length - 8) {
      final chunkId   = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      offset += 8;
      if (chunkId == 'fmt ') {
        audioFormat   = data.getUint16(offset,     Endian.little);
        numChannels   = data.getUint16(offset + 2, Endian.little);
        sampleRate    = data.getUint32(offset + 4, Endian.little);
        bitsPerSample = data.getUint16(offset + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = offset;
        dataSize   = chunkSize;
        break;
      }
      offset += chunkSize + (chunkSize & 1); // word-align
    }

    if (dataOffset < 0 || audioFormat != 1 || bitsPerSample != 16) return null;
    if (numChannels == 0 || sampleRate == 0) return null;

    final sampleCount = dataSize ~/ (numChannels * 2);
    if (sampleCount == 0) return null;

    // Limit analysis to first 60 s to keep it fast
    final maxSamples = math.min(sampleCount, sampleRate * 60);

    double sumSq    = 0.0;
    double maxPeak  = 0.0;

    // K-weighting biquad state (stage 1 + stage 2) per channel, left ch only
    // Coefficients for 48 kHz (close enough for typical sample rates)
    // Stage 1: pre-filter (high-shelf)
    const b1 = [1.53512485958697, -2.69169618940638, 1.19839281085285];
    const a1 = [1.0,              -1.69065929318241, 0.73248077421585];
    // Stage 2: RLB (high-pass)
    const b2 = [1.0, -2.0, 1.0];
    const a2 = [1.0, -1.99004745483398, 0.99007225036498];

    var x1_1 = 0.0, x1_2 = 0.0, y1_1 = 0.0, y1_2 = 0.0; // stage 1 state
    var x2_1 = 0.0, x2_2 = 0.0, y2_1 = 0.0, y2_2 = 0.0; // stage 2 state

    for (var i = 0; i < maxSamples; i++) {
      final pos = dataOffset + i * numChannels * 2;
      final raw = data.getInt16(pos, Endian.little);
      final s   = raw / 32768.0;

      // K-weight stage 1
      final ky1 = b1[0] * s + b1[1] * x1_1 + b1[2] * x1_2
                             - a1[1] * y1_1 - a1[2] * y1_2;
      x1_2 = x1_1; x1_1 = s;
      y1_2 = y1_1; y1_1 = ky1;

      // K-weight stage 2
      final ky2 = b2[0] * ky1 + b2[1] * x2_1 + b2[2] * x2_2
                               - a2[1] * y2_1 - a2[2] * y2_2;
      x2_2 = x2_1; x2_1 = ky1;
      y2_2 = y2_1; y2_1 = ky2;

      sumSq += ky2 * ky2;
      final abs = s.abs();
      if (abs > maxPeak) maxPeak = abs;
    }

    final meanSq   = sumSq / maxSamples;
    if (meanSq <= 0) return null;

    final lufs     = -0.691 + 10 * math.log(meanSq) / math.ln10;
    final rms      = 10 * math.log(meanSq) / math.ln10;
    final truePeak = maxPeak > 0 ? 20 * math.log(maxPeak) / math.ln10 : -60.0;

    return LoudnessResult(
      lufs:            lufs,
      rms:             rms,
      truePeak:        truePeak,
      isLufsEstimated: false,
      source:          'wav_dart',
    );
  }
}
