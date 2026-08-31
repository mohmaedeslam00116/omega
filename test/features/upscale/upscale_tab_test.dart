import 'dart:async';
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
import 'package:omega/core/settings/settings_service.dart';
import 'package:omega/features/upscale/upscale_tab.dart';

Uint8List _png(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(50, 100, 150));
  return Uint8List.fromList(img.encodePng(im));
}

CatalogEntry _entry(String id, {bool bundled = false}) => CatalogEntry(
      id: id,
      name: bundled ? 'Bundled Model' : 'Extra Model',
      scale: 4,
      type: ModelType.general,
      inputSize: 128,
      fileSize: 10,
      sha256: 'abc',
      url: 'https://example.com/$id.tflite',
      license: 'BSD-3-Clause',
      version: '1.0.0',
      bundled: bundled,
    );

class _FakeDownloadManager implements DownloadManager {
  final Set<String> downloaded;
  final List<CatalogEntry> downloadCalls = [];
  Completer<void>? gate;
  _FakeDownloadManager({required this.downloaded, this.gate});

  @override
  Future<File> download(CatalogEntry entry,
      {void Function(double progress)? onProgress,
      bool Function()? isCancelled}) async {
    downloadCalls.add(entry);
    onProgress?.call(0.5);
    final g = gate;
    if (g != null) await g.future;
    downloaded.add(entry.id);
    return File('fake-${entry.id}');
  }

  @override
  Future<bool> isDownloaded(String id) async => downloaded.contains(id);

  @override
  Future<String> pathFor(CatalogEntry entry) async =>
      '/cache/models/${entry.id}.tflite';

  @override
  Future<void> delete(String id) async => downloaded.remove(id);

  @override
  Future<void> clearCache() async => downloaded.clear();

  @override
  Future<int> getCacheSize() async => 0;
}

