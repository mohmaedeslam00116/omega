import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import '../engine/tflite_engine.dart';
import 'tensors.dart';

class UpscalePipeline {
  final TfliteEngine engine;
  final int tileSize;
  final int overlap;
  final int scale;

  UpscalePipeline({
    required this.engine,
    this.tileSize = 128,
    this.overlap = 36,
    this.scale = 4,
  });

  /// Highest seam: upscale imageBytes (encoded PNG/JPEG) -> upscaled bytes (PNG).
  /// Validates 4096 limit, tiles with overlap, runs Engine per tile
  /// (Preprocess -> infer -> feathered Stitch), reports progress.
  Future<Uint8List> upscale(
    Uint8List imageBytes, {
    void Function(double progress)? onProgress,
  }) async {
    if (!engine.isLoaded) {
      throw Exception('Model is corrupt, please re-download');
    }

    // Try primary tile size, fallback to 64 on OOM
    try {
      return await _process(imageBytes, tileSize, onProgress);
    } catch (e) {
      if (_isOom(e)) {
        return await _process(imageBytes, 64, onProgress);
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
  ) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw Exception('Failed to decode image');

    final w = decoded.width;
    final h = decoded.height;
    if (w > 4096 || h > 4096) {
      throw UnsupportedError('Image exceeds 4096px, please crop or choose smaller');
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
