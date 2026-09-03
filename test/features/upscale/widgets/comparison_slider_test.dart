import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:omega/features/upscale/widgets/comparison_slider.dart';

Uint8List _png(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(100, 150, 200));
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  testWidgets('ComparisonSlider renders before/after layers with interactive split and metadata',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final before = _png(100, 100);
    final after = _png(400, 400);
    var saved = false;
    var shared = false;
    var newImage = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ComparisonSlider(
          beforeBytes: before,
          afterBytes: after,
          inputWidth: 100,
          inputHeight: 100,
          duration: const Duration(milliseconds: 450),
          onSave: () => saved = true,
          onShare: () => shared = true,
          onNewImage: () => newImage = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Verify metadata overlay
    expect(find.textContaining('100 × 100'), findsOneWidget);
    expect(find.textContaining('400 × 400 (4×)'), findsOneWidget);
    expect(find.textContaining('450ms'), findsOneWidget);

    // Verify 'Before' and 'After' chips
    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After (4×)'), findsOneWidget);

    // Verify InteractiveViewer is present
    expect(find.byType(InteractiveViewer), findsOneWidget);

    // Verify Slider is present and draggable
    expect(find.byType(Slider), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(100, 0));
    await tester.pumpAndSettle();

    // Verify Actions
    await tester.tap(find.text('Save to Gallery'));
    await tester.pumpAndSettle();
    expect(saved, true);

    await tester.tap(find.byIcon(LucideIcons.share2));
    await tester.pumpAndSettle();
    expect(shared, true);

    await tester.tap(find.text('New Image'));
    await tester.pumpAndSettle();
    expect(newImage, true);
  });
}