class _FakeImageIo implements ImageIoService {
  Uint8List? toReturn;
  bool saveCalled = false;
  bool shareCalled = false;
  ({String filename, bool asJpeg, int jpegQuality})? lastSave;
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
      {String? filename,
      bool asJpeg = false,
      int jpegQuality = 90}) async {
    saveCalled = true;
    lastSave = (
      filename: filename ?? 'a.png',
      asJpeg: asJpeg,
      jpegQuality: jpegQuality
    );
    return 'gallery:${filename ?? 'a.png'}';
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
        body: UpscaleTab(imageIo: fakeIo, runner: runner, downloadManager: _FakeDownloadManager(downloaded: {})),
      ),
    ));

    expect(find.text('No image selected'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    // Round 4 UX polish: no debug scaffolding on the upscaling surface.
    expect(find.text('Verify bundled Model'), findsNothing);

    // Tap Gallery
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('Upscale disabled while the selected Model downloads',
      (tester) async {
    final gate = Completer<void>();
    final fakeIo = _FakeImageIo(_png(64, 64));
    final dl = _FakeDownloadManager(downloaded: {}, gate: gate);
    final runner = _FakeRunner((img, config, p, token) async => _png(200, 200));
    final catalog = [
      _entry('bundled-model', bundled: true),
      _entry('extra-model'),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpscaleTab(
          imageIo: fakeIo,
          runner: runner,
          downloadManager: dl,
          catalog: catalog,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<CatalogEntry>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Extra Model').last);
    await tester.pump();

    // Download is gated open -> still in progress, button disabled.
    final btn = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Upscale 4×'));
    expect(btn.onPressed, isNull);

    gate.complete();
    await tester.pumpAndSettle();
    final btn2 = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Upscale 4×'));
    expect(btn2.onPressed, isNotNull);
  });

  testWidgets('Model selection drives the job modelPath (downloaded Model)',
      (tester) async {
    final fakeIo = _FakeImageIo(_png(64, 64));
    final dl = _FakeDownloadManager(downloaded: {'extra-model'});
    final runner = _FakeRunner((img, config, prog, token) async {
      prog?.call(1.0);
      return _png(256, 256);
    });
    final catalog = [
      _entry('bundled-model', bundled: true),
      _entry('extra-model'),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpscaleTab(
          imageIo: fakeIo,
          runner: runner,
          downloadManager: dl,
          catalog: catalog,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<CatalogEntry>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Extra Model').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upscale 4×'));
    await tester.pumpAndSettle();

    expect(runner.lastConfig?.modelPath, '/cache/models/extra-model.tflite');
  });

  testWidgets('Selecting a missing Model auto-downloads it with progress',
      (tester) async {
    final fakeIo = _FakeImageIo(_png(64, 64));
    final dl = _FakeDownloadManager(downloaded: {});
    final runner = _FakeRunner((img, config, prog, token) async {
      prog?.call(1.0);
      return _png(256, 256);
    });
    final catalog = [
      _entry('bundled-model', bundled: true),
      _entry('extra-model'),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpscaleTab(
          imageIo: fakeIo,
          runner: runner,
          downloadManager: dl,
          catalog: catalog,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<CatalogEntry>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Extra Model').last);
    await tester.pump();

    expect(dl.downloadCalls.map((e) => e.id), contains('extra-model'));

    await tester.pumpAndSettle();
    await tester.tap(find.text('Upscale 4×'));
    await tester.pumpAndSettle();

    expect(runner.lastConfig?.modelPath, '/cache/models/extra-model.tflite');
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
      home: Scaffold(body: UpscaleTab(imageIo: fakeIo, runner: runner, downloadManager: _FakeDownloadManager(downloaded: {}))),
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
      home: Scaffold(body: UpscaleTab(imageIo: fakeIo, runner: runner, downloadManager: _FakeDownloadManager(downloaded: {}))),
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
        body: UpscaleTab(imageIo: fakeIo, runner: runner, downloadManager: _FakeDownloadManager(downloaded: {}), useGpu: true),
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

  testWidgets('Friendly memory-guard error surfaces in the tab',
      (tester) async {
    final bytes = _png(64, 64);
    final fakeIo = _FakeImageIo(bytes);
    final runner = _FakeRunner((img, config, prog, token) async {
      throw const MemoryEstimateExceededException(4456448, 52428800);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UpscaleTab(imageIo: fakeIo, runner: runner, downloadManager: _FakeDownloadManager(downloaded: {}))),
    ));
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upscale 4×'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('too large'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('Try a smaller image'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Save sheet: JPEG choice reaches ImageIo and persists prefs',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = await SettingsService.init();
    final fakeIo = _FakeImageIo(_png(64, 64));
    final runner = _FakeRunner((img, config, prog, token) async {
      prog?.call(1.0);
      return _png(256, 256);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpscaleTab(
          imageIo: fakeIo,
          runner: runner,
          downloadManager: _FakeDownloadManager(downloaded: {}),
          settingsService: settings,
        ),
      ),
    ));
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upscale 4×'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save to Gallery'));
    await tester.pumpAndSettle();
    expect(find.text('Save image'), findsOneWidget);
    expect(find.text('PNG'), findsOneWidget);
    expect(find.text('JPEG'), findsOneWidget);
    // PNG default -> no quality slider
    expect(find.byKey(const ValueKey('jpegQuality')), findsNothing);

    await tester.tap(find.text('JPEG'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('jpegQuality')), findsOneWidget);

    await tester.tap(find.text('Save image'));
    await tester.pumpAndSettle();

    expect(fakeIo.saveCalled, true);
    expect(fakeIo.lastSave?.asJpeg, true);
    expect(fakeIo.lastSave?.filename, 'omega_upscaled.jpg');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('saveFormat'), 'jpeg');
    expect(prefs.getInt('jpegQuality'), 90);
  });

  testWidgets('Save sheet recalls the remembered format and quality',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{'saveFormat': 'jpeg', 'jpegQuality': 70});
    final settings = await SettingsService.init();
    final fakeIo = _FakeImageIo(_png(64, 64));
    final runner = _FakeRunner((img, config, prog, token) async {
      prog?.call(1.0);
      return _png(256, 256);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpscaleTab(
          imageIo: fakeIo,
          runner: runner,
          downloadManager: _FakeDownloadManager(downloaded: {}),
          settingsService: settings,
        ),
      ),
    ));
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upscale 4×'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save to Gallery'));
    await tester.pumpAndSettle();
    // Remembered: JPEG selected -> quality slider shows the stored value.
    expect(find.byKey(const ValueKey('jpegQuality')), findsOneWidget);
    final slider = tester.widget<Slider>(find.byKey(const ValueKey('jpegQuality')));
    expect(slider.value, 70);

    await tester.tap(find.text('Save image'));
    await tester.pumpAndSettle();
    expect(fakeIo.lastSave?.asJpeg, true);
    expect(fakeIo.lastSave?.jpegQuality, 70);
    expect(fakeIo.lastSave?.filename, 'omega_upscaled.jpg');
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
      home: Scaffold(
        body: UpscaleTab(
          imageIo: fakeIo,
          runner: runner,
          downloadManager: _FakeDownloadManager(downloaded: {}),
          settingsService: await SettingsService.init(),
        ),
      ),
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
    // The save sheet opens; confirm with the default (PNG).
    await tester.tap(find.text('Save image'));
    await tester.pumpAndSettle();
    expect(fakeIo.saveCalled, true);

    // Let the "Saved" SnackBar auto-dismiss — it docks over the Share button.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(fakeIo.shareCalled, true);
  });

  testWidgets(
      'Before/After comparison handles images without RenderFlex overflow',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final inBytes = _png(80, 80);
    final outBytes = _png(160, 160);
    final fakeIo = _FakeImageIo(inBytes);
    final runner = _FakeRunner((img, config, p, token) async {
      p?.call(1.0);
      return outBytes;
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpscaleTab(
          imageIo: fakeIo,
          runner: runner,
          downloadManager: _FakeDownloadManager(downloaded: {}),
          settingsService: await SettingsService.init(),
        ),
      ),
    ));
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upscale 4×'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After'), findsOneWidget);
  });
}