import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/services/log_service.dart';
import 'package:musicplayer/services/native_palette_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    LogService.loggingEnabled.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      throw PlatformException(code: 'test_path_provider_failure');
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  test('palette warm-up failure stays silent while logging is disabled', () async {
    final printed = <String?>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      printed.add(message);
    };

    try {
      await NativePaletteService.warmUp();
      expect(printed, isEmpty);
    } finally {
      debugPrint = previousDebugPrint;
    }
  });
}
