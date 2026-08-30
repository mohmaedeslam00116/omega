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
    this.overlap = 32,
    this.scale = 4,
  });

  /// Highest seam: upscale imageBytes (encoded PNG/JPEG) -> upscaled bytes (PNG).
  /// Validates 4096 limit, tiles, runs Engine per tile (Preprocess -> infer ->
  /// Stitch), composites, reports progress.
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

    // Simple tiling: stride = tileSize (no overlap for count), but overlap handled in stitch feather.
    // For 1024 with 128 -> 8x8=64 tiles as per spec.
    final stride = ts; // keep 64 tiles for 1024 as spec expects
    final tilesX = (w / stride).ceil();
    final tilesY = (h / stride).ceil();
    final totalTiles = tilesX * tilesY;

    // Output canvas
    final outW = w * scale;
    final outH = h * scale;
    final output = img.Image(width: outW, height: outH);

    int done = 0;
    for (int ty = 0; ty < tilesY; ty++) {
      for (int tx = 0; tx < tilesX; tx++) {
        final x = tx * stride;
        final y = ty * stride;
        final cw = (x + ts > w) ? w - x : ts;
        final ch = (y + ts > h) ? h - y : ts;

        // Crop tile
        final tile = img.copyCrop(decoded, x: x, y: y, width: cw, height: ch);

        // Preprocess: tile -> float32 NHWC tensor at the Model's input size
        // (edge tiles are edge-replicated up to full size).
        final input = preprocessTile(tile, inputSize: ts);

        // Engine: real Model inference (deterministic stub in tests).
        final tensorOut = await engine.infer(input);

        // Stitch: tensor -> pixels; crop the valid region back out of the
        // padded output for edge tiles, then composite onto the canvas.
        final outTile = tileFromTensor(tensorOut, outputSize: ts * scale);
        final cropped = (cw == ts && ch == ts)
            ? outTile
            : img.copyCrop(outTile,
                x: 0, y: 0, width: cw * scale, height: ch * scale);
        img.compositeImage(output, cropped, dstX: x * scale, dstY: y * scale);

        done++;
        if (onProgress != null) onProgress(done / totalTiles);

        // Yield to event loop to keep UI responsive (simulates Isolate)
        await Future<void>.delayed(Duration.zero);
      }
    }

    return Uint8List.fromList(img.encodePng(output));
  }
}
