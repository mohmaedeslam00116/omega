import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omega/core/catalog/catalog_entry.dart';
import 'package:omega/core/download/download_manager.dart';
import 'package:omega/core/image/image_io_service.dart';
import 'package:omega/core/pipeline/upscale_job_runner.dart';
import 'package:omega/core/pipeline/upscale_pipeline.dart';
import 'package:omega/features/upscale/upscale_tab.dart';
import 'package:omega/features/upscale/widgets/batch_queue_carousel.dart';

Uint8List _png(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(100, 150, 200));
  return Uint8List.fromList(img.encodePng(im));
}

class _MultiImageIo implements ImageIoService {
  final List<Uint8List> multipleToReturn;
  bool saveCalled = false;
  _MultiImageIo(this.multipleToReturn);

  @override
  Future<Uint8List?> pickFromGallery() async =>
      multipleToReturn.isNotEmpty ? multipleToReturn.first : null;

  @override
  Future<List<Uint8List>> pickMultipleFromGallery() async => multipleToReturn;

  @override
  Future<Uint8List?> pickFromCamera() async => null;
  @override
  Future<Uint8List?> getInitialSharedImage() async => null;
  @override
  Stream<Uint8List?> get sharedImageStream => const Stream.empty();
  @override
  Future<void> validate(Uint8List bytes) async {}
  @override
  Future<String> saveToGallery(Uint8List bytes,
      {String? filename,
      bool asJpeg = false,
      int jpegQuality = 90,
      OutputImageFormat format = OutputImageFormat.png}) async {
    saveCalled = true;
    return 'saved';
  }

  @override
  Future<void> shareImage(Uint8List bytes, {String filename = 'a.png'}) async {}
}

class _FakeRunner implements UpscaleJobRunner {
  int runCalls = 0;
  @override
  Future<Uint8List> run(
    Uint8List imageBytes, {
    required UpscaleJobConfig config,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    runCalls++;
    onProgress?.call(1.0);
    return _png(256, 256);
  }
}

class _DummyDl implements DownloadManager {
  @override
  Future<File> download(CatalogEntry entry, {void Function(double progress)? onProgress, bool Function()? isCancelled}) async => File('fake');
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> clearCache() async {}
  @override
  Future<int> getCacheSize() async => 0;
  @override
  Future<bool> isDownloaded(String id) async => true;
  @override
  Future<String> pathFor(CatalogEntry entry) async => 'fake';
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Multi-image pick displays BatchQueueCarousel and Upscale All processes all items',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final img1 = _png(64, 64);
    final img2 = _png(64, 64);
    final fakeIo = _MultiImageIo([img1, img2]);
    final runner = _FakeRunner();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpscaleTab(
          imageIo: fakeIo,
          runner: runner,
          downloadManager: _DummyDl(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Tap Gallery
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();

    // Verify BatchQueueCarousel appears with 2 items
    expect(find.byType(BatchQueueCarousel), findsOneWidget);
    expect(find.text('Upscale All (2)'), findsOneWidget);

    // Tap Upscale All
    await tester.tap(find.text('Upscale All (2)'));
    await tester.pumpAndSettle();

    // Runner should have been called twice (once for each image)
    expect(runner.runCalls, 2);
  });
}
