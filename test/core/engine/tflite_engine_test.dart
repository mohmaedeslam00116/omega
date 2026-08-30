import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omega/core/engine/tflite_engine.dart';

/// Builds a deterministic NHWC [1,N,N,3] float32 tensor where channel values
/// derive from coordinates, so the 4x nearest mapping is easy to assert.
Float32List _rampTensor(int n) {
  final t = Float32List(n * n * 3);
  for (int y = 0; y < n; y++) {
    for (int x = 0; x < n; x++) {
      final i = (y * n + x) * 3;
      t[i] = (x / n);
      t[i + 1] = (y / n);
      t[i + 2] = ((x + y) / (2 * n));
    }
  }
  return t;
}

void main() {
  const n = 4; // input side for fast tests
  const scale = 4;
  const m = n * scale; // output side

  group('TfliteEngineStub (float32 contract [1,N,N,3] -> [1,N*scale,N*scale,3])',
      () {
    test('load marks loaded', () async {
      final engine = TfliteEngineStub();
      expect(engine.isLoaded, false);
      await engine.load('assets/models/realesr-general-x4v3_fp16.tflite');
      expect(engine.isLoaded, true);
    });

    test('infer maps NHWC input to 4x nearest-neighbour output', () async {
      final engine = TfliteEngineStub();
      await engine.load('x');

      final input = _rampTensor(n);
      final out = await engine.infer(input);

      expect(out.length, m * m * 3);
      // every channel of every output pixel replicates its source pixel
      for (final (oy, ox) in [(0, 0), (m - 1, m - 1), (2 * scale + 1, scale)]) {
        final sy = oy ~/ scale;
        final sx = ox ~/ scale;
        final si = (sy * n + sx) * 3;
        final oi = (oy * m + ox) * 3;
        expect(out[oi], closeTo(input[si], 1e-6), reason: 'r @($ox,$oy)');
        expect(out[oi + 1], closeTo(input[si + 1], 1e-6),
            reason: 'g @($ox,$oy)');
        expect(out[oi + 2], closeTo(input[si + 2], 1e-6), reason: 'b @($ox,$oy)');
      }
    });

    test('infer on Model input size 128 yields 512-side output', () async {
      final engine = TfliteEngineStub();
      await engine.load('x');
      final out = await engine.infer(Float32List(128 * 128 * 3));
      expect(out.length, 512 * 512 * 3);
    });

    test('infer throws if not loaded', () async {
      final engine = TfliteEngineStub();
      expect(
        () => engine.infer(Float32List(n * n * 3)),
        throwsA(isA<StateError>()),
      );
    });

    test('setUseGpu toggles flag', () async {
      final engine = TfliteEngineStub();
      await engine.setUseGpu(true);
      expect(engine.useGpu, true);
      await engine.setUseGpu(false);
      expect(engine.useGpu, false);
    });

    test('close resets loaded', () async {
      final engine = TfliteEngineStub();
      await engine.load('x');
      await engine.close();
      expect(engine.isLoaded, false);
    });
  });
}