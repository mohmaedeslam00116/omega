import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import '../catalog/catalog_entry.dart';
import '../download/download_manager.dart';
import '../engine/engine_factory.dart';
import '../engine/tflite_engine.dart';
import '../preset/human_friendly_preset.dart';
import 'cascaded_pipeline.dart';

/// Result of an upscale execution.
class UpscaleResult {
  final Uint8List outputBytes;
  final int outputWidth;
  final int outputHeight;
  final Duration duration;

  const UpscaleResult({
    required this.outputBytes,
    required this.outputWidth,
    required this.outputHeight,
    required this.duration,
  });
}

/// A deep module orchestrating model bundle resolution, delta downloading,
/// multi-stage engine initialization, and cascaded execution behind a simple interface.
abstract class UpscaleCoordinator {
  Future<UpscaleResult> processImage({
    required Uint8List inputBytes,
    required PresetContentType contentType,
    required PresetQualityTier qualityTier,
    required List<CatalogEntry> catalog,
    required bool useGpu,
    void Function(StageProgress progress)? onStageProgress,
    void Function(double downloadProgress)? onDownloadProgress,
    bool Function()? isCancelled,
  });
}

class UpscaleCoordinatorImpl implements UpscaleCoordinator {
  final DownloadManager downloadManager;
  final TfliteEngine Function(String modelPath)? engineCreator;

  const UpscaleCoordinatorImpl({
    required this.downloadManager,
    this.engineCreator,
  });

  @override
  Future<UpscaleResult> processImage({
    required Uint8List inputBytes,
    required PresetContentType contentType,
    required PresetQualityTier qualityTier,
    required List<CatalogEntry> catalog,
    required bool useGpu,
    void Function(StageProgress progress)? onStageProgress,
    void Function(double downloadProgress)? onDownloadProgress,
    bool Function()? isCancelled,
  }) async {
    final stopwatch = Stopwatch()..start();

    // 1. Resolve Best Model / Bundle
    final selectedEntry = PresetResolver.resolveBestModel(
      catalog: catalog,
      contentType: contentType,
      qualityTier: qualityTier,
      useGpu: useGpu,
    );

    // 2. Ensure model file is downloaded
    final modelPath = await downloadManager.pathFor(selectedEntry);
    final modelFile = File(modelPath);
    final isDownloaded = await downloadManager.isDownloaded(selectedEntry.id);

    if (!selectedEntry.bundled && (!isDownloaded || !modelFile.existsSync())) {
      await downloadManager.download(
        selectedEntry,
        onProgress: onDownloadProgress,
        isCancelled: isCancelled,
      );
    }

    // 3. Initialize Engine
    final engine = engineCreator != null
        ? engineCreator!(modelPath)
        : EngineFactory.createForModel(modelPath);

    await engine.setUseGpu(useGpu);
    await engine.load(modelPath);

    try {
      // 4. Run Pipeline Stage
      final pipeline = CascadedPipeline(
        stages: [
          PipelineStage(
            id: selectedEntry.id,
            name: selectedEntry.name,
            role: selectedEntry.role,
            engine: engine,
            scale: selectedEntry.scale,
            inputSize: selectedEntry.inputSize,
          ),
        ],
      );

      final outPng = await pipeline.process(
        inputBytes,
        onProgress: onStageProgress,
        isCancelled: isCancelled,
      );

      stopwatch.stop();

      final decoded = img.decodeImage(outPng);
      final outW = decoded?.width ?? 0;
      final outH = decoded?.height ?? 0;

      return UpscaleResult(
        outputBytes: outPng,
        outputWidth: outW,
        outputHeight: outH,
        duration: stopwatch.elapsed,
      );
    } finally {
      await engine.close();
    }
  }
}
