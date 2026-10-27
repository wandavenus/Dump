import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/services/floating_pill_transition_controller.dart';
import 'package:musicplayer/services/player_sheet_controller.dart';

void main() {
  setUp(() {
    PlayerSheetController.setProgress(0.0);
    FloatingPillTransitionController.setDockEnabled(true);
    FloatingPillTransitionController.setMiniPlayerVisible(true);
    FloatingPillTransitionController.reset();
  });

  tearDown(() {
    PlayerSheetController.setProgress(0.0);
    FloatingPillTransitionController.setMiniPlayerVisible(false);
    FloatingPillTransitionController.setDockEnabled(false);
    FloatingPillTransitionController.reset();
  });

  test('scroll deltas continuously collapse the dock', () {
    FloatingPillTransitionController.updateFromScrollDelta(18.0);
    expect(
      FloatingPillTransitionController.progress.value,
      closeTo(0.25, 1e-9),
    );

    FloatingPillTransitionController.updateFromScrollDelta(18.0);
    expect(
      FloatingPillTransitionController.progress.value,
      closeTo(0.5, 1e-9),
    );
  });

  test('scrolling back toward the page start reverses the transition', () {
    FloatingPillTransitionController.updateFromScrollDelta(72.0);
    FloatingPillTransitionController.updateFromScrollDelta(-36.0);

    expect(
      FloatingPillTransitionController.progress.value,
      closeTo(0.5, 1e-9),
    );
  });

  test('transition progress is clamped at both bounds', () {
    FloatingPillTransitionController.updateFromScrollDelta(1000.0);
    expect(FloatingPillTransitionController.progress.value, 1.0);

    FloatingPillTransitionController.updateFromScrollDelta(-1000.0);
    expect(FloatingPillTransitionController.progress.value, 0.0);
  });

  test('invalid and zero deltas are ignored', () {
    FloatingPillTransitionController.updateFromScrollDelta(double.nan);
    FloatingPillTransitionController.updateFromScrollDelta(double.infinity);
    FloatingPillTransitionController.updateFromScrollDelta(0.0);

    expect(FloatingPillTransitionController.progress.value, 0.0);
  });

  test('scrolling behind an expanded player does not move the dock', () {
    PlayerSheetController.setProgress(1.0);
    FloatingPillTransitionController.updateFromScrollDelta(72.0);

    expect(FloatingPillTransitionController.progress.value, 0.0);
  });

  test('no mini player means there is no empty compact dock', () {
    FloatingPillTransitionController.setMiniPlayerVisible(false);
    FloatingPillTransitionController.updateFromScrollDelta(72.0);

    expect(FloatingPillTransitionController.progress.value, 0.0);
  });

  test('disabled pill style ignores scroll deltas', () {
    FloatingPillTransitionController.setDockEnabled(false);
    FloatingPillTransitionController.updateFromScrollDelta(72.0);

    expect(FloatingPillTransitionController.progress.value, 0.0);
  });
}
