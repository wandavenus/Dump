import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/services/automix_service.dart';

void main() {
  group('AutomixSettings boundaries', () {
    test('corrupt persisted values fall back to safe defaults', () {
      final settings = AutomixSettings.fromMap(<dynamic, dynamic>{
        'profile': 42,
        'bpmTolerance': double.nan,
        'beats': -8,
        'avoidArtistRepeat': 'yes',
        'harmonicFilter': null,
      });

      expect(settings.profile, equals(AutomixProfile.dj));
      expect(settings.bpmTolerancePercent, equals(6.0));
      expect(settings.crossfadeBeats, equals(16));
      expect(settings.avoidArtistRepeat, isTrue);
      expect(settings.harmonicFilter, isFalse);
    });

    test('extreme or fractional persisted values are not sent to native', () {
      final settings = AutomixSettings.fromMap(<dynamic, dynamic>{
        'bpmTolerance': 1000,
        'beats': 16.5,
      });

      expect(settings.bpmTolerancePercent, equals(6.0));
      expect(settings.crossfadeBeats, equals(16));
    });

    test('valid values survive hydration and copyWith', () {
      final settings = AutomixSettings.fromMap(<dynamic, dynamic>{
        'profile': 'energy',
        'bpmTolerance': 7.5,
        'beats': 24,
      });
      final updated = settings.copyWith(
        bpmTolerancePercent: 0,
        crossfadeBeats: 65,
      );

      expect(settings.profile, equals(AutomixProfile.energy));
      expect(settings.bpmTolerancePercent, equals(7.5));
      expect(settings.crossfadeBeats, equals(24));
      expect(updated.bpmTolerancePercent, equals(6.0));
      expect(updated.crossfadeBeats, equals(16));
    });
  });
}
