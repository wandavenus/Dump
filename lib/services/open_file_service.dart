import 'package:flutter/services.dart';
import 'package:musicplayer/models/local_song.dart';
import 'package:musicplayer/services/audio_service.dart';
import 'package:musicplayer/services/log_service.dart';
import 'package:musicplayer/services/player_sheet_controller.dart';

/// Handles audio files opened from external apps (file managers, Telegram, etc.)
/// via Android ACTION_VIEW intents.
///
/// Call [registerHandler] early in startup (before runApp) to avoid dropping
/// warm intents. Call [checkInitialUri] after AudioService is ready to handle
/// the cold-start URI.
class OpenFileService {
  static const _channel = MethodChannel('musicplayer/open_file');

  static bool _handlerRegistered = false;
  static bool _initialUriChecked = false;

  /// Register the MethodChannel handler. Safe to call before AudioService is
  /// ready — incoming URIs are queued in native (pendingOpenFileUri) if they
  /// arrive before checkInitialUri().
  static void registerHandler() {
    if (_handlerRegistered) return;
    _handlerRegistered = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openUri') {
        final uri = call.arguments as String?;
        if (uri != null && uri.isNotEmpty) {
          // Native also writes to pendingOpenFileUri, so a brief miss here is
          // harmless — checkInitialUri() will drain it on the next resume.
          await _playUri(uri);
        }
      }
    });
  }

  /// Drain the initial/pending URI stored on the native side.
  /// Call this after AudioService.initialize() and permissions are granted.
  static Future<void> checkInitialUri() async {
    _initialUriChecked = true;
    try {
      final uri = await _channel.invokeMethod<String>('getInitialUri');
      if (uri != null && uri.isNotEmpty) {
        await _playUri(uri);
      }
    } on Exception catch (e) {
      // PlatformException, MissingPluginException, etc.
      LogService.error('OpenFileService', 'getInitialUri failed: $e');
    }
  }

  /// Call on every app resume to catch any URI that arrived while the Dart
  /// handler was not yet registered (edge case on very fast warm restarts).
  static Future<void> onResume() async {
    if (!_initialUriChecked) return; // too early; checkInitialUri() handles it
    try {
      final uri = await _channel.invokeMethod<String>('getInitialUri');
      if (uri != null && uri.isNotEmpty) {
        await _playUri(uri);
      }
    } on Exception catch (_) {}
  }

  // ── legacy alias kept for one-shot callers ────────────────────────────────
  static Future<void> initialize() async {
    registerHandler();
    await checkInitialUri();
  }

  static Future<void> _playUri(String uri) async {
    LogService.verbose('OpenFileService', 'Opening: $uri');
    try {
      // Convert content:// or file:// URI to a playable path/uri string.
      final String path;
      if (uri.startsWith('file://')) {
        path = Uri.parse(uri).toFilePath();
      } else {
        // content:// URI — pass as-is; ExoPlayer can handle content URIs.
        path = uri;
      }

      // Extract filename for a minimal title (strips extension).
      final rawName = path.split('/').last;
      final title = rawName.contains('.')
          ? rawName.substring(0, rawName.lastIndexOf('.'))
          : rawName;

      // Try to get duration from the file system if it's a real path.
      // For content:// URIs we fall back to 0; the engine will determine it.
      final song = LocalSong(
        id: 0,
        title: title,
        artist: 'Unknown Artist',
        path: path,
        album: 'Unknown Album',
        albumId: 0,
        duration: Duration.zero,
      );

      await AudioService.playSongAt(playlist: [song], index: 0);

      // Expand the player sheet so the user sees the preview player immediately.
      PlayerSheetController.open();
    } on Exception catch (e) {
      LogService.error('OpenFileService', 'Failed to play URI $uri: $e');
    }
  }
}
