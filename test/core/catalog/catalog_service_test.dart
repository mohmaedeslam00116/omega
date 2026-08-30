import 'package:flutter_test/flutter_test.dart';
import 'package:omega/core/catalog/catalog_service.dart';

void main() {
  group('CatalogServiceStub', () {
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

    test('fetchCatalog returns entries and caches 24h', () async {
      final svc = CatalogServiceStub(jsonStr);
      final first = await svc.fetchCatalog();
      expect(first.length, 2);
      final second = await svc.fetchCatalog();
      // same instance due to cache
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
}
