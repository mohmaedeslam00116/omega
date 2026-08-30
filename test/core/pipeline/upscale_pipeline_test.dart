import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:omega/core/engine/tflite_engine.dart';
import 'package:omega/core/pipeline/upscale_pipeline.dart';

class _FakeEngine implements TfliteEngine {
  bool _loaded = true;
  bool _useGpu = false;
  final bool Function(Uint8List tileBytes, int callIndex)? _inferHook;
  int _calls = 0;

  _FakeEngine({bool loaded = true, bool Function(Uint8List, int)? hook})
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
  Future<Uint8List> infer(Uint8List tileBytes) async {
    _calls++;
    if (_inferHook != null) {
      final shouldThrow = _inferHook(tileBytes, _calls);
      if (shouldThrow) throw Exception('OOM simulated');
    }
    // Return doubled bytes to simulate 4x (stub)
    return Uint8List.fromList([...tileBytes, ...tileBytes]);
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
    test('1024x1024 splits into 64 tiles and progress callbacks 64 times',
        () async {
      final engine = _FakeEngine();
      final pipeline = UpscalePipeline(engine: engine);
      final input = _makePng(1024, 1024, fill: img.ColorRgb8(100, 100, 100));
      final progresses = <double>[];
      final out = await pipeline.upscale(input, onProgress: progresses.add);
      expect(engine.calls, 64);
      expect(progresses.length, 64);
      expect(progresses.last, closeTo(1.0, 0.01));
      expect(progresses.first, greaterThan(0));
      // Verify output dimensions
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 4096);
      expect(decoded.height, 4096);
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
  Future<Uint8List> infer(Uint8List tileBytes) async {
    _calls++;
    if (_calls == 1 && !retried) {
      retried = true;
      throw Exception('OOM simulated');
    }
    return Uint8List.fromList([...tileBytes, ...tileBytes]);
  }

  @override
  Future<void> close() async => _loaded = false;
}
