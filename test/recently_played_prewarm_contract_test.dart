import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'recently played startup prewarm keeps 170px UI cache key prioritized',
    () {
      final mainSource = File('lib/main/main.dart').readAsStringSync();

      expect(
        mainSource,
        contains('final visibleRecentIds = recentIds.take(4).toList'),
      );
      expect(mainSource, contains('targetSizePx: smallPx'));
      expect(mainSource, contains('recentIds.skip(4).take(12).toList'));
      expect(mainSource, isNot(contains('Recently Played (250)')));
    },
  );
}
