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
  final tile = img.Image(width: outputSize, height: outputSize, numChannels: 3);
  for (int y = 0; y < outputSize; y++) {
    for (int x = 0; x < outputSize; x++) {
      final i = (y * outputSize + x) * 3;
      tile.setPixelRgb(
        x,
        y,
        _toByte(tensor[i]),
        _toByte(tensor[i + 1]),
        _toByte(tensor[i + 2]),
      );
    }
  }
  return tile;
}

int _toByte(double v) => (v * 255.0).round().clamp(0, 255);

/// **Stitch** — per-tile feather weight window: 1.0 in the tile interior,
/// ramping linearly to ~0 at the borders over [feather] pixels (per axis,
/// combined multiplicatively). A [feather] of 0 disables the ramp (all 1.0).
Float32List featherWeights({required int size, required int feather}) {
  final w = Float32List(size * size);
  for (int y = 0; y < size; y++) {
    final wy =
        feather <= 0 ? 1.0 : math.min(1.0, math.min(y + 0.5, size - y - 0.5) / feather);
    for (int x = 0; x < size; x++) {
      final wx = feather <= 0
          ? 1.0
          : math.min(1.0, math.min(x + 0.5, size - x - 0.5) / feather);
      w[y * size + x] = wx * wy;
    }
  }
  return w;
}

/// **Stitch** — blend one upscaled [tile] (flat RGB bytes, [tileSide]² px)
/// into the flat RGB [canvas] at ([dstX], [dstY]) using the feather [window].
///
/// Blending is a running weighted average: each canvas pixel carries its
/// accumulated coverage in [weights] (1 byte per pixel, 0..255). Where only
/// one tile covers a pixel, that tile's value wins exactly; where tiles
/// overlap, the result is the weight-averaged crossfade — no hard seams.
/// Writes are clipped to the canvas ([canvasWidth] x [canvasHeight]), so a
/// padded tile on an image smaller than the tile size cannot overflow.
void stitchTile({
  required Uint8List canvas,
  required Uint8List weights,
  required int canvasWidth,
  required int canvasHeight,
  required Uint8List tile,
  required int tileSide,
  required Float32List window,
  required int dstX,
  required int dstY,
}) {
  final cols = math.min(tileSide, canvasWidth - dstX);
  final rows = math.min(tileSide, canvasHeight - dstY);
  for (int oy = 0; oy < rows; oy++) {
    final crow = ((dstY + oy) * canvasWidth + dstX) * 3;
    final trow = oy * tileSide * 3;
    final wrow = (dstY + oy) * canvasWidth + dstX;
    for (int ox = 0; ox < cols; ox++) {
      final w = window[oy * tileSide + ox];
      final ci = crow + ox * 3;
      final ti = trow + ox * 3;
      final stored = weights[wrow + ox];
      if (stored == 0) {
        canvas[ci] = tile[ti];
        canvas[ci + 1] = tile[ti + 1];
        canvas[ci + 2] = tile[ti + 2];
        weights[wrow + ox] = (w * 255).round().clamp(1, 255);
        continue;
      }
      final w0 = stored / 255.0;
      final total = w0 + w;
      canvas[ci] = _blendByte(canvas[ci], tile[ti], w0, total);
      canvas[ci + 1] = _blendByte(canvas[ci + 1], tile[ti + 1], w0, total);
      canvas[ci + 2] = _blendByte(canvas[ci + 2], tile[ti + 2], w0, total);
      weights[wrow + ox] = (total * 255).round().clamp(1, 255);
    }
  }
}

int _blendByte(int c0, int c1, double w0, double total) =>
    ((c0 * w0 + c1 * (total - w0)) / total).round().clamp(0, 255);