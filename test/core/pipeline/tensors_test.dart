import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:omega/core/engine/tflite_engine.dart';
import 'package:omega/core/pipeline/tensors.dart';

img.Image _solid(int w, int h, int r, int g, int b) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return image;
}

void main() {
  group('Preprocess (preprocessTile)', () {
    test('full-size tile normalizes RGB into NHWC float32 0..1', () {
      final tile = _solid(4, 4, 255, 128, 0);
      final tensor = preprocessTile(tile, inputSize: 4);

      expect(tensor.length, 4 * 4 * 3);
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          final i = (y * 4 + x) * 3;
          expect(tensor[i], closeTo(1.0, 1e-6), reason: 'r @($x,$y)');
          expect(tensor[i + 1], closeTo(128 / 255, 1e-6), reason: 'g @($x,$y)');
          expect(tensor[i + 2], closeTo(0.0, 1e-6), reason: 'b @($x,$y)');
        }
      }
    });

    test('alpha is dropped: RGB channels only', () {
      final image = img.Image(width: 2, height: 2, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(10, 20, 30, 255));
      final tensor = preprocessTile(image, inputSize: 2);
      final i = (1 * 2 + 1) * 3;
      expect(tensor[i], closeTo(10 / 255, 1e-6));
      expect(tensor[i + 1], closeTo(20 / 255, 1e-6));
      expect(tensor[i + 2], closeTo(30 / 255, 1e-6));
    });

    test('edge tile is edge-replicated up to inputSize (no index errors)', () {
      // 100x60 tile, padded to 128x128 by clamped sampling
      final tile = _solid(100, 60, 200, 100, 50);
      final tensor = preprocessTile(tile, inputSize: 128);

      expect(tensor.length, 128 * 128 * 3);
      // inside the valid region
      final inside = (10 * 128 + 10) * 3;
      expect(tensor[inside], closeTo(200 / 255, 1e-6));
      // beyond width (x >= 100) replicates the last column
      final beyondX = (5 * 128 + 100) * 3;
      expect(tensor[beyondX], closeTo(200 / 255, 1e-6));
      // beyond height (y >= 60) replicates the last row
      final beyondY = (60 * 128 + 5) * 3;
      expect(tensor[beyondY], closeTo(200 / 255, 1e-6));
      // corner (beyond both)
      final corner = (127 * 128 + 127) * 3;
      expect(tensor[corner], closeTo(200 / 255, 1e-6));
    });

    test('non-uniform pixels land at the right NHWC index', () {
      final tile = img.Image(width: 2, height: 2);
      img.fill(tile, color: img.ColorRgb8(0, 0, 0));
      tile.setPixel(1, 0, img.ColorRgb8(255, 0, 0));
      tile.setPixel(0, 1, img.ColorRgb8(0, 255, 0));
      tile.setPixel(1, 1, img.ColorRgb8(0, 0, 255));

      final tensor = preprocessTile(tile, inputSize: 2);
      // (x=1,y=0) red
      expect(tensor[(0 * 2 + 1) * 3], closeTo(1.0, 1e-6));
      expect(tensor[(0 * 2 + 1) * 3 + 1], closeTo(0.0, 1e-6));
      // (x=0,y=1) green
      expect(tensor[(1 * 2 + 0) * 3 + 1], closeTo(1.0, 1e-6));
      // (x=1,y=1) blue
      expect(tensor[(1 * 2 + 1) * 3 + 2], closeTo(1.0, 1e-6));
    });
  });

  group('Stitch (tileFromTensor)', () {
    test('denormalizes NHWC float32 back to pixels with clamping', () {
      final tensor = Float32List(2 * 2 * 3);
      // (0,0) black
      // (1,0) white
      tensor[(0 * 2 + 1) * 3] = 1.0;
      tensor[(0 * 2 + 1) * 3 + 1] = 1.0;
      tensor[(0 * 2 + 1) * 3 + 2] = 1.0;
      // (0,1) mid gray
      tensor[(1 * 2 + 0) * 3] = 0.5;
      tensor[(1 * 2 + 0) * 3 + 1] = 0.5;
      tensor[(1 * 2 + 0) * 3 + 2] = 0.5;
      // (1,1) out-of-range values clamp
      tensor[(1 * 2 + 1) * 3] = -0.5;
      tensor[(1 * 2 + 1) * 3 + 1] = 1.5;

      final tile = tileFromTensor(tensor, outputSize: 2);
      expect(tile.width, 2);
      expect(tile.height, 2);

      expect(tile.getPixel(0, 0).r, 0);
      final white = tile.getPixel(1, 0);
      expect(white.r, 255);
      expect(white.g, 255);
      expect(white.b, 255);
      final gray = tile.getPixel(0, 1);
      expect(gray.r, (0.5 * 255).round());
      final clamped = tile.getPixel(1, 1);
      expect(clamped.r, 0);
      expect(clamped.g, 255);
    });

    test('round-trip: solid tile keeps its color through Preprocess + Engine',
        () async {
      final tile = _solid(128, 128, 30, 144, 255);
      final tensor = preprocessTile(tile, inputSize: 128);

      // The canonical deterministic Engine emulation (4x nearest).
      final stub = TfliteEngineStub();
      await stub.load('fake-model');
      final out = await stub.infer(tensor);

      final up = tileFromTensor(out, outputSize: 128 * 4);
      expect(up.width, 512);
      expect(up.height, 512);
      final p = up.getPixel(511, 511);
      expect(p.r, 30);
      expect(p.g, 144);
      expect(p.b, 255);
    });
  });

  group('Stitch (featherWeights)', () {
    test('all ones when feather is zero', () {
      final w = featherWeights(size: 4, feather: 0);
      expect(w.length, 16);
      for (final v in w) {
        expect(v, 1.0);
      }
    });

    test('center is fully weighted, edges ramp down, corners smallest', () {
      const size = 8;
      const feather = 2;
      final w = featherWeights(size: size, feather: feather);

      double at(int x, int y) => w[y * size + x];
      expect(at(4, 4), 1.0);
      // symmetric horizontally and vertically
      expect(at(0, 4), at(7, 4));
      expect(at(4, 0), at(4, 7));
      // edges are ramped down, corners are the product of two ramps
      expect(at(0, 4), lessThan(1.0));
      expect(at(0, 0), lessThan(at(0, 4)));
      // inside the feather margin from the edge, weight is 1
      expect(at(2, 4), 1.0);
    });
  });

  group('Stitch (stitchTile)', () {
    // 4x4 tile, feather 2, on a 6x4 canvas: tile1 at dst(0,0), tile2 at
    // dst(2,0) -> columns 2..3 are covered by both tiles.
    Uint8List constTile(int side, int v) =>
        Uint8List.fromList(List.filled(side * side * 3, v));

    test('single tile writes its pixels and registers coverage', () {
      final canvas = Uint8List(6 * 4 * 3);
      final weights = Uint8List(6 * 4);
      final window = featherWeights(size: 4, feather: 2);
      final tile = constTile(4, 100);

      stitchTile(
        canvas: canvas,
        weights: weights,
        canvasWidth: 6,
        canvasHeight: 4,
        tile: tile,
        tileSide: 4,
        window: window,
        dstX: 0,
        dstY: 0,
      );

      final i = (1 * 6 + 1) * 3;
      expect(canvas[i], 100);
      expect(canvas[i + 1], 100);
      expect(canvas[i + 2], 100);
      expect(weights[1 * 6 + 1], greaterThan(0));
    });

    test('writes are clipped to the canvas (image smaller than tile)', () {
      // Canvas 2x2 with a full 4x4 tile at (0,0): the padded overflow must be
      // discarded, not overflow into memory.
      final canvas = Uint8List(2 * 2 * 3);
      final weights = Uint8List(2 * 2);
      final window = featherWeights(size: 4, feather: 2);

      stitchTile(
        canvas: canvas,
        weights: weights,
        canvasWidth: 2,
        canvasHeight: 2,
        tile: constTile(4, 100),
        tileSide: 4,
        window: window,
        dstX: 0,
        dstY: 0,
      );

      expect(weights[0], greaterThan(0));
      expect(weights[1 * 2 + 1], greaterThan(0));
      expect(canvas[(1 * 2 + 1) * 3], 100);
    });

    test('overlap blends the two tiles instead of hard-copying', () {
      final canvas = Uint8List(6 * 4 * 3);
      final weights = Uint8List(6 * 4);
      final window = featherWeights(size: 4, feather: 2);

      stitchTile(
        canvas: canvas,
        weights: weights,
        canvasWidth: 6,
        canvasHeight: 4,
        tile: constTile(4, 100),
        tileSide: 4,
        window: window,
        dstX: 0,
        dstY: 0,
      );
      stitchTile(
        canvas: canvas,
        weights: weights,
        canvasWidth: 6,
        canvasHeight: 4,
        tile: constTile(4, 200),
        tileSide: 4,
        window: window,
        dstX: 2,
        dstY: 0,
      );

      int r(int x, int y) => canvas[(y * 6 + x) * 3];
      // single coverage keeps its own tile's constant
      expect(r(0, 1), 100);
      expect(r(5, 1), 200);
      // overlap: strictly between the two constants, close to the weighted mean
      final blended = r(2, 1);
      expect(blended, greaterThan(100));
      expect(blended, lessThan(200));
      // asymmetric blend: tile1 is deeper at x=2 than tile2 -> closer to 100
      final deeper = r(2, 1);
      final shallower = r(3, 1);
      expect(deeper, lessThan(shallower));
    });
  });
}