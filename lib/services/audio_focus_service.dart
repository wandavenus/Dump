import 'audio/audio_session_handler.dart';
import 'log_service.dart';

/// Thin wrapper retained for backwards compatibility.
/// Real implementation is in [AudioSessionHandler].
class AudioFocusService {
  AudioFocusService._();

  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    AudioSessionHandler.initialize();
    LogService.log('AudioFocus', 'Initialized');
  }

  static void onFocusLoss({bool transient = false}) {
    AudioSessionHandler.onAppPause();
  }

  static void onFocusGain() {
    AudioSessionHandler.onAppResume();
  }
}
