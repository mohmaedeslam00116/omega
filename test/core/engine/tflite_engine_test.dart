import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:omega/core/engine/tflite_engine.dart';

void main() {
  group('TfliteEngineStub', () {
    test('load marks loaded and infer doubles bytes', () async {
      final engine = TfliteEngineStub();
      expect(engine.isLoaded, false);
      await engine.load('assets/models/realesr-general-x4v3_fp16.tflite');
      expect(engine.isLoaded, true);
      final input = Uint8List.fromList([1, 2, 3, 4]);
      final out = await engine.infer(input);
      expect(out.length, input.length * 2);
    });

    test('infer throws if not loaded', () async {
      final engine = TfliteEngineStub();
      expect(() => engine.infer(Uint8List(4)), throwsA(isA<StateError>()));
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
