import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// **Preprocess** — turn a source [Tile] into the float32 tensor an Engine
/// consumes: NHWC layout `[1, inputSize, inputSize, 3]`, RGB, normalized 0..1.
///
/// Tiles cropped at the right/bottom image border can be smaller than
/// [inputSize]; missing samples are edge-replicated (clamped) so every tensor
/// is exactly the Model's input size. Alpha is dropped (upscale models are RGB).
Float32List preprocessTile(img.Image tile, {required int inputSize}) {
  final tensor = Float32List(inputSize * inputSize * 3);
  final maxSX = tile.width - 1;
  final maxSY = tile.height - 1;
  for (int y = 0; y < inputSize; y++) {
    final sy = math.min(y, maxSY);
    for (int x = 0; x < inputSize; x++) {
      final sx = math.min(x, maxSX);
      final p = tile.getPixel(sx, sy);
      final i = (y * inputSize + x) * 3;
      tensor[i] = p.r / 255.0;
      tensor[i + 1] = p.g / 255.0;
      tensor[i + 2] = p.b / 255.0;
    }
  }
  return tensor;
}

/// **Stitch** — map one upscaled tile tensor back to pixels: NHWC
/// `[1, outputSize, outputSize, 3]`, RGB, 0..1 (inverse of [preprocessTile]).
/// Values are clamped to the representable 0..255 byte range.
img.Image tileFromTensor(Float32List tensor, {required int outputSize}) {
  final tile = img.Image(width: outputSize, height: outputSize);
  for (int y = 0; y < outputSize; y++) {
    for (int x = 0; x < outputSize; x++) {
      final i = (y * outputSize + x) * 3;
      tile.setPixel(
        x,
        y,
        img.ColorRgb8(
          _toByte(tensor[i]),
          _toByte(tensor[i + 1]),
          _toByte(tensor[i + 2]),
        ),
      );
    }
  }
  return tile;
}

int _toByte(double v) => (v * 255.0).round().clamp(0, 255);