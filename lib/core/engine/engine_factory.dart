import 'mnn_engine_impl.dart';
import 'tflite_engine.dart';
import 'tflite_engine_impl.dart';

/// Factory for resolving and constructing the appropriate [TfliteEngine]
/// implementation based on model path / backend format.
class EngineFactory {
  /// Resolves the engine based on model path extension and platform capabilities.
  static TfliteEngine createForModel(String modelPath) {
    if (modelPath.endsWith('.mnn')) {
      return MnnEngineImpl();
    }
    return TfliteEngineImpl();
  }
}
