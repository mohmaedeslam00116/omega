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

  testWidgets('RootShell shows three tabs with Material 3 navigation', (
    tester,
  ) async {
    final catalogService = CatalogServiceStub('''[
      {
        "id": "realesr-general-x4v3",
        "name": "General Photo 4×",
        "scale": 4,
        "type": "general",
        "inputSize": 128,
        "fileSize": 10,
        "sha256": "abc",
        "url": "https://example.com/a.tflite",
        "license": "BSD-3-Clause",
        "version": "1.0.0",
        "bundled": true
      }
    ]''');

    await tester.pumpWidget(OmegaApp(catalogService: catalogService));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Upscale'), findsWidgets);
    expect(find.text('Models'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);

    // Tap Models tab (Destination index 1)
    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('General Photo 4×'), findsWidgets);

    // Tap Settings tab (Destination index 2)
    await tester.tap(find.byType(NavigationDestination).at(2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Theme Mode'), findsOneWidget);

    // Back to Upscale (Destination index 0)
    await tester.tap(find.byType(NavigationDestination).at(0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('No image selected'), findsOneWidget);
  });

  testWidgets('Bundled asset is declared and loadable', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final data = await rootBundle.load('assets/NOTICES');
    expect(data.lengthInBytes, greaterThan(0));
  });
}
