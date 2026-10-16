import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/services/automix_service.dart';

void main() {
  group('native AutoMix plan signature', () {
    final baseTargets = <Map<String, Object?>>[
      <String, Object?>{
        'id': 101,
        'bpm': 128.0,
        'beatOffsetMs': 40.0,
        'downbeatOffsetMs': 40.0,
        'dropCueMs': 12000.0,
        'multiplier': 1.0,
      },
      <String, Object?>{
        'id': 202,
        'bpm': 126.0,
        'beatOffsetMs': 500.0,
        'downbeatOffsetMs': 500.0,
        'dropCueMs': 60000.0,
        'multiplier': 1.016,
        'fadeSeconds': 7.62,
        'fadeCurve': 1.35,
        'levelTrimOutgoing': 0.8,
        'levelTrimIncoming': 1.0,
      },
    ];

    String signature(
      List<Map<String, Object?>> targets, {
      double fadeSeconds = 8.0,
    }) => automixNativePlanSignature(101, fadeSeconds, targets);

    test('changes when any current or incoming target field changes', () {
      final baseline = signature(baseTargets);
      final mutations = <({int targetIndex, String field, Object? value})>[
        (targetIndex: 0, field: 'id', value: 102),
        (targetIndex: 0, field: 'bpm', value: 130.0),
        (targetIndex: 0, field: 'beatOffsetMs', value: 48.0),
        (targetIndex: 0, field: 'downbeatOffsetMs', value: 50.0),
        (targetIndex: 0, field: 'dropCueMs', value: 12500.0),
        (targetIndex: 0, field: 'multiplier', value: 0.99),
        (targetIndex: 1, field: 'id', value: 203),
        (targetIndex: 1, field: 'bpm', value: 127.0),
        (targetIndex: 1, field: 'beatOffsetMs', value: 520.0),
        (targetIndex: 1, field: 'downbeatOffsetMs', value: 521.0),
        (targetIndex: 1, field: 'dropCueMs', value: 61000.0),
        (targetIndex: 1, field: 'multiplier', value: 1.02),
        (targetIndex: 1, field: 'fadeSeconds', value: 7.7),
        (targetIndex: 1, field: 'fadeCurve', value: 1.1),
        (targetIndex: 1, field: 'levelTrimOutgoing', value: 0.9),
        (targetIndex: 1, field: 'levelTrimIncoming', value: 0.85),
      ];

      for (final mutation in mutations) {
        final changed = <Map<String, Object?>>[
          for (final target in baseTargets) Map<String, Object?>.of(target),
        ];
        changed[mutation.targetIndex][mutation.field] = mutation.value;

        expect(
          signature(changed),
          isNot(baseline),
          reason:
              'Changing target ${mutation.targetIndex} field '
              '${mutation.field} must invalidate the old signature.',
        );
      }
    });

    test('canonicalizes map insertion order', () {
      final reordered = <Map<String, Object?>>[
        <String, Object?>{
          'multiplier': 1.0,
          'dropCueMs': 12000.0,
          'downbeatOffsetMs': 40.0,
          'beatOffsetMs': 40.0,
          'bpm': 128.0,
          'id': 101,
        },
        <String, Object?>{
          'levelTrimIncoming': 1.0,
          'levelTrimOutgoing': 0.8,
          'fadeCurve': 1.35,
          'fadeSeconds': 7.62,
          'multiplier': 1.016,
          'dropCueMs': 60000.0,
          'downbeatOffsetMs': 500.0,
          'beatOffsetMs': 500.0,
          'bpm': 126.0,
          'id': 202,
        },
      ];

      expect(signature(reordered), signature(baseTargets));
    });

    test('changes when the global fade duration changes', () {
      expect(
        signature(baseTargets, fadeSeconds: 8.1),
        isNot(signature(baseTargets)),
      );
    });

    test('ignores target entries beyond the active deck pair', () {
      final withFarTarget = <Map<String, Object?>>[
        ...baseTargets.map(Map<String, Object?>.of),
        <String, Object?>{'id': 303, 'bpm': 100.0},
      ];
      final changedFarTarget = <Map<String, Object?>>[
        ...baseTargets.map(Map<String, Object?>.of),
        <String, Object?>{'id': 303, 'bpm': 140.0, 'fadeCurve': 2.0},
      ];

      expect(signature(withFarTarget), signature(changedFarTarget));
    });
  });
}
