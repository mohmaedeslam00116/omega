import 'dart:io';
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'tflite_engine.dart';

/// Real implementation wrapping tflite_flutter Interpreter.
/// Used in production (Ticket 04), while TfliteEngineStub is used in tests.
/// Handles GpuDelegateV2 with XNNPACK CPU fallback (4 threads).
class TfliteEngineImpl implements TfliteEngine {
  Interpreter? _interpreter;
  bool _useGpu = false;
  String? _modelPath;
  bool _isLoaded = false;

  @override
  bool get isLoaded => _isLoaded;

  @override
  bool get useGpu => _useGpu;

  @override
  Future<void> setUseGpu(bool useGpu) async {
    _useGpu = useGpu;
    // If already loaded, reload with new delegate to apply.
    if (_isLoaded && _modelPath != null) {
      final path = _modelPath!;
      await close();
      await load(path);
    }
  }

  @override
  Future<void> load(String modelPath) async {
    _modelPath = modelPath;
    await close();
    final options = InterpreterOptions();

    if (_useGpu) {
      try {
        options.addDelegate(GpuDelegateV2());
      } catch (_) {
        options.threads = 4;
      }
    } else {
      options.threads = 4;
    }

    try {
      final file = File(modelPath);
      if (await file.exists()) {
        _interpreter = Interpreter.fromFile(file, options: options);
      } else {
        _interpreter = await Interpreter.fromAsset(modelPath, options: options);
      }
      _interpreter!.allocateTensors();
      _isLoaded = true;
    } catch (_) {
      _interpreter = null;
      _isLoaded = false;
      rethrow;
    }
  }

  @override
  Future<Float32List> infer(Float32List input) async {
    final interpreter = _interpreter;
    if (!_isLoaded || interpreter == null) {
      throw StateError('Engine not loaded: $_modelPath');
    }

    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);

    // Raw float32 little-endian bytes. tflite_flutter passes Uint8List input
    // through byte-for-byte (no shape resize, no per-element boxing) and
    // copies Uint8List output back the same way — see Tensor.getInputShapeIfDifferent
    // and ByteConversionUtils.convertObjectToBytes.
    final inBytes =
        Uint8List.view(input.buffer, input.offsetInBytes, input.lengthInBytes);
    if (inBytes.length != inputTensor.data.length) {
      throw ArgumentError(
        'Input tensor size mismatch: Model expects '
        '${inputTensor.data.length} bytes (shape ${inputTensor.shape}), '
        'got ${inBytes.length} bytes (${input.length} floats).',
      );
    }

    final outBytes = Uint8List(outputTensor.data.length);
    interpreter.run(inBytes, outBytes);

    final out = Float32List(outBytes.length ~/ 4);
    out.setAll(0, Float32List.view(outBytes.buffer));
    return out;
  }

  @override
  Future<void> close() async {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
  }
}
