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

    test('infers and parses backend correctly', () {
      final tfliteEntry = CatalogEntry.fromJson({
        'id': 'x',
        'name': 'n',
        'scale': 4,
        'type': 'general',
        'inputSize': 128,
        'fileSize': 1,
        'sha256': 'abc',
        'url': 'https://example.com/model.tflite',
        'license': 'BSD-3-Clause',
        'version': '1'
      });
      expect(tfliteEntry.backend, EngineBackend.tflite);

      final mnnEntry = CatalogEntry.fromJson({
        'id': 'x',
        'name': 'n',
        'scale': 4,
        'type': 'general',
        'inputSize': 128,
        'fileSize': 1,
        'sha256': 'abc',
        'url': 'https://example.com/model.mnn',
        'license': 'BSD-3-Clause',
        'version': '1'
      });
      expect(mnnEntry.backend, EngineBackend.mnn);

      final explicitMnnEntry = CatalogEntry.fromJson({
        'id': 'x',
        'name': 'n',
        'scale': 4,
        'type': 'general',
        'backend': 'mnn',
        'inputSize': 128,
        'fileSize': 1,
        'sha256': 'abc',
        'url': 'https://example.com/model.bin',
        'license': 'BSD-3-Clause',
        'version': '1'
      });
      expect(explicitMnnEntry.backend, EngineBackend.mnn);
      expect(explicitMnnEntry.toJson()['backend'], 'mnn');
    });

    test('parses and infers tier correctly', () {
      final fastEntry = CatalogEntry.fromJson({
        'id': 'fast-model',
        'name': 'Fast Model',
        'scale': 4,
        'type': 'anime',
        'tier': 'fast',
        'inputSize': 128,
        'fileSize': 1271540,
        'sha256': 'abc',
        'url': 'https://example.com/model.mnn',
        'license': 'BSD-3-Clause',
        'version': '1.0.0'
      });
      expect(fastEntry.tier, ModelTier.fast);
      expect(fastEntry.toJson()['tier'], 'fast');

      final inferredFast = CatalogEntry.fromJson({
        'id': 'inferred-fast',
        'name': 'Inferred Fast',
        'scale': 4,
        'type': 'anime',
        'inputSize': 128,
        'fileSize': 2000000,
        'sha256': 'abc',
        'url': 'https://example.com/model.mnn',
        'license': 'BSD-3-Clause',
        'version': '1.0.0'
      });
      expect(inferredFast.tier, ModelTier.fast);

      final inferredQuality = CatalogEntry.fromJson({
        'id': 'inferred-quality',
        'name': 'Inferred Quality',
        'scale': 4,
        'type': 'general',
        'inputSize': 128,
        'fileSize': 17180132,
        'sha256': 'abc',
        'url': 'https://example.com/model.mnn',
        'license': 'BSD-3-Clause',
        'version': '1.0.0'
      });
      expect(inferredQuality.tier, ModelTier.quality);
    });
  });
}
