import 'dart:math' as math;
import 'dart:typed_data';

/// Engine seam — wraps tflite_flutter Interpreter.
/// Scaffold provides a stub that does NOT require a real .tflite file,
/// so tests and initial UI can run without native model.
abstract class TfliteEngine {
  Future<void> load(String modelPath);
  Future<void> setUseGpu(bool useGpu);

  /// Runs one [Tile] through the loaded Model (real inference).
  ///
  /// Contract: [input] is a float32 NHWC tensor `[1, inputSize, inputSize, 3]`
  /// (RGB, normalized 0..1 — produced by Preprocess). Returns a float32 NHWC
  /// tensor `[1, inputSize * scale, inputSize * scale, 3]` (0..1), where
  /// `scale` is the Model's Scale.
  Future<Float32List> infer(Float32List input);

  Future<void> close();
  bool get isLoaded;
  bool get useGpu;
}

/// Stub implementation for tests and UI scaffolding.
/// Deterministically emulates a 4x Model: every source pixel is replicated
/// into a scale×scale block (nearest neighbour), so the float32 contract
/// [1,N,N,3] -> [1,N*4,N*4,3] holds without a native model.
class TfliteEngineStub implements TfliteEngine {
  static const _emulatedScale = 4;

  bool _loaded = false;
  bool _useGpu = false;
  String? _modelPath;

  @override
  bool get isLoaded => _loaded;

  @override
  bool get useGpu => _useGpu;

  @override
  Future<void> load(String modelPath) async {
    _modelPath = modelPath;
    _loaded = true;
  }

  @override
  Future<void> setUseGpu(bool useGpu) async {
    _useGpu = useGpu;
  }

  @override
  Future<Float32List> infer(Float32List input) async {
    if (!_loaded) throw StateError('Engine not loaded: $_modelPath');
    final side = _inputSide(input);
    final outSide = side * _emulatedScale;
    final out = Float32List(outSide * outSide * 3);
    for (int y = 0; y < outSide; y++) {
      final sy = y ~/ _emulatedScale;
      for (int x = 0; x < outSide; x++) {
        final sx = x ~/ _emulatedScale;
        final si = (sy * side + sx) * 3;
        final oi = (y * outSide + x) * 3;
        out[oi] = input[si];
        out[oi + 1] = input[si + 1];
        out[oi + 2] = input[si + 2];
      }
    }
    return out;
  }

  @override
  Future<void> close() async {
    _loaded = false;
    _modelPath = null;
  }

  /// NHWC input length -> spatial side (sqrt(len / 3)).
  static int _inputSide(Float32List input) {
    final side = math.sqrt(input.length / 3).round();
    if (side * side * 3 != input.length) {
      throw ArgumentError(
          'Engine input must be an NHWC [1,N,N,3] tensor, got ${input.length} floats');
    }
    return side;
  }
}
