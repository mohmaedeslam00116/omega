import 'dart:io';
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'tflite_engine.dart';

/// Real implementation wrapping tflite_flutter Interpreter.
/// Used in production (Ticket 04), while TfliteEngineStub is used in tests.
/// Handles GpuDelegateV2 with XNNPACK CPU fallback (4 threads).
///
/// Some TFLite models (e.g. Real-ESRGAN fp16 converted via PyTorch → ONNX →
/// TFLite) contain dozens of "input" tensors that are really unfused constant
/// parameters. Only tensor 0 is the actual image input; the rest must be
/// zero-filled before the first invoke or TFLite will error with
/// "Input tensor N lacks data".
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

      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();
      print('[TFLite] Inputs count: ${inputTensors.length}, Outputs count: ${outputTensors.length}');
      for (var i = 0; i < inputTensors.length; i++) {
        final t = inputTensors[i];
        print('[TFLite] Input $i: name="${t.name}", shape=${t.shape}, type=${t.type}, bytes=${t.numBytes()}');
      }

      // Zero-fill all secondary input tensors (unfused constants from model conversion)
      for (var i = 1; i < inputTensors.length; i++) {
        final t = inputTensors[i];
        final size = t.numBytes();
        if (size > 0) {
          t.setTo(Uint8List(size));
        }
      }

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
    if (inBytes.length != inputTensor.numBytes()) {
      throw ArgumentError(
        'Input tensor size mismatch: Model expects '
        '${inputTensor.numBytes()} bytes (shape ${inputTensor.shape}), '
        'got ${inBytes.length} bytes (${input.length} floats).',
      );
    }

    // Set data directly on tensor 0 and invoke — bypasses interpreter.run()
    // which only fills the first N inputs from its list arg, leaving the
    // secondary constant tensors (already zero-filled at load time) untouched.
    print('[TFLite] infer: setting input 0 with ${inBytes.length} bytes');
    inputTensor.setTo(inBytes);
    print('[TFLite] infer: calling invoke()...');
    interpreter.invoke();
    print('[TFLite] infer: invoke() succeeded');

    // Copy output bytes out.
    final outBytes = Uint8List(outputTensor.numBytes());
    outputTensor.copyTo(outBytes);

    final rawFloats = Float32List.view(outBytes.buffer);

    // Safeguard: If the model outputs NCHW [1, 3, H, W], transpose to NHWC [H, W, 3]
    final shape = outputTensor.shape;
    if (shape.length == 4 && shape[1] == 3) {
      final h = shape[2];
      final w = shape[3];
      final plane = h * w;
      final nhwc = Float32List(plane * 3);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final idx = y * w + x;
          final outIdx = idx * 3;
          nhwc[outIdx] = rawFloats[idx]; // R
          nhwc[outIdx + 1] = rawFloats[plane + idx]; // G
          nhwc[outIdx + 2] = rawFloats[2 * plane + idx]; // B
        }
      }
      return nhwc;
    }

    final out = Float32List(rawFloats.length);
    out.setAll(0, rawFloats);
    return out;
  }

  @override
  Future<void> close() async {
    _interpreter?.close();
    _interpreter = null;
    _isLoaded = false;
  }
}
