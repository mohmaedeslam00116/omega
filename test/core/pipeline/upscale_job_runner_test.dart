import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:omega/core/pipeline/upscale_job_runner.dart';
import 'package:omega/core/pipeline/upscale_pipeline.dart';

Uint8List _makePng(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(70, 70, 70));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UpscaleJobConfig', () {
    test('carries modelPath + useGpu with sane defaults', () {
      const config = UpscaleJobConfig(modelPath: 'assets/m.tflite');
      expect(config.modelPath, 'assets/m.tflite');
      expect(config.useGpu, true);
      expect(config.tileSize, 128);
      expect(config.overlap, 36);
      expect(config.scale, 4);
      expect(config.engineKind, JobEngineKind.real);
    });
  });

  group('CancelToken', () {
    test('cancel flips the flag once and notifies listeners', () {
      final token = CancelToken();
      var notified = 0;
      token.addListener(() => notified++);
      expect(token.isCancelled, false);
      token.cancel();
      token.cancel();
      expect(token.isCancelled, true);
      expect(notified, 1);
    });
  });

  group('ProgressThrottler', () {
    test('first send passes, rapid sends drop, after interval passes', () {
      var now = DateTime(2026, 1, 1);
      DateTime clock() => now;
      final throttler = ProgressThrottler(minInterval: const Duration(milliseconds: 120));

      expect(throttler.shouldSend(0.1, now: clock), true);
      now = now.add(const Duration(milliseconds: 50));
      expect(throttler.shouldSend(0.2, now: clock), false);
      now = now.add(const Duration(milliseconds: 200));
      expect(throttler.shouldSend(0.3, now: clock), true);
    });
  });

  group('InlineUpscaleJobRunner', () {
    test('runs the job with the stub Engine and reports full progress',
        () async {
      final runner = InlineUpscaleJobRunner();
      final progress = <double>[];
      final out = await runner.run(
        _makePng(256, 256),
        config: const UpscaleJobConfig(modelPath: 'unused'),
        onProgress: progress.add,
      );
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 1024);
      expect(decoded.height, 1024);
      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
    });

    test('honours a cancelled CancelToken between tiles', () async {
      final runner = InlineUpscaleJobRunner();
      final token = CancelToken()..cancel();
      await expectLater(
        runner.run(
          _makePng(256, 256),
          config: const UpscaleJobConfig(modelPath: 'unused'),
          cancelToken: token,
        ),
        throwsA(isA<UpscaleCancelledException>()),
      );
    });
  });

  group('IsolateUpscaleJobRunner', () {
    test('resolveModelPathForWorker copies bundled assets to a real file',
        () async {
      // Bundled assets cannot be read via rootBundle inside the worker
      // Isolate — the runner must materialize them as files on the caller
      // side before spawning.
      final path = await resolveModelPathForWorker(
          'assets/NOTICES',
          tempDirOverride: () async => Directory.systemTemp);
      expect(path, isNot(startsWith('assets/')));
      expect(File(path).existsSync(), true);
      expect(File(path).lengthSync(), greaterThan(0));
      File(path).deleteSync();
    });

    test('resolveModelPathForWorker passes file paths through untouched',
        () async {
      expect(await resolveModelPathForWorker('/cache/models/x.tflite'),
          '/cache/models/x.tflite');
    });

    test('runs a stub job in a fresh Isolate with throttled progress',
        () async {
      final runner = IsolateUpscaleJobRunner();
      final progress = <double>[];
      final out = await runner.run(
        _makePng(256, 256),
        config: const UpscaleJobConfig(modelPath: 'unused', engineKind: JobEngineKind.stub),
        onProgress: progress.add,
      );
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 1024);
      expect(decoded.height, 1024);
      // throttled intermediates + deterministic final tick
      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
    });

    test('honours CancelToken mid-job through the isolate boundary', () async {
      final runner = IsolateUpscaleJobRunner();
      final token = CancelToken();
      final progress = <double>[];
      await expectLater(
        runner.run(
          _makePng(1024, 1024),
          config: const UpscaleJobConfig(modelPath: 'unused', engineKind: JobEngineKind.stub),
          onProgress: (p) {
            progress.add(p);
            if (p > 0.2) token.cancel();
          },
          cancelToken: token,
        ),
        throwsA(isA<UpscaleCancelledException>()),
      );
      expect(progress, isNotEmpty);
    });

    test('propagates worker failures (missing Model)', () async {
      final runner = IsolateUpscaleJobRunner();
      await expectLater(
        runner.run(
          _makePng(64, 64),
          config: const UpscaleJobConfig(
              modelPath: 'assets/models/does-not-exist.tflite'),
        ),
        throwsA(anything),
      );
    });
  });
}