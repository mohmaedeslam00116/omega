import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:omega/core/catalog/catalog_entry.dart';
import 'package:omega/core/engine/tflite_engine.dart';
import 'package:omega/core/pipeline/cascaded_pipeline.dart';
import 'package:omega/core/pipeline/upscale_pipeline.dart';

class _MockDenoiseEngine implements TfliteEngine {
  int calls = 0;

  @override
  bool get isLoaded => true;
  @override
  bool get useGpu => false;
  @override
  Future<void> load(String path) async {}
  @override
  Future<void> setUseGpu(bool v) async {}
  @override
  Future<Float32List> infer(Float32List input) async {
    calls++;
    // Pass-through with slight attenuation (simulating denoising)
    final out = Float32List(input.length);
    for (int i = 0; i < input.length; i++) {
      out[i] = input[i] * 0.9;
    }
    return out;
  }
  @override
  Future<void> close() async {}
}

Uint8List _makePng(int w, int h, {img.Color? fill}) {
  final image = img.Image(width: w, height: h);
  if (fill != null) img.fill(image, color: fill);
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('CascadedPipeline', () {
    test('executes 2-stage pipeline (1x denoise -> 4x upscale) end-to-end', () async {
      final denoiseEngine = _MockDenoiseEngine();
      final upscaleStub = TfliteEngineStub();
      await upscaleStub.load('fake-upscale');

      final pipeline = CascadedPipeline(
        stages: [
          PipelineStage(
            id: 'denoise',
            name: 'Denoise 1x',
            role: ModelRole.denoise,
            engine: denoiseEngine,
            scale: 1,
          ),
          PipelineStage(
            id: 'upscale',
            name: 'SAFMN 4x',
            role: ModelRole.upscale,
            engine: upscaleStub,
            scale: 4,
          ),
        ],
      );

      final inputPng = _makePng(128, 128, fill: img.ColorRgb8(100, 150, 200));
      final progresses = <StageProgress>[];

      final outPng = await pipeline.process(
        inputPng,
        onProgress: progresses.add,
      );

      expect(denoiseEngine.calls, greaterThan(0));
      expect(progresses, isNotEmpty);
      expect(progresses.last.overallPercentage, closeTo(1.0, 0.05));
      expect(progresses.first.stageName, 'Denoise 1x');
      expect(progresses.last.stageName, 'SAFMN 4x');

      final outImage = img.decodeImage(outPng);
      expect(outImage, isNotNull);
      expect(outImage!.width, 512);
      expect(outImage.height, 512);
    });

    test('isCancelled aborts processing cleanly', () async {
      final denoiseEngine = _MockDenoiseEngine();
      final upscaleStub = TfliteEngineStub();
      await upscaleStub.load('fake-upscale');

      final pipeline = CascadedPipeline(
        stages: [
          PipelineStage(
            id: 'denoise',
            name: 'Denoise 1x',
            role: ModelRole.denoise,
            engine: denoiseEngine,
            scale: 1,
          ),
          PipelineStage(
            id: 'upscale',
            name: 'SAFMN 4x',
            role: ModelRole.upscale,
            engine: upscaleStub,
            scale: 4,
          ),
        ],
      );

      final inputPng = _makePng(256, 256);
      int callCount = 0;

      expect(
        () => pipeline.process(
          inputPng,
          isCancelled: () {
            callCount++;
            return callCount > 2;
          },
        ),
        throwsA(isA<UpscaleCancelledException>()),
      );
    });
  });
}
