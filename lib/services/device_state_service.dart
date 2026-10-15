import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'log_service.dart';

/// How hot the device reports itself to be (`PowerManager.getCurrentThermalStatus`).
///
/// Values mirror the platform constants so the native layer can send them
/// through untouched; [unknown] also covers "this platform cannot tell".
enum DeviceThermalStatus {
  unknown,
  none,
  light,
  moderate,
  severe,
  critical,
  emergency,
  shutdown;

  static DeviceThermalStatus fromNative(int? value) {
    if (value == null || value < 0 || value >= DeviceThermalStatus.values.length) {
      return DeviceThermalStatus.unknown;
    }
    return DeviceThermalStatus.values[value];
  }
}

/// Coarse power state of the phone, used to decide whether the offline library
/// analysis may run in the background.
///
/// This is deliberately a *coarse* signal — charging, battery percentage and
/// thermal bucket. It never carries anything identifying, and every read is
/// best-effort: a device that cannot answer degrades to [DevicePowerState.unknown],
/// which fails open (analysis keeps working exactly as it did before the guard
/// existed) rather than silently disabling the feature.
@immutable
class DevicePowerState {
  const DevicePowerState({
    required this.charging,
    this.levelPercent,
    this.thermalStatus = DeviceThermalStatus.unknown,
  });

  /// True while the phone is plugged in and receiving power.
  final bool charging;

  /// Battery level 0..100, or null when the platform did not report one.
  final int? levelPercent;

  /// Thermal bucket reported by the platform.
  final DeviceThermalStatus thermalStatus;

  /// The fail-open state used when the native bridge is unavailable.
  static const DevicePowerState unknown = DevicePowerState(charging: true);

  /// Whether the idle library sweep may spend CPU on decoding right now.
  ///
  /// The policy is the user's own words: analyze *anytime, as long as the phone
  /// is not slow and the battery is safe*. So a phone that is charging is always
  /// allowed unless it is genuinely overheating; an unplugged phone is left alone
  /// once it gets low, and a merely warm unplugged phone waits for a better
  /// moment. [minLevelPercent] is the floor for the unplugged case.
  bool allowsBackgroundAnalysis({int minLevelPercent = 30}) {
    switch (thermalStatus) {
      case DeviceThermalStatus.severe:
      case DeviceThermalStatus.critical:
      case DeviceThermalStatus.emergency:
      case DeviceThermalStatus.shutdown:
        // The phone is telling us it is hot: give the CPU back to playback.
        return false;
      case DeviceThermalStatus.moderate:
        if (!charging) return false;
      case DeviceThermalStatus.unknown:
      case DeviceThermalStatus.none:
      case DeviceThermalStatus.light:
        break;
    }
    if (charging) return true;
    final level = levelPercent;
    // Unknown level while unplugged stays permissive (fail open).
    return level == null || level >= minLevelPercent;
  }

  /// Short, log-friendly description of the state.
  String describe() =>
      'charging=$charging level=${levelPercent ?? "?"} thermal=${thermalStatus.name}';
}

/// Thin bridge to the platform's battery + thermal state.
///
/// One MethodChannel call per query, no listeners and no permissions: the sweep
/// polls it a handful of times per session, which is far cheaper than keeping a
/// battery receiver alive for a background analysis feature.
class DeviceStateService {
  DeviceStateService._();

  static const MethodChannel _channel = MethodChannel('musicplayer/device_state');

  /// Reads the current power state. Never throws: unsupported platforms and
  /// bridge failures return [DevicePowerState.unknown].
  static Future<DevicePowerState> powerState() async {
    if (kIsWeb) return DevicePowerState.unknown;
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('powerState');
      if (map == null) return DevicePowerState.unknown;
      final level = (map['levelPercent'] as num?)?.toInt();
      return DevicePowerState(
        charging: map['charging'] as bool? ?? true,
        levelPercent: (level != null && level >= 0 && level <= 100) ? level : null,
        thermalStatus: DeviceThermalStatus.fromNative((map['thermal'] as num?)?.toInt()),
      );
    } on Object catch (e) {
      LogService.verbose('DeviceState', 'powerState unavailable: $e');
      return DevicePowerState.unknown;
    }
  }
}
