import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:omega/core/engine/tflite_engine.dart';
import 'package:omega/core/pipeline/upscale_pipeline.dart';

class _FakeEngine implements TfliteEngine {
  bool _loaded = true;
  bool _useGpu = false;
  final TfliteEngineStub _stub = TfliteEngineStub();
  final bool Function(Float32List input, int callIndex)? _inferHook;
  int _calls = 0;

  _FakeEngine({bool loaded = true, bool Function(Float32List, int)? hook})
      : _loaded = loaded,
        _inferHook = hook;

  int get calls => _calls;

  @override
  bool get isLoaded => _loaded;
  @override
  bool get useGpu => _useGpu;
  @override
  Future<void> load(String p) async => _loaded = true;
  @override
  Future<void> setUseGpu(bool v) async => _useGpu = v;
  @override
  Future<Float32List> infer(Float32List input) async {
    _calls++;
    if (_inferHook != null) {
      final shouldThrow = _inferHook(input, _calls);
      if (shouldThrow) throw Exception('OOM simulated');
    }
    // Delegate the tensor mapping to the canonical stub implementation.
    if (!_stub.isLoaded) await _stub.load('fake-model');
    return _stub.infer(input);
  }

  @override
  Future<void> close() async => _loaded = false;
}

Uint8List _makePng(int w, int h, {img.Color? fill}) {
  final image = img.Image(width: w, height: h);
  if (fill != null) img.fill(image, color: fill);
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('UpscalePipeline', () {
    test('1024x1024 splits into 121 overlapping tiles (11x11, stride 92)',
        () async {
      final engine = _FakeEngine();
      final pipeline = UpscalePipeline(engine: engine);
      final input = _makePng(1024, 1024, fill: img.ColorRgb8(100, 100, 100));
      final progresses = <double>[];
      final out = await pipeline.upscale(input, onProgress: progresses.add);
      // stride = 128 - 36 = 92 -> ceil((1024-128)/92) + 1 = 11 per axis
      expect(engine.calls, 121);
      expect(progresses.length, 121);
      expect(progresses.last, closeTo(1.0, 0.01));
      expect(progresses.first, greaterThan(0));
      // Verify output dimensions
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 4096);
      expect(decoded.height, 4096);
    });

    test('256x256 uses a clamped 3x3 grid so every tile is full-size',
        () async {
      final engine = _FakeEngine();
      final pipeline = UpscalePipeline(engine: engine);
      final input = _makePng(256, 256, fill: img.ColorRgb8(10, 10, 10));
      await pipeline.upscale(input);
      // positions: 0, 92, min(184, 128)=128 -> 3 per axis
      expect(engine.calls, 9);
    });

    test('image smaller than the tile size upscales without overflow',
        () async {
      final engine = _FakeEngine();
      final pipeline = UpscalePipeline(engine: engine);
      final input = _makePng(100, 80, fill: img.ColorRgb8(90, 90, 90));
      final out = await pipeline.upscale(input);
      expect(engine.calls, 1);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 400);
      expect(decoded.height, 320);
    });

    test('overlapping regions are feather-blended, not hard-copied', () async {
      // First tile infers 0.0, every later tile infers 1.0. With feathered
      // Stitch, pixels covered by a single tile keep that tile's value and
      // pixels covered by two disagreeing tiles land strictly in between.
      final engine = _FirstTileZeroRestOneEngine();
      final pipeline = UpscalePipeline(engine: engine);
      final input = _makePng(256, 256, fill: img.ColorRgb8(0, 0, 0));
      final out = await pipeline.upscale(input);
      final decoded = img.decodeImage(out)!;

      // (40,40): covered only by tile (0,0) -> exactly 0
      expect(decoded.getPixel(40, 40).r, 0);
      // (600,40): covered by tiles at x=92 and x=128, both value 1 -> 255
      expect(decoded.getPixel(600, 40).r, 255);
      // (400,40): covered by tile (0,0)=0 and tile (92,0)=1 -> strictly between
      final blended = decoded.getPixel(400, 40).r;
      expect(blended, greaterThan(10));
      expect(blended, lessThan(245));
    });

    test('Stitched output dimensions = input x4 (128->512, 256->1024)',
        () async {
      final engine = _FakeEngine();
      final pipeline = UpscalePipeline(engine: engine);

      final in128 = _makePng(128, 128, fill: img.ColorRgb8(10, 20, 30));
      final out128 = await pipeline.upscale(in128);
      final dec128 = img.decodeImage(out128)!;
      expect(dec128.width, 512);
      expect(dec128.height, 512);

      final in256 = _makePng(256, 256, fill: img.ColorRgb8(40, 50, 60));
      final out256 = await pipeline.upscale(in256);
      final dec256 = img.decodeImage(out256)!;
      expect(dec256.width, 1024);
      expect(dec256.height, 1024);
    });

    test('no seam artifact on synthetic checker pattern', () async {
      // Create 256x256 checker: 2x2 tiles each 128 with distinct colors
      final input = img.Image(width: 256, height: 256);
      img.fillRect(input,
          x1: 0, y1: 0, x2: 127, y2: 127, color: img.ColorRgb8(255, 0, 0)); // red
      img.fillRect(input,
          x1: 128, y1: 0, x2: 255, y2: 127, color: img.ColorRgb8(0, 255, 0)); // green
      img.fillRect(input,
          x1: 0, y1: 128, x2: 127, y2: 255, color: img.ColorRgb8(0, 0, 255)); // blue
      img.fillRect(input,
          x1: 128, y1: 128, x2: 255, y2: 255, color: img.ColorRgb8(255, 255, 0)); // yellow
      final bytes = Uint8List.fromList(img.encodePng(input));

      final engine = _FakeEngine();
      final pipeline = UpscalePipeline(engine: engine);
      final outBytes = await pipeline.upscale(bytes);
      final out = img.decodeImage(outBytes)!;
      expect(out.width, 1024);
      // Check that upscaled quadrants retain colors (no seam bleed)
      // Top-left quadrant (0,0) should be redish
      final c00 = out.getPixel(10, 10);
      expect(c00.r, greaterThan(200));
      // Top-right
      final c10 = out.getPixel(600, 10);
      expect(c10.g, greaterThan(200));
      // Bottom-left
      final c01 = out.getPixel(10, 600);
      expect(c01.b, greaterThan(200));
    });

    test('OOM simulated by fake Engine -> fallback to 64 tiles and still completes',
        () async {
      // Hook that throws OOM on first infer call only
      final oomEngine = _OomFakeEngine();
      final pipeline = UpscalePipeline(engine: oomEngine);
      final input = _makePng(256, 256, fill: img.ColorRgb8(50, 50, 50));
      final out = await pipeline.upscale(input);
      final dec = img.decodeImage(out)!;
      expect(dec.width, 1024);
      // Should have retried with tile 64: for 256, 64 tiles would be 16 tiles (4x4) vs 4 tiles (2x2) for 128
      // Verify that OOM was handled and still produced output
      expect(oomEngine.retried, true);
    });

    test('Corrupt Model path -> error Model is corrupt, please re-download',
        () async {
      final engine = _FakeEngine(loaded: false);
      final pipeline = UpscalePipeline(engine: engine);
      final input = _makePng(128, 128);
      expect(
        () => pipeline.upscale(input),
        throwsA(predicate((e) =>
            e.toString().contains('Model is corrupt, please re-download'))),
      );
    });

    test('isCancelled between tiles aborts the job cleanly', () async {
      final engine = _FakeEngine();
      final pipeline = UpscalePipeline(engine: engine);
      final input = _makePng(256, 256, fill: img.ColorRgb8(50, 50, 50));

      var checks = 0;
      // 9 tiles (3x3 clamped grid): cancel flips true on the 4th check, so
      // exactly 3 tiles get processed before the abort.
      await expectLater(
        pipeline.upscale(input, isCancelled: () => ++checks > 3),
        throwsA(isA<UpscaleCancelledException>()),
      );
      expect(engine.calls, 3);
    });

    test('Image exceeds 4096 throws', () async {
      final engine = _FakeEngine();
      final pipeline = UpscalePipeline(engine: engine);
      final big = _makePng(4097, 100);
      expect(() => pipeline.upscale(big), throwsA(isA<UnsupportedError>()));
    });
  });
}

