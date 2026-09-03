import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import '../catalog/catalog_entry.dart';
import '../engine/tflite_engine.dart';
import 'memory_guard.dart';
import 'tensors.dart';
import 'upscale_pipeline.dart';

/// Progress telemetry for multi-stage cascaded inference.
class StageProgress {
  final int stageIndex; // 0-based
  final int totalStages;
  final String stageName;
  final double stagePercentage; // 0.0 to 1.0
  final double overallPercentage; // 0.0 to 1.0

  const StageProgress({
    required this.stageIndex,
    required this.totalStages,
    required this.stageName,
    required this.stagePercentage,
    required this.overallPercentage,
  });

  String get displayTitle =>
      'Step \${stageIndex + 1}/\$totalStages: \$stageName (\${(stagePercentage * 100).toStringAsFixed(0)}%)';
}

/// A single stage in a [CascadedPipeline].
class PipelineStage {
  final String id;
  final String name;
  final ModelRole role;
  final TfliteEngine engine;
  final int scale; // 1 for 1x models, 4 for 4x models
  final int inputSize;

  const PipelineStage({
    required this.id,
    required this.name,
    required this.role,
    required this.engine,
    required this.scale,
    this.inputSize = 128,
  });
}

/// Multi-stage pipeline running an ordered sequence of specialized micro-models
/// per image tile directly in memory without intermediate disk writes (ADR-0013 / ADR-0014).
class CascadedPipeline {
  final List<PipelineStage> stages;
  final int defaultTileSize;
  final int memoryLimitBytes;

  const CascadedPipeline({
    required this.stages,
    this.defaultTileSize = 128,
    this.memoryLimitBytes = MemoryGuard.defaultMemoryLimitBytes,
  });

  int get totalScale =>
      stages.fold<int>(1, (scale, stage) => scale * stage.scale);

  int _effectiveOverlap(int ts) => ts == 128 ? 36 : 16;
  int _strideFor(int ts) => ts - _effectiveOverlap(ts);

  List<int> _positions(int length, int ts, int stride) {
    if (length <= ts) return const [0];
    final count = ((length - ts) / stride).ceil() + 1;
    return List.generate(count, (i) => math.min(i * stride, length - ts));
  }

  Future<Uint8List> process(
    Uint8List imageBytes, {
    void Function(StageProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (stages.isEmpty) throw StateError('CascadedPipeline requires at least one stage');

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw Exception('Failed to decode image');

    final w = decoded.width;
    final h = decoded.height;
    final scale = totalScale;
    final ts = defaultTileSize;

    MemoryGuard.validateMemory(
      width: w,
      height: h,
      scale: scale,
      tileSize: ts,
      memoryLimitBytes: memoryLimitBytes,
    );

    final stride = _strideFor(ts);
    final xs = _positions(w, ts, stride);
    final ys = _positions(h, ts, stride);
    final totalTiles = xs.length * ys.length;

    final outW = w * scale;
    final outH = h * scale;
    final canvas = Uint8List(outW * outH * 3);
    final weights = Uint8List(outW * outH);
    final outSide = ts * scale;
    final ov = _effectiveOverlap(ts);
    final window = featherWeights(size: outSide, feather: ov * scale);

    int doneTiles = 0;
    final totalStages = stages.length;

    for (final y in ys) {
      for (final x in xs) {
        if (isCancelled != null && isCancelled()) {
          throw const UpscaleCancelledException();
        }

        final crop = img.copyCrop(
          decoded,
          x: x,
          y: y,
          width: math.min(ts, w - x),
          height: math.min(ts, h - y),
        );

        Float32List currentTensor = preprocessTile(crop, inputSize: ts);

        for (int s = 0; s < totalStages; s++) {
          if (isCancelled != null && isCancelled()) {
            throw const UpscaleCancelledException();
          }

          final stage = stages[s];
          currentTensor = await stage.engine.infer(currentTensor);

          if (onProgress != null) {
            final stageProgressFraction = (doneTiles + (s + 1) / totalStages) / totalTiles;
            final overallFraction = (doneTiles * totalStages + s + 1) / (totalTiles * totalStages);
            onProgress(StageProgress(
              stageIndex: s,
              totalStages: totalStages,
              stageName: stage.name,
              stagePercentage: stageProgressFraction.clamp(0.0, 1.0),
              overallPercentage: overallFraction.clamp(0.0, 1.0),
            ));
          }
        }

        final outTile = tileFromTensor(currentTensor, outputSize: outSide);
        stitchTile(
          canvas: canvas,
          weights: weights,
          canvasWidth: outW,
          canvasHeight: outH,
          tile: outTile.getBytes(order: img.ChannelOrder.rgb),
          tileSide: outSide,
          window: window,
          dstX: x * scale,
          dstY: y * scale,
        );

        doneTiles++;
      }
    }

    final outImage = img.Image.fromBytes(
      width: outW,
      height: outH,
      bytes: canvas.buffer,
      order: img.ChannelOrder.rgb,
      numChannels: 3,
    );

    return Uint8List.fromList(img.encodePng(outImage));
  }
}
