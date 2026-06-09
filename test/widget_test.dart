import 'package:flutter_test/flutter_test.dart';
import 'package:musicplayer/main.dart';

void main() {
  testWidgets('renders the main navigation shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('Beranda'), findsWidgets);
    expect(find.text('Baru'), findsOneWidget);
    expect(find.text('Radio'), findsOneWidget);
    expect(find.text('Perpustakaan'), findsOneWidget);
    expect(find.text('Cari'), findsOneWidget);
  });
}