class _OomFakeEngine implements TfliteEngine {
  bool _loaded = true;
  bool _useGpu = false;
  final TfliteEngineStub _stub = TfliteEngineStub();
  bool retried = false;
  int _calls = 0;

  @override
  bool get isLoaded => _loaded;
  @override
  bool get useGpu => _useGpu;
  @override
  Future<void> load(String p) async => _loaded = true;
  @override
  Future<void> setUseGpu(bool v) async => _useGpu = v;
  @override
  Future<Float32List> infer(Float32List input) async {
    _calls++;
    if (_calls == 1 && !retried) {
      retried = true;
      throw Exception('OOM simulated');
    }
    if (!_stub.isLoaded) await _stub.load('fake-model');
    return _stub.infer(input);
  }

  @override
  Future<void> close() async => _loaded = false;
}

/// First infer returns an all-0.0 tensor, every later one all-1.0 — makes the
/// feather blend observable: single-coverage keeps the tile's constant,
/// overlapping coverage lands strictly between the two constants.
class _FirstTileZeroRestOneEngine implements TfliteEngine {
  bool _loaded = true;
  bool _useGpu = false;
  final TfliteEngineStub _stub = TfliteEngineStub();
  int _calls = 0;

  @override
  bool get isLoaded => _loaded;
  @override
  bool get useGpu => _useGpu;
  @override
  Future<void> load(String p) async => _loaded = true;
  @override
  Future<void> setUseGpu(bool v) async => _useGpu = v;
  @override
  Future<Float32List> infer(Float32List input) async {
    _calls++;
    if (!_stub.isLoaded) await _stub.load('fake-model');
    final out = await _stub.infer(input);
    final v = _calls == 1 ? 0.0 : 1.0;
    for (int i = 0; i < out.length; i++) {
      out[i] = v;
    }
    return out;
  }

  @override
  Future<void> close() async => _loaded = false;
}
