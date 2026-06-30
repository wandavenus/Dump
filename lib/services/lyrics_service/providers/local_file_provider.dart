import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../services/log_service.dart';
import '../cancellation.dart';
import '../lrc_parser.dart';
import '../provider.dart';
import '../quality.dart';

/// Provider: file lirik lokal di direktori yang sama dengan audio,
/// atau di folder yang dikonfigurasi pengguna.
///
/// Ekstensi yang didukung: .lrc, .elrc, .lrcx
class LocalFileProvider implements LyricsProvider {
  /// Folder lirik yang dikonfigurasi pengguna (opsional).
  /// Jika kosong, hanya direktori audio yang diperiksa.
  final String Function() getConfiguredFolder;

  const LocalFileProvider({required this.getConfiguredFolder});

  static const _extensions = ['.lrc', '.elrc', '.lrcx'];

  @override
  String get name => 'File Lokal';

  @override
  bool get isOnline => false;

  @override
  Future<LyricsProviderResult?> fetch(
    LyricsQuery query,
    CancellationToken cancelToken,
  ) async {
    if (kIsWeb) return null;
    final path = query.filePath;
    if (path == null || path.isEmpty) return null;

    cancelToken.throwIfCancelled();

    // Cari di direktori yang sama dengan file audio
    final result = await _searchInFolder(
      audioPath: path,
      folder: p.dirname(path),
      cancelToken: cancelToken,
    );
    if (result != null) return result;

    // Cari di folder yang dikonfigurasi pengguna
    final configured = getConfiguredFolder().trim();
    if (configured.isNotEmpty) {
      return _searchInFolder(
        audioPath: path,
        folder: configured,
        cancelToken: cancelToken,
      );
    }
    return null;
  }

  Future<LyricsProviderResult?> _searchInFolder({
    required String audioPath,
    required String folder,
    required CancellationToken cancelToken,
  }) async {
    final nameNoExt = p.basenameWithoutExtension(audioPath);
    for (final ext in _extensions) {
      cancelToken.throwIfCancelled();
      final filePath = p.join(folder, '$nameNoExt$ext');
      final file = File(filePath);

      FileSystemEntityType type;
      try {
        type = (await file.stat()).type; // ignore: avoid_slow_async_io
      } catch (_) {
        continue;
      }
      if (type == FileSystemEntityType.notFound) continue;

      final raw = await _readFile(file);
      if (raw == null || raw.trim().isEmpty) continue;

      cancelToken.throwIfCancelled();
      final parsed = LrcParser.parse(raw.trim());
      if (parsed.isEmpty) continue;

      LogService.verbose(
        'LocalFileProvider',
        'Found $filePath — ${parsed.lines.length} lines [${parsed.quality.displayName}]',
      );
      return LyricsProviderResult(
        lines: parsed.lines,
        quality: parsed.quality,
        providerName: 'Dari file lokal',
        isInternet: false,
        rawLrc: raw.trim(),
      );
    }
    return null;
  }

  Future<String?> _readFile(File file) async {
    try {
      String raw = await file.readAsString(encoding: utf8);
      if (raw.contains('\uFFFD')) {
        raw = await file.readAsString(encoding: latin1);
      }
      return raw;
    } catch (_) {
      try {
        return await file.readAsString(encoding: latin1);
      } catch (_) {
        return null;
      }
    }
  }
}
