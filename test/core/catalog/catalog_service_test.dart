import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omega/core/catalog/catalog_service.dart';

void main() {
  const jsonStr = '''
[
  {
    "id": "a",
    "name": "A",
    "scale": 4,
    "type": "general",
    "inputSize": 128,
    "fileSize": 1024,
    "sha256": "abc",
    "url": "https://example.com/a.tflite",
    "license": "BSD-3-Clause",
    "version": "1.0.0",
    "bundled": true
  },
  {
    "id": "b",
    "name": "B",
    "scale": 4,
    "type": "general",
    "inputSize": 128,
    "fileSize": 2048,
    "sha256": "def",
    "url": "https://example.com/b.tflite",
    "license": "BSD-3-Clause",
    "version": "1.0.0",
    "bundled": false
  }
]
''';

  group('CatalogServiceStub', () {
    test('fetchCatalog returns entries and caches 24h', () async {
      final svc = CatalogServiceStub(jsonStr);
      final first = await svc.fetchCatalog();
      expect(first.length, 2);
      final second = await svc.fetchCatalog();
      expect(identical(first, second), true);
    });

    test('forceRefresh bypasses cache', () async {
      final svc = CatalogServiceStub(jsonStr);
      final first = await svc.fetchCatalog();
      final refreshed = await svc.fetchCatalog(forceRefresh: true);
      expect(identical(first, refreshed), false);
      expect(refreshed.length, 2);
    });

    test('getCached returns empty before fetch', () async {
      final svc = CatalogServiceStub(jsonStr);
      expect(await svc.getCached(), isEmpty);
    });
  });

  group('HttpCatalogService', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('omega_catalog_test_');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('fetchCatalog returns 2 entries from example JSON when HTTP mocked',
        () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response(jsonStr, 200);
      });
      final svc = HttpCatalogService(
        client: client,
        catalogUrl: 'https://raw.githubusercontent.com/test/catalog.json',
        getCacheDirOverride: () async => tmp,
      );
      final entries = await svc.fetchCatalog();
      expect(entries.length, 2);
      expect(entries.first.license, 'BSD-3-Clause');
      expect(calls, 1);
    });

    test('24h disk cache respected; second call within window does not hit network',
        () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response(jsonStr, 200);
      });
      final svc = HttpCatalogService(
        client: client,
        catalogUrl: 'https://example.com/catalog.json',
        getCacheDirOverride: () async => tmp,
      );
      final first = await svc.fetchCatalog();
      expect(first.length, 2);
      expect(calls, 1);
      // second call should use memory cache
      final second = await svc.fetchCatalog();
      expect(identical(first, second), true);
      expect(calls, 1);
      // new instance should use disk cache
      final svc2 = HttpCatalogService(
        client: MockClient((_) async {
          calls++;
          return http.Response('[]', 200);
        }),
        catalogUrl: 'https://example.com/catalog.json',
        getCacheDirOverride: () async => tmp,
      );
      final fromDisk = await svc2.fetchCatalog();
      expect(fromDisk.length, 2);
      expect(calls, 1); // not incremented, disk hit
    });

    test('Manual refresh bypasses cache', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response(jsonStr, 200);
      });
      final svc = HttpCatalogService(
        client: client,
        catalogUrl: 'https://example.com/catalog.json',
        getCacheDirOverride: () async => tmp,
      );
      await svc.fetchCatalog();
      expect(calls, 1);
      await svc.fetchCatalog(forceRefresh: true);
      expect(calls, 2);
    });

    test('Parsing validates required fields (scale 4, inputSize 128) and surfaces license',
        () async {
      const badScale = '''
[{"id":"x","name":"n","scale":2,"type":"general","inputSize":128,"fileSize":1,"sha256":"a","url":"u","license":"MIT","version":"1"}]''';
      final client = MockClient((_) async => http.Response(badScale, 200));
      final svc = HttpCatalogService(
        client: client,
        catalogUrl: 'https://example.com/catalog.json',
        getCacheDirOverride: () async => tmp,
      );
      await expectLater(() => svc.fetchCatalog(),
          throwsA(isA<FormatException>()));

      const badInput = '''
[{"id":"x","name":"n","scale":4,"type":"general","inputSize":64,"fileSize":1,"sha256":"a","url":"u","license":"MIT","version":"1"}]''';
      final client2 = MockClient((_) async => http.Response(badInput, 200));
      final svc2 = HttpCatalogService(
        client: client2,
        catalogUrl: 'https://example.com/catalog.json',
        getCacheDirOverride: () async => Directory.systemTemp.createTemp(),
      );
      await expectLater(() => svc2.fetchCatalog(),
          throwsA(isA<FormatException>()));
    });

    test('getCached returns disk entry if memory empty', () async {
      final client = MockClient((_) async => http.Response(jsonStr, 200));
      final svc = HttpCatalogService(
        client: client,
        catalogUrl: 'https://example.com/catalog.json',
        getCacheDirOverride: () async => tmp,
      );
      await svc.fetchCatalog();
      final svc2 = HttpCatalogService(
        client: MockClient((_) async => http.Response('[]', 200)),
        catalogUrl: 'https://example.com/catalog.json',
        getCacheDirOverride: () async => tmp,
      );
      final cached = await svc2.getCached();
      expect(cached.length, 2);
    });
  });
}
