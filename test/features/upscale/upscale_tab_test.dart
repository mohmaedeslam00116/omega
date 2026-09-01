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

CatalogEntry _entry(
  String id, {
  bool bundled = false,
  ModelType type = ModelType.general,
  ModelTier tier = ModelTier.fast,
  EngineBackend backend = EngineBackend.tflite,
}) =>
    CatalogEntry(
      id: id,
      name: bundled ? 'Bundled Model' : 'Extra Model',
      scale: 4,
      type: type,
      backend: backend,
      tier: tier,
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
  Future<List<Uint8List>> pickMultipleFromGallery() async =>
      toReturn != null ? [toReturn!] : [];
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
      int jpegQuality = 90,
      OutputImageFormat format = OutputImageFormat.png}) async {
    saveCalled = true;
    lastSave = (
      filename: filename ?? 'a.png',
      asJpeg: asJpeg || format == OutputImageFormat.jpeg,
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Empty state with pick CTA; after pick, preview and dimensions show',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
    expect(find.text('Verify bundled Model'), findsNothing);

    // Tap Gallery
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);
    expect(find.text('100 × 100'), findsOneWidget);
    expect(find.text('400 × 400 (4×)'), findsOneWidget);
  });

  testWidgets('Preset selection drives the resolved modelPath (downloaded Model)',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fakeIo = _FakeImageIo(_png(64, 64));
    final dl = _FakeDownloadManager(downloaded: {'anime-model'});
    final runner = _FakeRunner((img, config, prog, token) async {
      prog?.call(1.0);
      return _png(256, 256);
    });
    final catalog = [
      _entry('bundled-photo', bundled: true, type: ModelType.general, tier: ModelTier.fast),
      _entry('anime-model', bundled: false, type: ModelType.anime, tier: ModelTier.fast),
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

    // Tap Art & Anime preset
    await tester.tap(find.text('Art & Anime'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upscale 4×'));
    await tester.pumpAndSettle();

    expect(runner.lastConfig?.modelPath, '/cache/models/anime-model.tflite');
  });

  testWidgets('Selecting a preset with missing Model auto-downloads it on upscale',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fakeIo = _FakeImageIo(_png(64, 64));
    final dl = _FakeDownloadManager(downloaded: {});
    final runner = _FakeRunner((img, config, prog, token) async {
      prog?.call(1.0);
      return _png(256, 256);
    });
    final catalog = [
      _entry('bundled-photo', bundled: true, type: ModelType.general, tier: ModelTier.fast),
      _entry('anime-model', bundled: false, type: ModelType.anime, tier: ModelTier.fast),
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

    await tester.tap(find.text('Art & Anime'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Upscale 4×'));
    await tester.pumpAndSettle();

    expect(dl.downloadCalls.map((e) => e.id), contains('anime-model'));
    expect(runner.lastConfig?.modelPath, '/cache/models/anime-model.tflite');
  });

  testWidgets('Progress advances, Cancel appears, job completes',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final bytes = _png(64, 64);
    final fakeIo = _FakeImageIo(bytes);
    final runner = _FakeRunner((img, config, prog, token) async {
      prog?.call(1.0);
      return _png(256, 256);
    });

    final catalog = [
      _entry('bundled-photo', bundled: true, type: ModelType.general, tier: ModelTier.fast),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpscaleTab(
          imageIo: fakeIo,
          runner: runner,
          downloadManager: _FakeDownloadManager(downloaded: {}),
          catalog: catalog,
          useGpu: true,
        ),
      ),
    ));
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upscale 4×'));
    await tester.pumpAndSettle();

    expect(runner.lastConfig?.modelPath,
        'assets/models/bundled-photo_fp16.tflite');
    expect(runner.lastConfig?.useGpu, true);
    expect(runner.lastToken, isNotNull);
  });

  testWidgets('Friendly memory-guard error surfaces in the tab',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final bytes = _png(64, 64);
    final fakeIo = _FakeImageIo(bytes);
    final runner = _FakeRunner((img, config, prog, token) async {
      throw const MemoryEstimateExceededException(4456448, 52428800);
    });

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: UpscaleTab(
          imageIo: fakeIo,
          runner: runner,
          settingsService: SettingsService(prefs),
          downloadManager: _FakeDownloadManager(downloaded: {}),
        ),
      ),
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
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

    // Switch to JPEG -> quality slider appears at default 90%
    await tester.tap(find.text('JPEG'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('jpegQuality')), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);

    // Tap Save
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fakeIo.saveCalled, true);
    expect(fakeIo.lastSave?.asJpeg, true);
    expect(fakeIo.lastSave?.jpegQuality, 90);
    expect(settings.saveFormat, 'jpeg');
    expect(settings.jpegQuality, 90);
  });

  testWidgets('Save sheet recalls the remembered format and quality',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'saveFormat': 'jpeg',
      'jpegQuality': 70,
    });
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

    // Remembers JPEG + 70%
    expect(find.byKey(const ValueKey('jpegQuality')), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);

    // Tap Save
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fakeIo.saveCalled, true);
    expect(fakeIo.lastSave?.asJpeg, true);
    expect(fakeIo.lastSave?.jpegQuality, 70);
  });

  testWidgets(
      'After complete, slider compares before/after and Save/Share succeed',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final bytes = _png(64, 64);
    final fakeIo = _FakeImageIo(bytes);
    final runner = _FakeRunner((img, config, prog, token) async => _png(256, 256));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UpscaleTab(imageIo: fakeIo, runner: runner, downloadManager: _FakeDownloadManager(downloaded: {}))),
    ));
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upscale 4×'));
    await tester.pumpAndSettle();

    // After upscale finishes, slider is visible
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After (4×)'), findsOneWidget);

    // Save to Gallery
    await tester.tap(find.text('Save to Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fakeIo.saveCalled, true);

    // Share
    await tester.tap(find.byIcon(Icons.share_rounded));
    await tester.pumpAndSettle();
    expect(fakeIo.shareCalled, true);
  });
}