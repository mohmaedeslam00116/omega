import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omega/core/catalog/catalog_service.dart';
import 'package:omega/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('RootShell shows SuperImage-style single screen with Settings action', (
    tester,
  ) async {
    final catalogService = CatalogServiceStub('''[
      {
        "id": "safmn-x4-int8",
        "name": "SAFMN 4x",
        "scale": 4,
        "type": "anime",
        "inputSize": 128,
        "fileSize": 10,
        "sha256": "abc",
        "url": "https://example.com/a.mnn",
        "license": "GPL-3.0",
        "version": "1.0.0",
        "bundled": true
      }
    ]''');

    await tester.pumpWidget(OmegaApp(catalogService: catalogService));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Omega'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    // Tap Settings icon in AppBar
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Theme Mode'), findsOneWidget);

    // Pop back to Upscale
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('No image selected'), findsOneWidget);
  });

  testWidgets('Bundled asset is declared and loadable', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final data = await rootBundle.load('assets/NOTICES');
    expect(data.lengthInBytes, greaterThan(0));
  });
}
