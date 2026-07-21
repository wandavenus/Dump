import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/utils/safe_num.dart';

void main() {
  group('SafeNumToInt.toIntOrElse', () {
    test('converts a finite int correctly', () {
      expect(42.toIntOrElse(-1), equals(42));
    });

    test('converts a finite double correctly', () {
      expect(3.7.toIntOrElse(-1), equals(3));
    });

    test('returns fallback for double.nan', () {
      expect(double.nan.toIntOrElse(-1), equals(-1));
    });

    test('returns fallback for double.infinity', () {
      expect(double.infinity.toIntOrElse(0), equals(0));
    });

    test('returns fallback for double.negativeInfinity', () {
      expect(double.negativeInfinity.toIntOrElse(0), equals(0));
    });

    test('returns 0 for 0.0', () {
      expect(0.0.toIntOrElse(-1), equals(0));
    });

    test('handles negative finite values', () {
      expect((-5).toIntOrElse(0), equals(-5));
    });
  });
}
