import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omega/core/catalog/catalog_entry.dart';
import 'package:omega/core/download/download_manager.dart';

CatalogEntry _entryForContent(
  String id,
  String content, {
  String url = 'https://example.com/a.tflite',
}) {
  final bytes = utf8.encode(content);
  final sha = sha256.convert(bytes).toString();
  return CatalogEntry(
    id: id,
    name: 'Test $id',
    scale: 4,
    type: ModelType.general,
    inputSize: 128,
    fileSize: bytes.length,
    sha256: sha,
    url: url,
    license: 'BSD-3-Clause',
    version: '1.0.0',
  );
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('omega_dl_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('DownloadManager', () {
    test('pathFor returns the local models/<id>.tflite path', () async {
      final entry = _entryForContent('path-test', 'x');
      final mgr = DownloadManagerImpl(
        client: http.Client(),
        getCacheDirOverride: () async => tmp,
      );
      final path = await mgr.pathFor(entry);
      expect(path, endsWith('models/path-test.tflite'));
      expect(path.startsWith(tmp.path), true);
    });

    test('Download shows 0..1 progress and supports cancel', () async {
      const content = 'hello world content for progress';
      final entry = _entryForContent('a', content);
      final progress = <double>[];
      final client = MockClient((req) async {
        return http.Response(content, 200, headers: {
          'content-length': content.length.toString(),
        });
      });
      final mgr = DownloadManagerImpl(
        client: client,
        getCacheDirOverride: () async => tmp,
      );
      final file = await mgr.download(entry, onProgress: progress.add);
      expect(await file.exists(), true);
      expect(progress.isNotEmpty, true);
      expect(progress.last, closeTo(1.0, 0.01));
      expect(progress.first, lessThanOrEqualTo(1.0));
    });

    test('supports cancel via isCancelled', () async {
      // Chunked client to allow mid-stream cancel
      final content = 'abcdefghij' * 10; // 100 bytes
      final entry = _entryForContent('b', content);

      final fakeClient = _ChunkedClient(content, chunkSize: 10);

      final mgr = DownloadManagerImpl(
        client: fakeClient,
        getCacheDirOverride: () async => tmp,
      );

      var callCount = 0;
      bool isCancelled() {
        callCount++;
        return callCount > 2; // cancel after 2 progress calls
      }

      await expectLater(
        () => mgr.download(entry,
            onProgress: (_) {}, isCancelled: isCancelled),
        throwsA(isA<CancelledException>()),
      );
    });

    test('Resume via Range header after interruption', () async {
      final fullContent = '0123456789ABCDEF' * 4; // 64 bytes
      final entry = _entryForContent('c', fullContent);
      // Simulate partial file exists (first 20 bytes)
      final modelsDir = Directory('${tmp.path}/models');
      await modelsDir.create(recursive: true);
      final file = File('${modelsDir.path}/c.tflite');
      await file.writeAsString(fullContent.substring(0, 20));

      String? capturedRange;
      final client = MockClient((req) async {
        capturedRange = req.headers['Range'];
        // If Range present, return remaining content
        if (capturedRange != null) {
          final remaining = fullContent.substring(20);
          return http.Response(remaining, 206, headers: {
            'content-length': remaining.length.toString(),
            'content-range': 'bytes 20-63/64',
          });
        }
        return http.Response(fullContent, 200);
      });

      final mgr = DownloadManagerImpl(
        client: client,
        getCacheDirOverride: () async => tmp,
      );
      final result = await mgr.download(entry);
      expect(capturedRange, 'bytes=20-');
      expect(await result.readAsString(), fullContent);
    });

    test('SHA256 mismatch -> file deleted, error, retry succeeds', () async {
      const content = 'correct content';
      final wrongSha =
          '0000000000000000000000000000000000000000000000000000000000000000';
      final entryWrong = CatalogEntry(
        id: 'd',
        name: 'd',
        scale: 4,
        type: ModelType.general,
        inputSize: 128,
        fileSize: content.length,
        sha256: wrongSha,
        url: 'https://example.com/d.tflite',
        license: 'BSD-3-Clause',
        version: '1.0.0',
      );
      final client = MockClient((_) async => http.Response(content, 200));
      final mgr = DownloadManagerImpl(
        client: client,
        getCacheDirOverride: () async => tmp,
      );
      await expectLater(() => mgr.download(entryWrong),
          throwsA(isA<FormatException>()));
      // file should be deleted
      final file = File('${tmp.path}/models/d.tflite');
      expect(await file.exists(), false);

      // retry with correct hash succeeds
      final correctEntry = _entryForContent('d', content);
      final file2 = await mgr.download(correctEntry);
      expect(await file2.exists(), true);
      expect(await file2.readAsString(), content);
    });

    test('Delete removes file; clear cache empties models/', () async {
      const c1 = 'content1';
      const c2 = 'content2';
      final client = MockClient((req) async {
        if (req.url.toString().contains('e1')) return http.Response(c1, 200);
        return http.Response(c2, 200);
      });
      // Use separate URLs to distinguish, so create entries with matching URLs
      final e1url = CatalogEntry(
        id: 'e1',
        name: 'e1',
        scale: 4,
        type: ModelType.general,
        inputSize: 128,
        fileSize: c1.length,
        sha256: sha256.convert(utf8.encode(c1)).toString(),
        url: 'https://example.com/e1.tflite',
        license: 'BSD-3-Clause',
        version: '1.0.0',
      );
      final e2url = CatalogEntry(
        id: 'e2',
        name: 'e2',
        scale: 4,
        type: ModelType.general,
        inputSize: 128,
        fileSize: c2.length,
        sha256: sha256.convert(utf8.encode(c2)).toString(),
        url: 'https://example.com/e2.tflite',
        license: 'BSD-3-Clause',
        version: '1.0.0',
      );

      final mgr = DownloadManagerImpl(
        client: client,
        getCacheDirOverride: () async => tmp,
      );
      await mgr.download(e1url);
      await mgr.download(e2url);
      expect(await File('${tmp.path}/models/e1.tflite').exists(), true);
      expect(await File('${tmp.path}/models/e2.tflite').exists(), true);

      await mgr.delete('e1');
      expect(await File('${tmp.path}/models/e1.tflite').exists(), false);
      expect(await File('${tmp.path}/models/e2.tflite').exists(), true);

      await mgr.clearCache();
      expect(await Directory('${tmp.path}/models').exists(), true);
      final remaining = await Directory('${tmp.path}/models')
          .list()
          .where((e) => e is File)
          .toList();
      expect(remaining, isEmpty);
    });

    test('Cache limit 500MB enforced (test via fake file sizes)', () async {
      // Use small limit 20 bytes for test
      const c1 = '1234567890'; // 10
      const c2 = 'abcdefghij'; // 10
      const c3 = 'KLMNOPQRST'; // 10 -> total 30 > 20, oldest evicted

      final client = MockClient((req) async {
        final url = req.url.toString();
        if (url.contains('f1')) return http.Response(c1, 200);
        if (url.contains('f2')) return http.Response(c2, 200);
        return http.Response(c3, 200);
      });

      final mgr = DownloadManagerImpl(
        client: client,
        getCacheDirOverride: () async => tmp,
        cacheLimitBytes: 20,
      );

      // Need entries with matching URLs
      final en1 = CatalogEntry(
          id: 'f1',
          name: 'f1',
          scale: 4,
          type: ModelType.general,
          inputSize: 128,
          fileSize: c1.length,
          sha256: sha256.convert(utf8.encode(c1)).toString(),
          url: 'https://example.com/f1.tflite',
          license: 'BSD-3-Clause',
          version: '1.0.0');
      final en2 = CatalogEntry(
          id: 'f2',
          name: 'f2',
          scale: 4,
          type: ModelType.general,
          inputSize: 128,
          fileSize: c2.length,
          sha256: sha256.convert(utf8.encode(c2)).toString(),
          url: 'https://example.com/f2.tflite',
          license: 'BSD-3-Clause',
          version: '1.0.0');
      final en3 = CatalogEntry(
          id: 'f3',
          name: 'f3',
          scale: 4,
          type: ModelType.general,
          inputSize: 128,
          fileSize: c3.length,
          sha256: sha256.convert(utf8.encode(c3)).toString(),
          url: 'https://example.com/f3.tflite',
          license: 'BSD-3-Clause',
          version: '1.0.0');

      await mgr.download(en1);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await mgr.download(en2);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Both f1 and f2 should exist (20 bytes total)
      expect(await File('${tmp.path}/models/f1.tflite').exists(), true);
      expect(await File('${tmp.path}/models/f2.tflite').exists(), true);

      await mgr.download(en3);
      // After f3, total would be 30 >20, oldest (f1) evicted
      final existsF1 = await File('${tmp.path}/models/f1.tflite').exists();
      final existsF2 = await File('${tmp.path}/models/f2.tflite').exists();
      final existsF3 = await File('${tmp.path}/models/f3.tflite').exists();
      expect(existsF3, true);
      // f1 should be gone, f2 and f3 remain (20 bytes)
      expect(existsF1, false);
      expect(existsF2, true);
    });
  });
}

class _ChunkedClient extends http.BaseClient {
  final String content;
  final int chunkSize;
  _ChunkedClient(this.content, {this.chunkSize = 10});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = utf8.encode(content);
    final stream = Stream.fromIterable([
      for (var i = 0; i < bytes.length; i += chunkSize)
        Uint8List.fromList(
            bytes.sublist(i, (i + chunkSize).clamp(0, bytes.length)))
    ]);
    return http.StreamedResponse(
      stream,
      200,
      contentLength: bytes.length,
      headers: {'content-type': 'application/octet-stream'},
      request: request,
    );
  }
}
