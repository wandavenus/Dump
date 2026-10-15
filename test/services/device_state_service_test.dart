import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/services/device_state_service.dart';

/// The idle AutoMix library sweep decides with this policy, and it has to fail
/// open: a phone that cannot report its power state must keep the analysis it
/// had before the battery guard existed.
void main() {
  group('DevicePowerState background analysis policy', () {
    test('a charging phone is allowed unless it is genuinely overheating', () {
      expect(
        const DevicePowerState(charging: true, levelPercent: 4).allowsBackgroundAnalysis(),
        isTrue,
      );
      expect(
        const DevicePowerState(
          charging: true,
          levelPercent: 50,
          thermalStatus: DeviceThermalStatus.light,
        ).allowsBackgroundAnalysis(),
        isTrue,
      );
      expect(
        const DevicePowerState(
          charging: true,
          levelPercent: 50,
          thermalStatus: DeviceThermalStatus.severe,
        ).allowsBackgroundAnalysis(),
        isFalse,
      );
      expect(
        const DevicePowerState(
          charging: true,
          levelPercent: 50,
          thermalStatus: DeviceThermalStatus.critical,
        ).allowsBackgroundAnalysis(),
        isFalse,
      );
    });

    test('an unplugged phone is left alone once the battery is low', () {
      expect(
        const DevicePowerState(charging: false, levelPercent: 29)
            .allowsBackgroundAnalysis(),
        isFalse,
      );
      expect(
        const DevicePowerState(charging: false, levelPercent: 30)
            .allowsBackgroundAnalysis(),
        isTrue,
      );
      expect(
        const DevicePowerState(charging: false, levelPercent: 80)
            .allowsBackgroundAnalysis(),
        isTrue,
      );
    });

    test('a merely warm unplugged phone waits for a better moment', () {
      expect(
        const DevicePowerState(
          charging: false,
          levelPercent: 80,
          thermalStatus: DeviceThermalStatus.moderate,
        ).allowsBackgroundAnalysis(),
        isFalse,
      );
      // …but the same warmth while charging is fine.
      expect(
        const DevicePowerState(
          charging: true,
          levelPercent: 80,
          thermalStatus: DeviceThermalStatus.moderate,
        ).allowsBackgroundAnalysis(),
        isTrue,
      );
    });

    test('unknown state fails open so analysis is never silently disabled', () {
      expect(DevicePowerState.unknown.charging, isTrue);
      expect(DevicePowerState.unknown.allowsBackgroundAnalysis(), isTrue);
      // Unknown battery level while discharging also stays permissive.
      expect(
        const DevicePowerState(charging: false).allowsBackgroundAnalysis(),
        isTrue,
      );
    });

    test('native thermal codes map onto the enum, unknown codes included', () {
      expect(DeviceThermalStatus.fromNative(0), DeviceThermalStatus.unknown);
      expect(DeviceThermalStatus.fromNative(1), DeviceThermalStatus.none);
      expect(DeviceThermalStatus.fromNative(3), DeviceThermalStatus.moderate);
      expect(DeviceThermalStatus.fromNative(4), DeviceThermalStatus.severe);
      expect(DeviceThermalStatus.fromNative(7), DeviceThermalStatus.shutdown);
      // Out of range / missing values must not throw.
      expect(DeviceThermalStatus.fromNative(null), DeviceThermalStatus.unknown);
      expect(DeviceThermalStatus.fromNative(-1), DeviceThermalStatus.unknown);
      expect(DeviceThermalStatus.fromNative(99), DeviceThermalStatus.unknown);
    });
  });
}
