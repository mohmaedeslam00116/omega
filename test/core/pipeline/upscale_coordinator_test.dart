import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:omega/core/catalog/catalog_entry.dart';
import 'package:omega/core/download/download_manager.dart';
import 'package:omega/core/engine/tflite_engine.dart';
import 'package:omega/core/pipeline/cascaded_pipeline.dart';
import 'package:omega/core/pipeline/upscale_coordinator.dart';
import 'package:omega/core/preset/human_friendly_preset.dart';

class _FakeDownloadManager implements DownloadManager {
  int downloadCalls = 0;
  final Directory tempDir;

  _FakeDownloadManager(this.tempDir);

  @override
  Future<File> download(CatalogEntry entry,
      {void Function(double progress)? onProgress,
      bool Function()? isCancelled}) async {
    downloadCalls++;
    onProgress?.call(1.0);
    final f = File('\${tempDir.path}/\${entry.id}.tflite');
    f.writeAsStringSync('fake_model');
    return f;
  }

  @override
  Future<String> pathFor(CatalogEntry entry) async {
    return '\${tempDir.path}/\${entry.id}.tflite';
  }

  @override
  Future<bool> isDownloaded(String id) async => true;
  @override
  Future<int> getCacheSize() async => 0;
  @override
  Future<void> delete(String modelId) async {}
  @override
  Future<void> clearCache() async {}
}

Uint8List _makePng(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(100, 150, 200));
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  group('UpscaleCoordinator', () {
    late Directory tempModelsDir;
    late _FakeDownloadManager downloadManager;

    setUp(() {
      tempModelsDir = Directory.systemTemp.createTempSync('omega_models_dir');
      downloadManager = _FakeDownloadManager(tempModelsDir);
    });

    tearDown(() {
      try {
        tempModelsDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('orchestrates model resolution, download, and cascaded execution end-to-end', () async {
      final coordinator = UpscaleCoordinatorImpl(
        downloadManager: downloadManager,
        engineCreator: (_) => TfliteEngineStub(),
      );

      final catalog = [
        const CatalogEntry(
          id: 'test-model',
          name: 'Test Fast Model',
          scale: 4,
          type: ModelType.general,
          backend: EngineBackend.tflite,
          tier: ModelTier.fast,
          inputSize: 128,
          fileSize: 100,
          sha256: 'abc',
          url: 'https://example.com/model.tflite',
          license: 'MIT',
          version: '1.0.0',
          bundled: true,
        ),
      ];

      final input = _makePng(128, 128);
      final stageProgresses = <StageProgress>[];

      final result = await coordinator.processImage(
        inputBytes: input,
        contentType: PresetContentType.photo,
        qualityTier: PresetQualityTier.lightning,
        catalog: catalog,
        useGpu: false,
        onStageProgress: stageProgresses.add,
      );

      expect(result.outputWidth, 512);
      expect(result.outputHeight, 512);
      expect(result.duration.inMilliseconds, greaterThanOrEqualTo(0));
      expect(stageProgresses, isNotEmpty);
    });
  });
}
