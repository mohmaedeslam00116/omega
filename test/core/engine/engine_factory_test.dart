import 'package:flutter_test/flutter_test.dart';
import 'package:omega/core/engine/engine_factory.dart';
import 'package:omega/core/engine/mnn_engine_impl.dart';
import 'package:omega/core/engine/tflite_engine_impl.dart';

void main() {
  group('EngineFactory', () {
    test('routes .mnn model paths to MnnEngineImpl', () {
      final engine = EngineFactory.createForModel('assets/models/realesr-x4plus.mnn');
      expect(engine, isA<MnnEngineImpl>());
    });

    test('routes .tflite model paths to TfliteEngineImpl', () {
      final engine = EngineFactory.createForModel('assets/models/realesr-general-x4v3.tflite');
      expect(engine, isA<TfliteEngineImpl>());
    });
  });
}
