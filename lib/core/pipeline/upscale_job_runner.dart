import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../engine/tflite_engine.dart';
import '../engine/tflite_engine_impl.dart';
import 'upscale_pipeline.dart';

/// Which Engine implementation the worker builds inside the Isolate.
/// `real` wraps the on-device TFLite Interpreter; `stub` runs the
/// deterministic in-process emulation (tests and environments without
/// native TFLite).
enum JobEngineKind { real, stub }

/// Immutable, Isolate-sendable configuration for one [UpscaleJob].
class UpscaleJobConfig {
  final String modelPath;
  final bool useGpu;
  final int tileSize;
  final int overlap;
  final int scale;
  final JobEngineKind engineKind;

  const UpscaleJobConfig({
    required this.modelPath,
    this.useGpu = false,
    this.tileSize = 128,
    this.overlap = 36,
    this.scale = 4,
    this.engineKind = JobEngineKind.real,
  });
}

/// UI-facing handle to abort a running UpscaleJob. Safe to cancel several
/// times and after the job already finished (no-op).
class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void addListener(void Function() listener) => _listeners.add(listener);

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}

/// Drops progress callbacks closer together than [minInterval] so a worker
/// inside an Isolate does not flood the UI isolate.
class ProgressThrottler {
  final Duration minInterval;
  DateTime? _last;

  ProgressThrottler({this.minInterval = const Duration(milliseconds: 120)});

  bool shouldSend(double progress, {DateTime Function()? now}) {
    final t = (now ?? DateTime.now)();
    final last = _last;
    if (last == null || t.difference(last) >= minInterval) {
      _last = t;
      return true;
    }
    return false;
  }
}

/// Seam for executing one UpscaleJob. Production uses
/// [IsolateUpscaleJobRunner]; tests use [InlineUpscaleJobRunner].
abstract class UpscaleJobRunner {
  Future<Uint8List> run(
    Uint8List imageBytes, {
    required UpscaleJobConfig config,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  });
}

/// Worker core: builds [engineFactory]'s Engine, applies the config, runs the
/// pipeline. Called inside the spawned Isolate by [IsolateUpscaleJobRunner]
/// and directly (in-process) by [InlineUpscaleJobRunner] and tests.
Future<Uint8List> runUpscaleWithEngine(
  Uint8List imageBytes, {
  required UpscaleJobConfig config,
  required TfliteEngine Function() engineFactory,
  void Function(double progress)? onProgress,
  CancelToken? cancelToken,
}) async {
  final engine = engineFactory();
  await engine.setUseGpu(config.useGpu);
  await engine.load(config.modelPath);
  final pipeline = UpscalePipeline(
    engine: engine,
    tileSize: config.tileSize,
    overlap: config.overlap,
    scale: config.scale,
  );
  try {
    return await pipeline.upscale(
      imageBytes,
      onProgress: onProgress,
      isCancelled: cancelToken == null ? null : () => cancelToken.isCancelled,
    );
  } finally {
    await engine.close();
  }
}

/// Runs the job on the CURRENT isolate — the seam tests use (stub Engine,
/// no Isolate boundary, unthrottled progress).
class InlineUpscaleJobRunner implements UpscaleJobRunner {
  final TfliteEngine Function() engineFactory;

  InlineUpscaleJobRunner({TfliteEngine Function()? engineFactory})
      : engineFactory = engineFactory ?? TfliteEngineStub.new;

  @override
  Future<Uint8List> run(
    Uint8List imageBytes, {
    required UpscaleJobConfig config,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) {
    return runUpscaleWithEngine(
      imageBytes,
      config: config,
      engineFactory: engineFactory,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }
}

/// Bundled assets (`assets/...`) cannot be read via rootBundle inside the
/// worker Isolate — there is no Flutter binding there. Materialize them as
/// real files on the caller side first; file paths pass through untouched.
Future<String> resolveModelPathForWorker(
  String modelPath, {
  Future<Directory> Function()? tempDirOverride,
}) async {
  if (!modelPath.startsWith('assets/')) return modelPath;
  final data = await rootBundle.load(modelPath);
  final dir = await (tempDirOverride ?? getTemporaryDirectory)();
  final file = File('${dir.path}/models/${modelPath.split('/').last}');
  await file.create(recursive: true);
  await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  return file.path;
}

/// Spawns a FRESH Isolate per UpscaleJob (ADR-0007). The Engine is
/// constructed inside the Isolate from [UpscaleJobConfig.modelPath] +
/// [UpscaleJobConfig.useGpu]; progress crosses back time-throttled (~120ms)
/// and cancellation flows in through a handshake port. The worker closes its
/// Engine when the job ends, so every job starts from a clean slate.
class IsolateUpscaleJobRunner implements UpscaleJobRunner {
  static const _minProgressInterval = Duration(milliseconds: 120);

  @override
  Future<Uint8List> run(
    Uint8List imageBytes, {
    required UpscaleJobConfig config,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final progressPort = ReceivePort();
    SendPort? cancelSend;
    var pendingCancel = false;

    if (cancelToken != null) {
      cancelToken.addListener(() {
        final send = cancelSend;
        if (send != null) {
          send.send('cancel');
        } else {
          // Cancel arrived before the worker handshake — deliver it as soon
          // as the channel is up.
          pendingCancel = true;
        }
      });
    }

    // Only sendable values are captured by the worker closure below:
    // a SendPort, the image bytes and the config.
    final progressSend = progressPort.sendPort;
    // Bundled assets must be materialized to files on THIS side — the worker
    // has no Flutter binding to read rootBundle.
    final workerPath = await resolveModelPathForWorker(config.modelPath);
    final workerConfig = UpscaleJobConfig(
      modelPath: workerPath,
      useGpu: config.useGpu,
      tileSize: config.tileSize,
      overlap: config.overlap,
      scale: config.scale,
      engineKind: config.engineKind,
    );

    final future = Isolate.run(() async {
      final workerCancel = ReceivePort();
      final localToken = CancelToken();
      workerCancel.listen((_) => localToken.cancel());
      // Handshake: hand the main isolate our cancel channel.
      progressSend.send(['port', workerCancel.sendPort]);

      final throttler = ProgressThrottler(minInterval: _minProgressInterval);
      return runUpscaleWithEngine(
        imageBytes,
        config: workerConfig,
        engineFactory: config.engineKind == JobEngineKind.real
            ? TfliteEngineImpl.new
            : TfliteEngineStub.new,
        onProgress: (p) {
          // The final tick is emitted by the caller after completion, so it
          // cannot race with this port closing.
          if (p < 1.0 && throttler.shouldSend(p)) {
            progressSend.send(['progress', p]);
          }
        },
        cancelToken: localToken,
      );
    });

    progressPort.listen((message) {
      if (message is List && message.isNotEmpty) {
        if (message[0] == 'port') {
          cancelSend = message[1] as SendPort;
          if (pendingCancel) cancelSend!.send('cancel');
        } else if (message[0] == 'progress') {
          onProgress?.call(message[1] as double);
        }
      }
    });

    try {
      final result = await future;
      onProgress?.call(1.0);
      return result;
    } finally {
      progressPort.close();
    }
  }
}