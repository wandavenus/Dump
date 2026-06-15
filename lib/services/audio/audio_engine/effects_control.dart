part of '../audio_engine.dart';

// ─── Effect-control library functions ─────────────────────────────────────────
//
//  These are library-level functions (not class methods).
//  They access AudioEngine private class members (e.g. AudioEngine._effectsChannel,
//  AudioEngine._virtualizerSupported) which is valid because part files share
//  the same library scope as the library-defining file.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _engineAttachNativeEffects(int sessionId) async {
  try {
    final result = await AudioEngine._effectsChannel
        .invokeMapMethod<String, dynamic>('attachEffects', {'sessionId': sessionId});
    if (result != null) {
      AudioEngine._virtualizerSupported = result['virtualizerSupported'] as bool? ?? false;
      AudioEngine._bassBoostSupported   = result['bassBoostSupported']   as bool? ?? false;
      AudioEngine._reverbSupported      = result['reverbSupported']      as bool? ?? false;
    }
    LogService.log(
      'AudioEngine',
      'Native effects attached (session $sessionId) '
      'virt=${AudioEngine._virtualizerSupported} '
      'bass=${AudioEngine._bassBoostSupported} '
      'reverb=${AudioEngine._reverbSupported}',
    );
  } catch (e) {
    LogService.warn('AudioEngine', 'attachEffects: $e');
  }
}

Future<void> _engineSetSpatial(bool enabled, int strength) async {
  if (!AudioEngine.isAndroid) return;
  try {
    await AudioEngine._effectsChannel.invokeMethod('setSpatialEnabled', {
      'enabled':  enabled,
      'strength': strength.clamp(0, 1000),
    });
  } catch (e) {
    LogService.warn('AudioEngine', 'setSpatialEnabled: $e');
  }
}

Future<void> _engineSetBassBoost(int strength) async {
  if (!AudioEngine.isAndroid) return;
  try {
    await AudioEngine._effectsChannel.invokeMethod(
      'setBassBoost', {'strength': strength.clamp(0, 1000)},
    );
  } catch (e) {
    LogService.warn('AudioEngine', 'setBassBoost: $e');
  }
}

Future<void> _engineSetReverb(int preset) async {
  if (!AudioEngine.isAndroid) return;
  try {
    await AudioEngine._effectsChannel.invokeMethod('setReverb', {'preset': preset});
  } catch (e) {
    LogService.warn('AudioEngine', 'setReverb: $e');
  }
}

Future<void> _engineRestoreEqBands(PlayerSlot slot) async {
  final eq = slot.equalizer;
  if (eq == null) return;
  try {
    final prefs  = await SharedPreferences.getInstance();
    final params = await eq.parameters;
    for (var i = 0; i < params.bands.length; i++) {
      final gain = prefs.getDouble('eqBand_$i');
      if (gain != null) await params.bands[i].setGain(gain);
    }
    final enabled = prefs.getBool('eqEnabled') ?? false;
    await eq.setEnabled(enabled);
  } catch (e) {
    LogService.warn('AudioEngine', 'restoreEqBands: $e');
  }
}

Future<void> _engineSetOutputMode(AudioOutputMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('audioOutputMode', mode.index);
  if (AudioEngine.isAndroid) _engineApplyOutputMode(mode);
  LogService.log('AudioEngine', 'Output mode: ${mode.name}');
}

Future<AudioOutputMode> _engineGetOutputMode() async {
  final prefs = await SharedPreferences.getInstance();
  final idx   = prefs.getInt('audioOutputMode') ?? 0;
  return AudioOutputMode.values[idx.clamp(0, 2)];
}

void _engineApplyOutputMode(AudioOutputMode mode) {
  try {
    AudioEngine._effectsChannel
        .invokeMethod('setAudioOutputMode', {'mode': mode.index});
  } catch (e) {
    LogService.warn('AudioEngine', 'setAudioOutputMode: $e');
  }
}
