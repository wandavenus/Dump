part of '../song_metadata_service.dart';

class SongMetadataService {
  SongMetadataService._();

  static const MethodChannel _channel = MethodChannel('musicplayer/media_store');
  static const String unknown = 'Unknown';

  static Future<SongInfo> getSongInfo(LocalSong song) async {
    final metadata = await _loadNativeMetadata(song);
    return SongInfo(
      title:      _clean(song.title),
      artist:     _clean(song.artist),
      album:      _clean(song.album),
      year:       _clean(metadata['year']),
      duration:   _formatDuration(song.duration),
      format:     extractAudioFormat(song.path),
      bitrate:    _formatBitrate(metadata['bitrate']),
      sampleRate: _formatSampleRate(metadata['sampleRate']),
      fileSize:   formatFileSize(int.tryParse(metadata['fileSize'] ?? '')),
      filePath:   _clean(song.path),
    );
  }

  static Future<Map<String, String>> _loadNativeMetadata(LocalSong song) async {
    if (kIsWeb || song.path.trim().isEmpty) return const <String, String>{};
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getAudioMetadata',
        {'path': song.path, 'songId': song.id},
      );
      if (result == null) return const <String, String>{};
      return result.map((key, value) => MapEntry(key, value?.toString() ?? ''));
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Failed to load metadata for ${song.path}: $error\n$stackTrace');
      return const <String, String>{};
    } catch (error, stackTrace) {
      debugPrint('Invalid metadata payload for ${song.path}: $error\n$stackTrace');
      return const <String, String>{};
    }
  }

  static String extractAudioFormat(String path) {
    final sanitizedPath = path.split('?').first.trim();
    if (sanitizedPath.isEmpty || !sanitizedPath.contains('.')) return unknown;
    final extension = sanitizedPath.split('.').last.toUpperCase();
    return extension.isEmpty ? unknown : extension;
  }

  static String formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return unknown;
    const units = ['B', 'KB', 'MB', 'GB'];
    var size      = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    final formatted = unitIndex == 0
        ? size.toStringAsFixed(0)
        : size.toStringAsFixed(size >= 10 ? 1 : 2);
    return '$formatted ${units[unitIndex]}';
  }
}
