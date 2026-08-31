import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import '../engine/tflite_engine.dart';
import 'memory_guard.dart';
import 'tensors.dart';

export 'memory_guard.dart';

/// Thrown when an [UpscaleJob] is aborted through its cancellation signal
/// between tiles. The [UpscaleJobRunner] surface translates this into a
/// quiet "cancelled" state — not an error.
class UpscaleCancelledException implements Exception {
  const UpscaleCancelledException();

  @override
  String toString() => 'Upscale cancelled';
}

class UpscalePipeline {
  final TfliteEngine engine;
  final int tileSize;
  final int? overlap;
  final int scale;

  /// Pre-flight budget: jobs whose estimated decode + output footprint
  /// exceeds this are rejected before any inference (ADR-0007 decision 3).
  final int memoryLimitBytes;

  UpscalePipeline({
    required this.engine,
    this.tileSize = 128,
    this.overlap,
    this.scale = 4,
    this.memoryLimitBytes = MemoryGuard.defaultMemoryLimitBytes,
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

  int _effectiveOverlap(int ts) => overlap ?? MemoryGuard.overlapForTileSize(ts);

  /// Stride = tileSize - overlap, floored so neighbouring tiles always share
  /// at least half a tile (guards against overlap >= tileSize).
  int _strideFor(int ts) {
    final ov = _effectiveOverlap(ts);
    return ts - math.min(ov, ts ~/ 2);
  }

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
    final swTotal = Stopwatch()..start();
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw Exception('Failed to decode image');

    final w = decoded.width;
    final h = decoded.height;
    print('[Omega-Pipeline] Starting upscale: image=${w}x$h, tileSize=$ts, scale=$scale');

    // Pre-flight memory guard: refuse the job (with a friendly message)
    // before allocating anything big. Not an OOM — never retried.
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
    print('[Omega-Pipeline] Tiling plan: ${xs.length}x${ys.length} = $totalTiles total tiles (stride=$stride, overlap=${_effectiveOverlap(ts)})');

    // Output canvas (flat RGB) + per-pixel coverage weights for the feather.
    final outW = w * scale;
    final outH = h * scale;
    final canvas = Uint8List(outW * outH * 3);
    final weights = Uint8List(outW * outH);
    final outSide = ts * scale;
    final ov = _effectiveOverlap(ts);
    final window = featherWeights(size: outSide, feather: ov * scale);

    int done = 0;
    for (final y in ys) {
      for (final x in xs) {
        if (isCancelled != null && isCancelled()) {
          print('[Omega-Pipeline] Job cancelled by user at tile $done/$totalTiles');
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
        print('[Omega-Pipeline] Completed tile $done/$totalTiles (${(done / totalTiles * 100).toStringAsFixed(1)}%)');

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
    final pngBytes = Uint8List.fromList(img.encodePng(output));
    swTotal.stop();
    print('[Omega-Pipeline] Upscale finished in ${swTotal.elapsedMilliseconds}ms (${outW}x$outH, ${pngBytes.length} bytes)');
    return pngBytes;
  }
}
