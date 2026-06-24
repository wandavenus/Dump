import 'package:flutter/services.dart';

class RgScanResult {
  final double integratedLufs;
  final double trackGainDb;
  final double trackPeak;
  final bool tagsWritten;

  const RgScanResult({
    required this.integratedLufs,
    required this.trackGainDb,
    required this.trackPeak,
    required this.tagsWritten,
  });
}

class ReplayGainScannerService {
  static const _channel = MethodChannel('musicplayer/media_store');

  static Future<RgScanResult> scan(String path) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'scanReplayGain',
      {'path': path},
    );
    if (result == null) throw Exception('No result from native scanner');
    return RgScanResult(
      integratedLufs: (result['integratedLufs'] as num).toDouble(),
      trackGainDb: (result['trackGainDb'] as num).toDouble(),
      trackPeak: (result['trackPeak'] as num).toDouble(),
      tagsWritten: result['tagsWritten'] as bool? ?? false,
    );
  }
}
