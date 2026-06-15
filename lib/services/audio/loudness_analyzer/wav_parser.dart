part of '../loudness_analyzer.dart';

// ─── Pure-Dart WAV loudness parser ────────────────────────────────────────────
//
//  Extracted from LoudnessAnalyzer to keep analyzer.dart focused on the
//  analysis pipeline.  These are library-level functions used with
//  Flutter's compute() for isolate execution.
// ─────────────────────────────────────────────────────────────────────────────

/// Top-level function required by [compute].
LoudnessResult? _wavParseIsolate(String filePath) {
  try {
    final bytes = File(filePath).readAsBytesSync();
    return _wavParse(bytes);
  } catch (_) {
    return null;
  }
}

LoudnessResult? _wavParse(Uint8List bytes) {
  if (bytes.length < 44) return null;
  final data = ByteData.sublistView(bytes);

  final riff = String.fromCharCodes(bytes.sublist(0, 4));
  final wave = String.fromCharCodes(bytes.sublist(8, 12));
  if (riff != 'RIFF' || wave != 'WAVE') return null;

  int offset        = 12;
  int dataOffset    = -1;
  int dataSize      = -1;
  int audioFormat   = 0;
  int numChannels   = 0;
  int sampleRate    = 0;
  int bitsPerSample = 0;

  while (offset < bytes.length - 8) {
    final chunkId   = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    offset += 8;
    if (chunkId == 'fmt ') {
      audioFormat   = data.getUint16(offset,      Endian.little);
      numChannels   = data.getUint16(offset + 2,  Endian.little);
      sampleRate    = data.getUint32(offset + 4,  Endian.little);
      bitsPerSample = data.getUint16(offset + 14, Endian.little);
    } else if (chunkId == 'data') {
      dataOffset = offset;
      dataSize   = chunkSize;
      break;
    }
    offset += chunkSize + (chunkSize & 1);
  }

  if (dataOffset < 0 || audioFormat != 1 || bitsPerSample != 16) return null;
  if (numChannels == 0 || sampleRate == 0) return null;

  final sampleCount = dataSize ~/ (numChannels * 2);
  if (sampleCount == 0) return null;

  final maxSamples = math.min(sampleCount, sampleRate * 60);

  double sumSq   = 0.0;
  double maxPeak = 0.0;

  // K-weighting biquad (48 kHz coefficients)
  // Stage 1: high-shelf pre-filter
  const b1 = [1.53512485958697, -2.69169618940638, 1.19839281085285];
  const a1 = [1.0,              -1.69065929318241, 0.73248077421585];
  // Stage 2: RLB high-pass
  const b2 = [1.0, -2.0,  1.0];
  const a2 = [1.0, -1.99004745483398, 0.99007225036498];

  var x1_1 = 0.0, x1_2 = 0.0, y1_1 = 0.0, y1_2 = 0.0;
  var x2_1 = 0.0, x2_2 = 0.0, y2_1 = 0.0, y2_2 = 0.0;

  for (var i = 0; i < maxSamples; i++) {
    final pos = dataOffset + i * numChannels * 2;
    final raw = data.getInt16(pos, Endian.little);
    final s   = raw / 32768.0;

    final ky1 = b1[0] * s   + b1[1] * x1_1 + b1[2] * x1_2
                             - a1[1] * y1_1 - a1[2] * y1_2;
    x1_2 = x1_1; x1_1 = s;
    y1_2 = y1_1; y1_1 = ky1;

    final ky2 = b2[0] * ky1 + b2[1] * x2_1 + b2[2] * x2_2
                             - a2[1] * y2_1 - a2[2] * y2_2;
    x2_2 = x2_1; x2_1 = ky1;
    y2_2 = y2_1; y2_1 = ky2;

    sumSq += ky2 * ky2;
    final abs = s.abs();
    if (abs > maxPeak) maxPeak = abs;
  }

  final meanSq = sumSq / maxSamples;
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
