import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/services/log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('musicplayer/logging');
  final nativeCalls = <MethodCall>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    nativeCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call);
          return null;
        });

    LogService.loggingEnabled.value = false;
    LogService.errorsOnly.value = false;
    LogService.verboseEnabled.value = false;
    LogService.liveTailEnabled.value = true;
    LogService.isInitialized = false;
    LogService.clear();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    LogService.clear();
  });

  test('logging calls are dropped immediately while toggle is OFF', () {
    LogService.log('Test', 'must not be retained');
    LogService.warn('Test', 'warning must not be retained');
    LogService.error('Test', 'error must not be retained');

    expect(LogService.logCount.value, 0);
    expect(LogService.getLogs(), isEmpty);
  });

  test('console debug prints follow the app logging toggle', () {
    final printed = <String?>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      printed.add(message);
    };

    try {
      LogService.debugPrintIfEnabled('hidden');
      expect(printed, isEmpty);

      LogService.loggingEnabled.value = true;
      LogService.debugPrintIfEnabled('visible');
      expect(printed, equals(['visible']));
    } finally {
      debugPrint = previousDebugPrint;
    }
  });

  test(
    'turning logging OFF clears buffered entries and syncs native gate',
    () async {
      await LogService.setLoggingEnabled(true);
      LogService.log('Test', 'temporary entry');
      expect(LogService.logCount.value, 1);

      await LogService.setLoggingEnabled(false);

      expect(LogService.logCount.value, 0);
      expect(LogService.getLogs(), isEmpty);
      expect(nativeCalls.map((call) => call.arguments), equals([true, false]));
      expect(nativeCalls.every((call) => call.method == 'setEnabled'), isTrue);
    },
  );

  test('redacts absolute paths and URIs before storing entries', () async {
    await LogService.setLoggingEnabled(true);
    LogService.log(
      'Test',
      'opened /storage/emulated/0/Music/Private/song.flac via content://media/external/audio/media/42',
    );

    final message = LogService.getLogs().single.message;
    expect(message, contains('<path>'));
    expect(message, contains('<uri>'));
    expect(message, isNot(contains('Private')));
    expect(message, isNot(contains('media/external')));
    expect(
      LogService.redact('/database is not a device path'),
      '/database is not a device path',
    );
  });

  test('normalizes category aliases for filtering', () async {
    await LogService.setLoggingEnabled(true);
    LogService.log('AudioEffects', 'one');
    LogService.warn('ReplayGainApplicator', 'two');

    expect(
      LogService.getCategories(),
      containsAll(<String>['Audio', 'ReplayGain']),
    );
    expect(LogService.getLogs(category: 'Audio'), hasLength(1));
    expect(LogService.getLogs(category: 'ReplayGain'), hasLength(1));
  });

  test('revision advances when the ring buffer is full', () async {
    await LogService.setLoggingEnabled(true);
    LogService.verboseEnabled.value = true;
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    try {
      for (var i = 0; i < 5000; i++) {
        LogService.verbose('Test', 'entry $i');
      }
      final fullRevision = LogService.logRevision.value;
      LogService.verbose('Test', 'overflow');
      expect(LogService.logRevision.value, greaterThan(fullRevision));
      expect(LogService.logCount.value, 5000);
    } finally {
      debugPrint = previousDebugPrint;
    }
  });

  test('buffer overflow keeps warnings and errors', () async {
    await LogService.setLoggingEnabled(true);
    LogService.verboseEnabled.value = true;
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    try {
      LogService.error('Test', 'must survive');
      for (var i = 0; i < 5000; i++) {
        LogService.verbose('Test', 'noise $i');
      }

      expect(LogService.getErrors(), hasLength(1));
      expect(LogService.getErrors().single.message, 'must survive');
    } finally {
      debugPrint = previousDebugPrint;
    }
  });

  test('startup syncs the persisted logging preference to Android', () async {
    SharedPreferences.setMockInitialValues({'log_enabled': false});

    await LogService.init();

    expect(LogService.loggingEnabled.value, isFalse);
    expect(nativeCalls, hasLength(1));
    expect(nativeCalls.single.method, 'setEnabled');
    expect(nativeCalls.single.arguments, isFalse);
  });
}
