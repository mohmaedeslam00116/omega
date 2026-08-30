import 'package:flutter_test/flutter_test.dart';
import 'package:omega/core/catalog/catalog_entry.dart';

void main() {
  group('CatalogEntry', () {
    const jsonStr = '''
[
  {
    "id": "realesr-general-x4v3",
    "name": "General Photo 4x",
    "scale": 4,
    "type": "general",
    "inputSize": 128,
    "fileSize": 3670016,
    "sha256": "e614f430e100a1c0b1a2e3d4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5",
    "url": "https://example.com/a.tflite",
    "license": "BSD-3-Clause",
    "version": "1.0.0",
    "bundled": true
  }
]
''';

    test('parses from JSON and round-trips', () {
      final entries = CatalogEntry.listFromJson(jsonStr);
      expect(entries.length, 1);
      final e = entries.first;
      expect(e.id, 'realesr-general-x4v3');
      expect(e.scale, 4);
      expect(e.type, ModelType.general);
      expect(e.inputSize, 128);
      expect(e.bundled, true);
      expect(e.toJson()['id'], 'realesr-general-x4v3');
    });

    test('throws on unknown type', () {
      expect(
        () => CatalogEntry.fromJson({
          'id': 'x',
          'name': 'n',
          'scale': 4,
          'type': 'unknown',
          'inputSize': 128,
          'fileSize': 1,
          'sha256': 'abc',
          'url': 'u',
          'license': 'MIT',
          'version': '1'
        }),
        throwsArgumentError,
      );
    });

    test('validates scale must be 4', () {
      expect(
        () => CatalogEntry.fromJson({
          'id': 'x',
          'name': 'n',
          'scale': 2,
          'type': 'general',
          'inputSize': 128,
          'fileSize': 1,
          'sha256': 'abc',
          'url': 'u',
          'license': 'MIT',
          'version': '1'
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('validates inputSize must be 128', () {
      expect(
        () => CatalogEntry.fromJson({
          'id': 'x',
          'name': 'n',
          'scale': 4,
          'type': 'general',
          'inputSize': 64,
          'fileSize': 1,
          'sha256': 'abc',
          'url': 'u',
          'license': 'MIT',
          'version': '1'
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('validates license not empty and surfaces it', () {
      final e = CatalogEntry.fromJson({
        'id': 'x',
        'name': 'n',
        'scale': 4,
        'type': 'general',
        'inputSize': 128,
        'fileSize': 1,
        'sha256': 'abc',
        'url': 'u',
        'license': 'BSD-3-Clause',
        'version': '1'
      });
      expect(e.license, 'BSD-3-Clause');
      expect(
        () => CatalogEntry.fromJson({
          'id': 'x',
          'name': 'n',
          'scale': 4,
          'type': 'general',
          'inputSize': 128,
          'fileSize': 1,
          'sha256': 'abc',
          'url': 'u',
          'license': '',
          'version': '1'
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
