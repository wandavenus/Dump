part of '../song_metadata_service.dart';

// ─── Private formatting helpers ───────────────────────────────────────────────
// Library-level functions extracted from SongMetadataService.
// Accessible within the library via direct call (no class prefix needed).

String _formatDuration(Duration duration) {
  if (duration <= Duration.zero) return SongMetadataService.unknown;
  final hours   = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _formatBitrate(String? rawBitrate) {
  final bitrate = int.tryParse(rawBitrate ?? '');
  if (bitrate == null || bitrate <= 0) return SongMetadataService.unknown;
  return '${(bitrate / 1000).round()} kbps';
}

String _formatSampleRate(String? rawSampleRate) {
  final sampleRate = int.tryParse(rawSampleRate ?? '');
  if (sampleRate == null || sampleRate <= 0) return SongMetadataService.unknown;
  final khz       = sampleRate / 1000;
  final formatted = khz == khz.roundToDouble()
      ? khz.toStringAsFixed(0)
      : khz.toStringAsFixed(1);
  return '$formatted kHz';
}

String _clean(String? value) {
  final sanitized = value?.trim();
  if (sanitized == null || sanitized.isEmpty || sanitized == '<unknown>') {
    return SongMetadataService.unknown;
  }
  return sanitized;
}
