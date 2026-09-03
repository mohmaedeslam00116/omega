import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:omega/features/upscale/models/batch_item.dart';
import 'package:omega/features/upscale/widgets/batch_queue_carousel.dart';

Uint8List _png(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(120, 180, 240));
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  testWidgets('BatchQueueCarousel displays items with status badges and selection',
      (tester) async {
    final item1 = BatchItem(
      id: '1',
      inputBytes: _png(64, 64),
      status: BatchItemStatus.completed,
    );
    final item2 = BatchItem(
      id: '2',
      inputBytes: _png(64, 64),
      status: BatchItemStatus.processing,
      progress: 0.6,
    );
    final item3 = BatchItem(
      id: '3',
      inputBytes: _png(64, 64),
      status: BatchItemStatus.pending,
    );

    int selectedIdx = 0;
    var addCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BatchQueueCarousel(
          items: [item1, item2, item3],
          selectedIndex: selectedIdx,
          onSelect: (idx) => selectedIdx = idx,
          onAddMore: () => addCalled = true,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Verify all 3 thumbnail items are present
    expect(find.byType(Image), findsNWidgets(3));

    // Verify status icons
    expect(find.byIcon(LucideIcons.check), findsOneWidget); // completed
    expect(find.byType(CircularProgressIndicator), findsOneWidget); // processing
    expect(find.byIcon(LucideIcons.clock), findsOneWidget); // pending

    // Tap item 2
    await tester.tap(find.byType(Image).at(1));
    await tester.pump();
    expect(selectedIdx, 1);

    // Tap Add More
    await tester.tap(find.byIcon(LucideIcons.imagePlus));
    await tester.pump();
    expect(addCalled, true);
  });
}
