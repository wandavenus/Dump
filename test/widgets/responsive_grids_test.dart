import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/l10n/app_localizations.dart';
import 'package:musicplayer/pages/search_page.dart';
import 'package:musicplayer/themes/app_themes.dart';

const List<Locale> _locales = [Locale('en'), Locale('id')];

const List<LocalizationsDelegate<Object>> _delegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// Reads the column count of the first adaptive grid rendered on screen.
int _columns(WidgetTester tester) {
  final grid = tester.widget<SliverGrid>(find.byType(SliverGrid).first);
  final delegate = grid.gridDelegate;
  expect(delegate, isA<SliverGridDelegateWithFixedCrossAxisCount>());
  return (delegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisCount;
}

Future<void> _pumpSearch(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemes.dark,
      localizationsDelegates: _delegates,
      supportedLocales: _locales,
      home: const SearchPage(),
    ),
  );
  await tester.pump();
}

/// MediaStore is a platform channel that has no implementation in the test
/// environment. Mocking it keeps the page's library load synchronous instead of
/// leaving the service's 20 s timeout timer pending.
void _mockMediaStore() {
  const channel = MethodChannel('musicplayer/media_store');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async => null);
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_mockMediaStore);

  testWidgets('search category grid keeps 2 columns in portrait', (
    tester,
  ) async {
    await _pumpSearch(tester, const Size(393, 852));
    expect(find.byType(SliverGrid), findsWidgets);
    expect(_columns(tester), 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search category grid widens to 4 columns in landscape', (
    tester,
  ) async {
    await _pumpSearch(tester, const Size(800, 360));
    expect(find.byType(SliverGrid), findsWidgets);
    expect(_columns(tester), 4);
    expect(tester.takeException(), isNull);
  });
}
