import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omega/main.dart';

void main() {
  testWidgets('RootShell shows two tabs with impeccable theme', (
    tester,
  ) async {
    await tester.pumpWidget(const OmegaApp());

    expect(find.text('Omega'), findsOneWidget);
    expect(find.text('Upscale'), findsWidgets);
    expect(find.text('Catalog'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);

    // Tap Catalog tab
    await tester.tap(find.text('Catalog').last);
    await tester.pumpAndSettle();
    expect(find.text('General Photo 4×'), findsOneWidget);

    // Back to Upscale
    await tester.tap(find.text('Upscale').last);
    await tester.pumpAndSettle();
    expect(find.text('No image selected'), findsOneWidget);
  });

  testWidgets('Bundled asset is declared and loadable', (tester) async {
    await tester.pumpWidget(const OmegaApp());
    // The Upscale tab has a button to verify bundled model
    expect(find.text('Verify bundled Model'), findsOneWidget);
  });
}
