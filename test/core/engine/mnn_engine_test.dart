import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:omega/core/engine/mnn_engine_impl.dart';
import 'package:omega/core/engine/tflite_engine.dart';

void main() {
  group('MnnEngineImpl', () {
    test('implements TfliteEngine interface', () {
      final engine = MnnEngineImpl();
      expect(engine, isA<TfliteEngine>());
      expect(engine.isLoaded, isFalse);
      expect(engine.useGpu, isTrue);
    });

    test('setUseGpu updates useGpu state', () async {
      final engine = MnnEngineImpl();
      await engine.setUseGpu(false);
      expect(engine.useGpu, isFalse);
    });

    test('infer throws when not loaded', () async {
      final engine = MnnEngineImpl();
      expect(
        () => engine.infer(Float32List(128 * 128 * 3)),
        throwsStateError,
      );
    });

    test('close on unloaded engine completes cleanly', () async {
      final engine = MnnEngineImpl();
      await engine.close();
      expect(engine.isLoaded, isFalse);
    });
  });
}
