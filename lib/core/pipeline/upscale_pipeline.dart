import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import '../engine/tflite_engine.dart';
import 'tensors.dart';

/// Thrown when an [UpscaleJob] is aborted through its cancellation signal
/// between tiles. The [UpscaleJobRunner] surface translates this into a
/// quiet "cancelled" state — not an error.
class UpscaleCancelledException implements Exception {
  const UpscaleCancelledException();

  @override
  String toString() => 'Upscale cancelled';
}

/// Thrown by the pre-flight memory guard when the estimated decode + output
/// footprint exceeds the pipeline's memory limit. The message is
/// user-facing (shown in the Upscale tab) — keep it free of OOM jargon so it
/// never looks like an out-of-memory retry trigger.
class MemoryEstimateExceededException implements Exception {
  final int estimatedBytes;
  final int limitBytes;

  const MemoryEstimateExceededException(this.estimatedBytes, this.limitBytes);

  static String _mb(int bytes) => (bytes / (1024 * 1024)).round().toString();

  @override
  String toString() =>
      'Image is too large to upscale on this device '
      '(needs ~${_mb(estimatedBytes)} MB, limit is ${_mb(limitBytes)} MB). '
      'Try a smaller image.';
}

/// Pre-flight estimate of the peak pixel memory one upscale needs:
/// the decoded input image plus the full output canvas, both RGBA
/// (4 bytes per pixel).
int estimateUpscaleMemoryBytes(int width, int height, {int scale = 4}) =>
    (width * height + width * scale * (height * scale)) * 4;

class UpscalePipeline {
  final TfliteEngine engine;
  final int tileSize;
  final int overlap;
  final int scale;

  /// Pre-flight budget: jobs whose estimated decode + output footprint
  /// exceeds this are rejected before any inference (ADR-0007 decision 3).
  final int memoryLimitBytes;

  UpscalePipeline({
    required this.engine,
    this.tileSize = 128,
    this.overlap = 36,
    this.scale = 4,
    this.memoryLimitBytes = 512 * 1024 * 1024,
  });

  /// Highest seam: upscale imageBytes (encoded PNG/JPEG) -> upscaled bytes (PNG).
  /// Validates 4096 limit, tiles with overlap, runs Engine per tile
  /// (Preprocess -> infer -> feathered Stitch), reports progress.
  /// [isCancelled] is polled between tiles; when it turns true the job aborts
  /// with [UpscaleCancelledException].
  Future<Uint8List> upscale(
    Uint8List imageBytes, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!engine.isLoaded) {
      throw Exception('Model is corrupt, please re-download');
    }

    // Try primary tile size, fallback to 64 on OOM
    try {
      return await _process(imageBytes, tileSize, onProgress, isCancelled);
    } catch (e) {
      if (_isOom(e)) {
        return await _process(imageBytes, 64, onProgress, isCancelled);
      }
      rethrow;
    }
  }

  bool _isOom(Object e) =>
      e.toString().contains('OOM') ||
      e is OutOfMemoryError ||
      e.toString().contains('out of memory');

  /// Stride = tileSize - overlap, floored so neighbouring tiles always share
  /// at least half a tile (guards against overlap >= tileSize).
  int _strideFor(int ts) => ts - math.min(overlap, ts ~/ 2);

  /// Tile origins along one axis. Every tile is FULL size: origins are clamped
  /// so the last tile ends exactly at the edge (w >= ts), and a single tile
  /// covers a shorter axis (w < ts, padded by Preprocess).
  List<int> _positions(int length, int ts, int stride) {
    if (length <= ts) return const [0];
    final count = ((length - ts) / stride).ceil() + 1;
    return List.generate(count, (i) => math.min(i * stride, length - ts));
  }

  Future<Uint8List> _process(
    Uint8List imageBytes,
    int ts,
    void Function(double)? onProgress,
    bool Function()? isCancelled,
  ) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw Exception('Failed to decode image');

    final w = decoded.width;
    final h = decoded.height;
    if (w > 4096 || h > 4096) {
      throw UnsupportedError('Image exceeds 4096px, please crop or choose smaller');
    }

    // Pre-flight memory guard: refuse the job (with a friendly message)
    // before allocating anything big. Not an OOM — never retried.
    final estimated = estimateUpscaleMemoryBytes(w, h, scale: scale);
    if (estimated > memoryLimitBytes) {
      throw MemoryEstimateExceededException(estimated, memoryLimitBytes);
    }

    final stride = _strideFor(ts);
    final xs = _positions(w, ts, stride);
    final ys = _positions(h, ts, stride);
    final totalTiles = xs.length * ys.length;

    // Output canvas (flat RGB) + per-pixel coverage weights for the feather.
    final outW = w * scale;
    final outH = h * scale;
    final canvas = Uint8List(outW * outH * 3);
    final weights = Uint8List(outW * outH);
    final outSide = ts * scale;
    final window = featherWeights(size: outSide, feather: overlap * scale);

    int done = 0;
    for (final y in ys) {
      for (final x in xs) {
        if (isCancelled != null && isCancelled()) {
          throw const UpscaleCancelledException();
        }
        // Full-size source tile (edges clamped; shorter axes padded later by
        // Preprocess edge replication).
        final tile = img.copyCrop(decoded,
            x: x, y: y, width: math.min(ts, w - x), height: math.min(ts, h - y));

        // Preprocess: tile -> float32 NHWC tensor at the Model's input size.
        final input = preprocessTile(tile, inputSize: ts);

        // Engine: real Model inference (deterministic stub in tests).
        final tensorOut = await engine.infer(input);

        // Stitch: tensor -> pixels, feather-blended into the canvas.
        final outTile = tileFromTensor(tensorOut, outputSize: outSide);
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

        done++;
        if (onProgress != null) onProgress(done / totalTiles);

        // Yield to event loop to keep UI responsive (simulates Isolate)
        await Future<void>.delayed(Duration.zero);
      }
    }

    final output = img.Image.fromBytes(
      width: outW,
      height: outH,
      bytes: canvas.buffer,
      numChannels: 3,
    );
    return Uint8List.fromList(img.encodePng(output));
  }
}
