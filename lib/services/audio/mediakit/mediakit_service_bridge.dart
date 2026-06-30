import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../models/local_song.dart';
import '../../log_service.dart';

/// Dart ↔ Native bridge for the [MediaKitPlaybackService] Android foreground
/// service.
///
/// Responsibilities:
///   • Start / stop the Android foreground service via MethodChannel.
///   • Push track metadata and playback state to the service so it can update
///     the notification and [MediaSession].
///   • Receive transport commands (play, pause, next, previous, seek, stop)
///     issued by the system (lock screen, BT, notification buttons) via
///     EventChannel, and forward them to the registered handler.
///
/// Platform guard: all methods are no-ops on non-Android platforms (web, iOS,
/// desktop) so the engine can call them unconditionally without platform checks.
///
/// Channel names:
///   musicplayer/mediakit_service   — MethodChannel (Dart → Native)
///   musicplayer/mediakit_transport — EventChannel  (Native → Dart)
class MediaKitServiceBridge {
  MediaKitServiceBridge._();

  static const _serviceChannel = MethodChannel('musicplayer/mediakit_service');
  static const _transportChannel = EventChannel(
    'musicplayer/mediakit_transport',
  );

  static StreamSubscription<dynamic>? _transportSub;

  /// Called when the native service sends a transport command.
  /// Signature: (action, positionMs?) where positionMs is only set for "seek".
  static void Function(String action, int? positionMs)? _transportHandler;

  // ── Setup ─────────────────────────────────────────────────────────────────

  /// Register the callback that receives transport commands from the system.
  /// Call this before [startListening].
  static void setTransportCommandHandler(
    void Function(String action, int? positionMs) handler,
  ) {
    _transportHandler = handler;
  }

  /// Start listening to the native transport EventChannel.
  /// Safe to call multiple times — cancels any previous subscription first.
  static Future<void> startListening() async {
    if (!_isAndroid) return;
    await _transportSub?.cancel();
    _transportSub = _transportChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        final action = event['action'] as String? ?? '';
        final positionMs = (event['positionMs'] as num?)?.toInt();
        if (action.isNotEmpty) {
          _transportHandler?.call(action, positionMs);
        }
      },
      onError: (Object e) {
        LogService.warn('MediaKitServiceBridge', 'Transport stream error: $e');
      },
    );
  }

  /// Cancel the transport EventChannel subscription.
  static Future<void> stopListening() async {
    await _transportSub?.cancel();
    _transportSub = null;
  }

  // ── Service lifecycle ─────────────────────────────────────────────────────

  /// Ask Android to start [MediaKitPlaybackService] as a foreground service.
  /// Returns immediately; the service may not be ready yet.
  static Future<void> startService() async {
    if (!_isAndroid) return;
    try {
      await _serviceChannel.invokeMethod<void>('startService');
    } catch (e) {
      LogService.warn('MediaKitServiceBridge', 'startService error: $e');
    }
  }

  /// Ask the service to stop foreground and call [stopSelf].
  static Future<void> stopService() async {
    if (!_isAndroid) return;
    try {
      await _serviceChannel.invokeMethod<void>('release');
    } catch (e) {
      LogService.warn('MediaKitServiceBridge', 'release error: $e');
    }
  }

  // ── Metadata / state push ─────────────────────────────────────────────────

  /// Push current track metadata to the service.
  ///
  /// The service updates [MediaKitStatePlayer] and refreshes the notification.
  /// Retries once (after 600 ms) if the service is still starting
  /// (native returns "not_ready").
  static Future<void> updateMetadata({
    required String title,
    required String artist,
    String? artworkUri,
    required int durationMs,
  }) async {
    if (!_isAndroid) return;
    final args = <String, Object?>{
      'title': title,
      'artist': artist,
      'artworkUri': artworkUri,
      'durationMs': durationMs,
    };
    try {
      await _serviceChannel.invokeMethod<void>('updateMetadata', args);
    } on PlatformException catch (e) {
      if (e.code == 'not_ready') {
        // Service just started — retry after it has had time to initialise.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        try {
          await _serviceChannel.invokeMethod<void>('updateMetadata', args);
        } catch (e2) {
          LogService.warn(
            'MediaKitServiceBridge',
            'updateMetadata retry failed: $e2',
          );
        }
      } else {
        LogService.warn('MediaKitServiceBridge', 'updateMetadata error: $e');
      }
    } catch (e) {
      LogService.warn('MediaKitServiceBridge', 'updateMetadata error: $e');
    }
  }

  /// Push current playback state to the service.
  ///
  /// The service updates the [MediaKitStatePlayer] (so lock-screen shows the
  /// correct play/pause icon) and refreshes the notification.
  static Future<void> updatePlaybackState({
    required bool isPlaying,
    required int positionMs,
  }) async {
    if (!_isAndroid) return;
    try {
      await _serviceChannel.invokeMethod<void>('updatePlaybackState', {
        'isPlaying': isPlaying,
        'positionMs': positionMs,
      });
    } catch (e) {
      LogService.warn('MediaKitServiceBridge', 'updatePlaybackState error: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static bool get _isAndroid {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  /// Build a metadata map from a [LocalSong].
  static Map<String, Object?> songToMetadata(
    LocalSong song, {
    Duration duration = Duration.zero,
  }) => {
    'title': song.title,
    'artist': song.artist,
    'artworkUri': song.artworkUri,
    'durationMs':
        duration == Duration.zero
            ? song.duration.inMilliseconds
            : duration.inMilliseconds,
  };
}
