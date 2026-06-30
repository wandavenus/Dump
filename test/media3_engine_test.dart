import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/services/audio/engines/media3_engine.dart';

/// Unit tests for [Media3Engine.dispose].
///
/// The MethodChannel 'musicplayer/media3_playback' is intercepted by a mock
/// handler so no native code is needed.  All assertions target observable
/// Dart-side behaviour:
///   • dispose() sends the "release" method — not "stop".
///   • Double-dispose sends "release" only once (idempotency guard).
///   • Calling dispose() before initialize() is a complete no-op.
///   • Native errors during release are swallowed (graceful degradation).
///   • stop() and dispose() invoke different MethodChannel methods.
///
/// Test groups:
///   A. dispose() — sends "release"
///   B. dispose() idempotency — double-dispose is a no-op
///   C. dispose() before initialize() — no-op
///   D. Error handling — native exceptions do not propagate
///   E. stop vs release — different MethodChannel methods
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('musicplayer/media3_playback');
  final List<String> methodCalls = [];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methodCalls.add(call.method);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // ───────────────────────────────────────────────────────────────────────────
  // A. dispose() sends "release"
  // ───────────────────────────────────────────────────────────────────────────

  group('A — dispose() sends "release"', () {
    test(
      'A01 dispose after initialize invokes "release" on the MethodChannel',
      () async {
        final engine = Media3Engine();
        await engine.initialize();
        await engine.dispose();
        expect(methodCalls, contains('release'));
      },
    );

    test('A02 dispose sends exactly one "release" call', () async {
      final engine = Media3Engine();
      await engine.initialize();
      await engine.dispose();
      expect(methodCalls.where((m) => m == 'release').length, 1);
    });

    test('A03 isInitialized is false after dispose', () async {
      final engine = Media3Engine();
      await engine.initialize();
      expect(engine.isInitialized, isTrue);
      await engine.dispose();
      expect(engine.isInitialized, isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // B. dispose() idempotency
  // ───────────────────────────────────────────────────────────────────────────

  group('B — dispose() idempotency', () {
    test('B01 second dispose() call is a complete no-op', () async {
      final engine = Media3Engine();
      await engine.initialize();
      await engine.dispose();
      methodCalls.clear(); // reset after first dispose
      await engine.dispose(); // second call — must not send another "release"
      expect(methodCalls, isEmpty);
    });

    test(
      'B02 three dispose() calls send "release" exactly once total',
      () async {
        final engine = Media3Engine();
        await engine.initialize();
        await engine.dispose();
        await engine.dispose();
        await engine.dispose();
        expect(methodCalls.where((m) => m == 'release').length, 1);
      },
    );

    test(
      'B03 isInitialized stays false after repeated dispose calls',
      () async {
        final engine = Media3Engine();
        await engine.initialize();
        await engine.dispose();
        await engine.dispose();
        expect(engine.isInitialized, isFalse);
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // C. dispose() before initialize()
  // ───────────────────────────────────────────────────────────────────────────

  group('C — dispose() before initialize()', () {
    test(
      'C01 dispose before initialize sends nothing to the MethodChannel',
      () async {
        final engine = Media3Engine();
        await engine.dispose(); // never initialized
        expect(methodCalls, isEmpty);
      },
    );

    test('C02 dispose before initialize does not throw', () async {
      final engine = Media3Engine();
      await expectLater(engine.dispose(), completes);
    });

    test('C03 isInitialized is false before and after no-op dispose', () async {
      final engine = Media3Engine();
      expect(engine.isInitialized, isFalse);
      await engine.dispose();
      expect(engine.isInitialized, isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // D. Error handling — native exceptions do not propagate
  // ───────────────────────────────────────────────────────────────────────────

  group('D — native errors do not propagate', () {
    test('D01 PlatformException from native side is swallowed', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'release') {
              throw PlatformException(
                code: 'NATIVE_ERROR',
                message: 'service dead',
              );
            }
            return null;
          });

      final engine = Media3Engine();
      await engine.initialize();
      // Must complete without rethrowing the platform exception.
      await expectLater(engine.dispose(), completes);
    });

    test('D02 MissingPluginException from native side is swallowed', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'release') {
              throw MissingPluginException('No implementation found');
            }
            return null;
          });

      final engine = Media3Engine();
      await engine.initialize();
      await expectLater(engine.dispose(), completes);
    });

    test(
      'D03 isInitialized is false even when native release throws',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              throw PlatformException(code: 'ERR');
            });

        final engine = Media3Engine();
        await engine.initialize();
        await engine.dispose();
        // _initialized was cleared before the await, so it stays false.
        expect(engine.isInitialized, isFalse);
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // E. stop vs release — different MethodChannel methods
  //
  // "stop" transitions ExoPlayer to STATE_IDLE; the service stays alive.
  // "release" (dispose) triggers a full service teardown via stopSelf().
  // Both map to different MethodChannel method names — this test verifies
  // the mapping so a refactor cannot accidentally swap them.
  // ───────────────────────────────────────────────────────────────────────────

  group('E — stop vs release semantic difference', () {
    test('E01 stop() sends "stop", not "release"', () async {
      final engine = Media3Engine();
      await engine.initialize();
      await engine.stop();
      expect(methodCalls, contains('stop'));
      expect(methodCalls, isNot(contains('release')));
    });

    test('E02 dispose() sends "release", not "stop"', () async {
      final engine = Media3Engine();
      await engine.initialize();
      await engine.dispose();
      expect(methodCalls, contains('release'));
      expect(methodCalls, isNot(contains('stop')));
    });

    test(
      'E03 stop then dispose sends both methods in the correct order',
      () async {
        final engine = Media3Engine();
        await engine.initialize();
        await engine.stop();
        await engine.dispose();
        final stopIndex = methodCalls.indexOf('stop');
        final releaseIndex = methodCalls.indexOf('release');
        expect(stopIndex, greaterThanOrEqualTo(0));
        expect(releaseIndex, greaterThan(stopIndex));
      },
    );
  });
}
