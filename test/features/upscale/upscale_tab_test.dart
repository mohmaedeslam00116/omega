import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:omega/core/image/image_io_service.dart';
import 'package:omega/core/pipeline/upscale_job_runner.dart';
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

class _FakeRunner implements UpscaleJobRunner {
  final Future<Uint8List> Function(
    Uint8List bytes,
    UpscaleJobConfig config,
    void Function(double)? onProgress,
    CancelToken? token,
  ) _fn;
  CancelToken? lastToken;
  UpscaleJobConfig? lastConfig;
  _FakeRunner(this._fn);

  @override
  Future<Uint8List> run(
    Uint8List imageBytes, {
    required UpscaleJobConfig config,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    lastToken = cancelToken;
    lastConfig = config;
    return _fn(imageBytes, config, onProgress, cancelToken);
  }
}

void main() {
  testWidgets('Empty state with pick CTA; after pick, preview shows',
      (tester) async {
    final bytes = _png(100, 100);
    final fakeIo = _FakeImageIo(bytes);
    final runner = _FakeRunner((img, config, prog, token) async {
      prog?.call(1.0);
      return _png(400, 400);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpscaleTab(imageIo: fakeIo, runner: runner),
      ),
    ));

    expect(find.text('No image selected'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);

    // Tap Gallery
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('Upscale button disabled if Model not ready', (tester) async {
    final bytes = _png(50, 50);
    final fakeIo = _FakeImageIo(bytes);
    final runner = _FakeRunner((img, config, p, token) async => _png(200, 200));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpscaleTab(
          imageIo: fakeIo,
          runner: runner,
          modelPath: 'assets/models/missing.tflite',
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Gallery'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final btn = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Upscale 4×'));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Progress advances, Cancel appears, job completes',
      (tester) async {
    final bytes = _png(128, 128);
    final fakeIo = _FakeImageIo(bytes);
    final runner = _FakeRunner((img, config, prog, token) async {
      for (var i = 1; i <= 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        prog?.call(i / 4);
      }
      return _png(512, 512);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UpscaleTab(imageIo: fakeIo, runner: runner)),
    ));
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upscale 4×'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    // Let it complete
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('Cancel button stops the job cleanly', (tester) async {
    final bytes = _png(128, 128);
    final fakeIo = _FakeImageIo(bytes);
    final runner = _FakeRunner((img, config, prog, token) async {
      prog?.call(0.2);
      final cancelled = Completer<void>();
      token?.addListener(cancelled.complete);
      await cancelled.future;
      throw const UpscaleCancelledException();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UpscaleTab(imageIo: fakeIo, runner: runner)),
    ));
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upscale 4×'));
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Back to the preview action, no progress, no error SnackBar.
    expect(find.text('Upscale 4×'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Job config carries the model path and GPU flag', (tester) async {
    final bytes = _png(64, 64);
    final fakeIo = _FakeImageIo(bytes);
    final runner = _FakeRunner((img, config, prog, token) async {
      prog?.call(1.0);
      return _png(256, 256);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpscaleTab(imageIo: fakeIo, runner: runner, useGpu: true),
      ),
    ));
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upscale 4×'));
    await tester.pumpAndSettle();

    expect(runner.lastConfig?.modelPath,
        'assets/models/realesr-general-x4v3_fp16.tflite');
    expect(runner.lastConfig?.useGpu, true);
    expect(runner.lastToken, isNotNull);
  });

  testWidgets(
      'After complete, slider compares before/after and Save/Share succeed',
      (tester) async {
    final inBytes = _png(20, 20);
    final outBytes = _png(80, 80);
    final fakeIo = _FakeImageIo(inBytes);
    final runner = _FakeRunner((img, config, p, token) async {
      p?.call(1.0);
      return outBytes;
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UpscaleTab(imageIo: fakeIo, runner: runner)),
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