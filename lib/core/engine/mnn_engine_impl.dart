import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'tflite_engine.dart';

// Native C signatures
typedef _MnnCreateNative = Pointer<Void> Function(
    Pointer<Utf8> modelPath, Int32 forwardType, Int32 precisionMode, Int32 numThreads);
typedef _MnnCreateDart = Pointer<Void> Function(
    Pointer<Utf8> modelPath, int forwardType, int precisionMode, int numThreads);

typedef _MnnResizeNative = Int32 Function(
    Pointer<Void> ctx, Int32 batch, Int32 channels, Int32 height, Int32 width);
typedef _MnnResizeDart = int Function(
    Pointer<Void> ctx, int batch, int channels, int height, int width);

typedef _MnnInferNative = Int32 Function(
    Pointer<Void> ctx, Pointer<Float> inputData, Pointer<Float> outputData);
typedef _MnnInferDart = int Function(
    Pointer<Void> ctx, Pointer<Float> inputData, Pointer<Float> outputData);

typedef _MnnDestroyNative = Void Function(Pointer<Void> ctx);
typedef _MnnDestroyDart = void Function(Pointer<Void> ctx);

/// MNN Engine implementation supporting Vulkan & OpenCL GPU acceleration via Dart FFI.
/// Fulfills the [TfliteEngine] interface contract (NHWC float32 tensors).
class MnnEngineImpl implements TfliteEngine {
  static DynamicLibrary? _lib;
  static bool _libLoaded = false;

  static DynamicLibrary? get _dynamicLib {
    if (!_libLoaded) {
      _libLoaded = true;
      try {
        if (Platform.isAndroid) {
          _lib = DynamicLibrary.open('libomega_mnn.so');
        } else {
          _lib = DynamicLibrary.process();
        }
      } catch (_) {
        _lib = null;
      }
    }
    return _lib;
  }

  Pointer<Void>? _ctx;
  bool _useGpu = true;
  int _lastSide = 0;
  final int _scale = 4;
  String? _modelPath;

  @override
  bool get isLoaded => _ctx != null && _ctx != nullptr;

  @override
  bool get useGpu => _useGpu;

  @override
  Future<void> setUseGpu(bool useGpu) async {
    _useGpu = useGpu;
    if (isLoaded && _modelPath != null) {
      final path = _modelPath!;
      await close();
      await load(path);
    }
  }

  @override
  Future<void> load(String modelPath) async {
    _modelPath = modelPath;
    if (isLoaded) await close();

    final lib = _dynamicLib;
    if (lib == null) {
      throw UnsupportedError(
        'MNN native library (libomega_mnn.so) is not available on this platform.',
      );
    }

    final mnnCreate =
        lib.lookupFunction<_MnnCreateNative, _MnnCreateDart>('omega_mnn_create');

    final pathPtr = modelPath.toNativeUtf8();
    try {
      // ForwardType: 3 = Vulkan, 2 = OpenCL, 0 = CPU. Precision: 2 = Low (FP16).
      final forwardType = _useGpu ? 3 : 0;
      _ctx = mnnCreate(pathPtr, forwardType, 2, 4);
      if (_ctx == null || _ctx == nullptr) {
        throw StateError('Failed to initialize MNN context for: ');
      }
    } finally {
      calloc.free(pathPtr);
    }
  }

  @override
  Future<Float32List> infer(Float32List input) async {
    final ctx = _ctx;
    if (!isLoaded || ctx == null) throw StateError('MNN Engine not loaded');

    final lib = _dynamicLib!;
    final mnnResize =
        lib.lookupFunction<_MnnResizeNative, _MnnResizeDart>('omega_mnn_resize_input');
    final mnnInfer =
        lib.lookupFunction<_MnnInferNative, _MnnInferDart>('omega_mnn_infer');

    final side = math.sqrt(input.length / 3).round();
    if (side * side * 3 != input.length) {
      throw ArgumentError('Input must be NHWC [1,N,N,3]');
    }

    if (side != _lastSide) {
      final code = mnnResize(ctx, 1, 3, side, side);
      if (code != 0) throw StateError('Failed to resize MNN session: ');
      _lastSide = side;
    }

    final outSide = side * _scale;
    final outLength = outSide * outSide * 3;

    final inputPtr = calloc<Float>(input.length);
    final outputPtr = calloc<Float>(outLength);

    try {
      inputPtr.asTypedList(input.length).setAll(0, input);

      final code = mnnInfer(ctx, inputPtr, outputPtr);
      if (code != 0) throw StateError('MNN inference failed with code: ');

      final result = Float32List(outLength);
      result.setAll(0, outputPtr.asTypedList(outLength));
      return result;
    } finally {
      calloc.free(inputPtr);
      calloc.free(outputPtr);
    }
  }

  @override
  Future<void> close() async {
    final ctx = _ctx;
    if (ctx != null && ctx != nullptr) {
      final lib = _dynamicLib;
      if (lib != null) {
        final mnnDestroy =
            lib.lookupFunction<_MnnDestroyNative, _MnnDestroyDart>('omega_mnn_destroy');
        mnnDestroy(ctx);
      }
      _ctx = null;
      _lastSide = 0;
      _modelPath = null;
    }
  }
}
