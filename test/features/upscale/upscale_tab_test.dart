import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:omega/core/engine/tflite_engine.dart';
import 'package:omega/core/image/image_io_service.dart';
import 'package:omega/core/pipeline/upscale_pipeline.dart';
import 'package:omega/features/upscale/upscale_tab.dart';

Uint8List _png(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(50, 100, 150));
  return Uint8List.fromList(img.encodePng(im));
}

class _FakeImageIo implements ImageIoService {
  Uint8List? toReturn;
  bool saveCalled = false;
  bool shareCalled = false;
  _FakeImageIo(this.toReturn);
  @override
  Future<Uint8List?> pickFromGallery() async => toReturn;
  @override
  Future<Uint8List?> pickFromCamera() async => toReturn;
  @override
  Future<Uint8List?> getInitialSharedImage() async => null;
  @override
  Stream<Uint8List?> get sharedImageStream => const Stream.empty();
  @override
  Future<void> validate(Uint8List bytes) async {}
  @override
  Future<String> saveToGallery(Uint8List bytes,
          {String filename = 'a.png', bool asJpeg = false}) async {
    saveCalled = true;
    return 'gallery:$filename';
  }

  @override
  Future<void> shareImage(Uint8List bytes,
      {String filename = 'a.png'}) async {
    shareCalled = true;
  }
}

class _FakeEngine implements TfliteEngine {
  bool _loaded = true;
  @override
  bool get isLoaded => _loaded;
  @override
  bool get useGpu => false;
  void setLoaded(bool v) => _loaded = v;
  @override
  Future<void> close() async => _loaded = false;
  @override
  Future<void> load(String p) async => _loaded = true;
  @override
  Future<void> setUseGpu(bool v) async {}
  @override
  Future<Uint8List> infer(Uint8List tileBytes) async =>
      Uint8List.fromList([...tileBytes, ...tileBytes]);
}

class _NeverReadyEngine implements TfliteEngine {
  @override
  bool get isLoaded => false;
  @override
  bool get useGpu => false;
  @override
  Future<void> close() async {}
  @override
  Future<void> load(String p) async {}
  @override
  Future<void> setUseGpu(bool v) async {}
  @override
  Future<Uint8List> infer(Uint8List tileBytes) async =>
      Uint8List.fromList(tileBytes);
}

class _FakePipeline extends UpscalePipeline {
  final Future<Uint8List> Function(Uint8List, void Function(double)?) _fn;
  _FakePipeline(this._fn) : super(engine: _FakeEngine());

  @override
  Future<Uint8List> upscale(Uint8List imageBytes,
      {void Function(double progress)? onProgress}) {
    return _fn(imageBytes, onProgress);
  }
}

void main() {
  testWidgets('Empty state with pick CTA; after pick, preview shows',
      (tester) async {
    final bytes = _png(100, 100);
    final fakeIo = _FakeImageIo(bytes);
    final fakePipeline = _FakePipeline((img, prog) async {
      prog?.call(1.0);
      return _png(400, 400);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpscaleTab(
          imageIo: fakeIo,
          pipeline: fakePipeline,
          engine: _FakeEngine(),
        ),
      ),
    ));

    expect(find.text('No image selected'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);

    // Tap Gallery
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('Upscale button disabled if engine not ready', (tester) async {
    final bytes = _png(50, 50);
    final fakeIo = _FakeImageIo(bytes);
    final engineNotReady = _NeverReadyEngine();
    final pipeline = _FakePipeline((img, p) async => _png(200, 200));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpscaleTab(
          imageIo: fakeIo,
          pipeline: pipeline,
          engine: engineNotReady,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Gallery'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final btn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Upscale 4×'));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Progress bar advances; UI remains responsive', (tester) async {
    final bytes = _png(128, 128);
    final fakeIo = _FakeImageIo(bytes);
    final pipeline = _FakePipeline((img, prog) async {
      for (var i = 1; i <= 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        prog?.call(i / 4);
      }
      return _png(512, 512);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UpscaleTab(imageIo: fakeIo, pipeline: pipeline)),
    ));
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upscale 4×'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // Let it complete
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('After complete, slider compares before/after and Save/Share succeed',
      (tester) async {
    final inBytes = _png(20, 20);
    final outBytes = _png(80, 80);
    final fakeIo = _FakeImageIo(inBytes);
    final pipeline = _FakePipeline((img, p) async {
      p?.call(1.0);
      return outBytes;
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UpscaleTab(imageIo: fakeIo, pipeline: pipeline)),
    ));
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upscale 4×'));
    await tester.pumpAndSettle();

    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('Save to Gallery'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);

    await tester.tap(find.text('Save to Gallery'));
    await tester.pumpAndSettle();
    expect(fakeIo.saveCalled, true);

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(fakeIo.shareCalled, true);
  });
}
