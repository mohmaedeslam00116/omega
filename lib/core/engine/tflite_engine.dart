import 'dart:typed_data';

/// Engine seam — wraps tflite_flutter Interpreter.
/// Scaffold provides a stub that does NOT require a real .tflite file,
/// so tests and initial UI can run without native model.
abstract class TfliteEngine {
  Future<void> load(String modelPath);
  Future<void> setUseGpu(bool useGpu);
  Future<Uint8List> infer(Uint8List tileBytes);
  Future<void> close();
  bool get isLoaded;
  bool get useGpu;
}

/// Stub implementation for Ticket 01/04 scaffolding.
/// infer() returns input doubled (synthetic upscale) to verify pipeline shape.
class TfliteEngineStub implements TfliteEngine {
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
  Future<Uint8List> infer(Uint8List tileBytes) async {
    if (!_loaded) throw StateError('Engine not loaded: $_modelPath');
    return Uint8List.fromList([...tileBytes, ...tileBytes]);
  }

  @override
  Future<void> close() async {
    _loaded = false;
    _modelPath = null;
  }
}
