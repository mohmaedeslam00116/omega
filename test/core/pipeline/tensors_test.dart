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
}