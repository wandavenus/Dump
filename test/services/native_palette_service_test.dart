import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/services/log_service.dart';
import 'package:musicplayer/services/native_palette_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const paletteChannel = MethodChannel('dev.wndavenz.music/native_palette');

  const fallback = <int>[
    0xFF2B313A,
    0xFF4E657D,
    0xFF7B8794,
    0xFFABBED4,
    0xFF121821,
  ];
  const extracted = <int>[
    0xFF336699,
    0xFF224466,
    0xFF112233,
    0xFFAABBCC,
    0xFF001122,
  ];

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory tempDir;
  late int extractCount;
  late Future<List<int>?> Function() nextExtraction;

  setUp(() async {
    LogService.loggingEnabled.value = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    NativePaletteService.resetForTests();
    tempDir = await Directory.systemTemp.createTemp('native_palette_test_');
    extractCount = 0;
    nextExtraction = () async => extracted;

    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      return tempDir.path;
    });
    messenger.setMockMethodCallHandler(paletteChannel, (call) async {
      switch (call.method) {
        case 'getCacheVersion':
          return 9;
        case 'extractPalette':
          extractCount++;
          return nextExtraction();
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    messenger.setMockMethodCallHandler(paletteChannel, null);
    NativePaletteService.resetForTests();
    debugDefaultTargetPlatformOverride = null;
    await tempDir.delete(recursive: true);
  });

  Future<File> writeCache(Object value) async {
    final dir = Directory('${tempDir.path}/artwork')
      ..createSync(recursive: true);
    final file = File('${dir.path}/palette_cache_v9.json');
    await file.writeAsString(jsonEncode(value));
    return file;
  }

  group('warmUp', () {
    test('ignores a non-object cache instead of throwing', () async {
      await writeCache(<Object?>[]);

      await expectLater(NativePaletteService.warmUp(), completes);
      expect(NativePaletteService.getSync(1), isNull);
    });

    test('skips malformed and out-of-range rows', () async {
      await writeCache(<String, Object?>{
        '1': <Object?>[0xFF010203, 0xFF040506, 0xFF070809],
        '2': <Object?>[0xFF010203, 0xFF040506, 'not-a-number'],
        '3': <Object?>[-1, 0xFF040506, 0xFF070809],
        '4': fallback,
        'not-a-song': <Object?>[0xFF010203, 0xFF040506, 0xFF070809],
        '5': <Object?>[0xFF010203, 0xFF040506],
      });

      await NativePaletteService.warmUp();

      expect(NativePaletteService.getSync(1), isNotNull);
      expect(NativePaletteService.getSync(2), isNull);
      expect(NativePaletteService.getSync(3), isNull);
      expect(NativePaletteService.getSync(4), isNull);
      expect(NativePaletteService.getSync(5), isNull);
    });

    test('pads and truncates entries to exactly five colors', () async {
      await writeCache(<String, Object?>{
        '7': <Object?>[0xFF112233, 0xFF445566, 0xFF778899],
        '8': <Object?>[
          0xFF112233,
          0xFF445566,
          0xFF778899,
          0xFFAABBCC,
          0xFFDDEEFF,
          0xFF010203,
        ],
      });

      await NativePaletteService.warmUp();

      final padded = NativePaletteService.getSync(7);
      expect(padded, hasLength(5));
      expect(padded![3].toARGB32(), 0xFFABBED4);
      expect(padded[4].toARGB32(), 0xFF121821);

      final truncated = NativePaletteService.getSync(8);
      expect(truncated, hasLength(5));
      expect(truncated![4].toARGB32(), 0xFFDDEEFF);
    });
  });

  group('get', () {
    test('deduplicates concurrent requests for the same song', () async {
      final completer = Completer<List<int>?>();
      nextExtraction = () => completer.future;

      final first = NativePaletteService.get(42);
      final second = NativePaletteService.get(42);
      expect(identical(first, second), isTrue);

      await Future<void>.delayed(Duration.zero);
      expect(extractCount, 1);

      completer.complete(extracted);
      expect(await first, hasLength(5));
      expect(NativePaletteService.getSync(42), isNotNull);
    });

    test('pads a three-color native response', () async {
      nextExtraction = () async => const [0xFF112233, 0xFF445566, 0xFF778899];

      final colors = await NativePaletteService.get(43);

      expect(colors, hasLength(5));
      expect(colors[3].toARGB32(), 0xFFABBED4);
      expect(colors[4].toARGB32(), 0xFF121821);
    });

    test('does not cache the hard fallback', () async {
      nextExtraction = () async => fallback;

      final colors = await NativePaletteService.get(44);

      expect(NativePaletteService.isHardFallback(colors), isTrue);
      expect(NativePaletteService.getSync(44), isNull);
      expect(extractCount, 2);
    });

    test('rejects out-of-range native values without throwing', () async {
      nextExtraction = () async => const [
        0xFF112233,
        -1,
        -1, // sentinel: not a valid ARGB value
      ];

      final colors = await NativePaletteService.get(45);

      expect(NativePaletteService.isHardFallback(colors), isTrue);
      expect(NativePaletteService.getSync(45), isNull);
    });

    test('times out instead of pinning the caller and retries', () async {
      NativePaletteService.extractTimeout = const Duration(milliseconds: 20);
      final never = Completer<List<int>?>();
      nextExtraction = () => never.future;

      final stopwatch = Stopwatch()..start();
      final colors = await NativePaletteService.get(46);
      stopwatch.stop();

      expect(NativePaletteService.isHardFallback(colors), isTrue);
      expect(NativePaletteService.getSync(46), isNull);
      expect(extractCount, 2);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));

      if (!never.isCompleted) never.complete(null);
    });
  });

  group('invalidate', () {
    test('drops the memory entry and forces re-extraction', () async {
      final first = await NativePaletteService.get(47);
      expect(NativePaletteService.getSync(47), isNotNull);
      expect(extractCount, 1);

      NativePaletteService.invalidate(47);
      expect(NativePaletteService.getSync(47), isNull);

      nextExtraction = () async => const [
        0xFF010203,
        0xFF040506,
        0xFF070809,
        0xFFAABBCC,
        0xFFDDEEFF,
      ];
      final second = await NativePaletteService.get(47);

      expect(extractCount, 2);
      expect(second, isNot(same(first)));
      expect(second[0].toARGB32(), 0xFF010203);
      expect(NativePaletteService.getSync(47), isNotNull);
    });

    test('an in-flight extraction cannot repopulate the old palette', () async {
      final stale = Completer<List<int>?>();
      nextExtraction = () => stale.future;

      final staleFuture = NativePaletteService.get(48);
      await Future<void>.delayed(Duration.zero);
      expect(extractCount, 1);

      NativePaletteService.invalidate(48);

      final fresh = Completer<List<int>?>();
      nextExtraction = () => fresh.future;
      final freshFuture = NativePaletteService.get(48);
      await Future<void>.delayed(Duration.zero);
      expect(extractCount, 2);

      stale.complete(const [
        0xFF010203,
        0xFF040506,
        0xFF070809,
        0xFFAABBCC,
        0xFFDDEEFF,
      ]);
      fresh.complete(extracted);

      await staleFuture;
      await freshFuture;

      final cached = NativePaletteService.getSync(48);
      expect(cached, isNotNull);
      expect(cached![0].toARGB32(), 0xFF336699);
    });
  });
}
