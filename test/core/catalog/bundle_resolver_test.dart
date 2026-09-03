import 'package:flutter_test/flutter_test.dart';
import 'package:omega/core/catalog/bundle_resolver.dart';
import 'package:omega/core/catalog/catalog_entry.dart';

void main() {
  group('CatalogEntry with Roles', () {
    test('parses role field correctly and defaults to upscale', () {
      final jsonDenoise = {
        'id': 'nafnet-tiny',
        'name': 'NAFNet Tiny',
        'scale': 1,
        'type': 'general',
        'role': 'denoise',
        'backend': 'mnn',
        'tier': 'fast',
        'inputSize': 128,
        'fileSize': 400000,
        'sha256': 'abc123',
        'url': 'https://example.com/nafnet.mnn',
        'license': 'MIT',
        'version': '1.0.0',
      };
      final entry = CatalogEntry.fromJson(jsonDenoise);
      expect(entry.role, ModelRole.denoise);
      expect(entry.scale, 1);
      expect(entry.toJson()['role'], 'denoise');
    });
  });

  group('ModelBundle and BundleResolver', () {
    final catalog = [
      const CatalogEntry(
        id: 'nafnet-tiny',
        name: 'NAFNet Tiny',
        scale: 1,
        type: ModelType.general,
        role: ModelRole.denoise,
        inputSize: 128,
        fileSize: 400000,
        sha256: 'a1',
        url: 'https://example.com/a1.mnn',
        license: 'MIT',
        version: '1.0',
      ),
      const CatalogEntry(
        id: 'safmn-x4',
        name: 'SAFMN x4',
        scale: 4,
        type: ModelType.anime,
        role: ModelRole.upscale,
        inputSize: 128,
        fileSize: 260000,
        sha256: 'a2',
        url: 'https://example.com/a2.mnn',
        license: 'MIT',
        version: '1.0',
      ),
      const CatalogEntry(
        id: 'animeline-sharpen',
        name: 'Anime Line Sharpen',
        scale: 1,
        type: ModelType.anime,
        role: ModelRole.lineRefine,
        inputSize: 128,
        fileSize: 70000,
        sha256: 'a3',
        url: 'https://example.com/a3.mnn',
        license: 'MIT',
        version: '1.0',
      ),
    ];

    const animeBundle = ModelBundle(
      id: 'anime-task-bundle',
      name: 'Anime Task Bundle',
      taskType: TaskType.anime,
      modelIds: ['nafnet-tiny', 'safmn-x4', 'animeline-sharpen'],
    );

    test('returns isReady: true when all bundle models are downloaded', () {
      final res = BundleResolver.resolve(
        bundle: animeBundle,
        catalog: catalog,
        isModelDownloaded: (id) => true,
      );
      expect(res.isReady, isTrue);
      expect(res.missingEntries, isEmpty);
      expect(res.presentEntries.length, 3);
      expect(res.totalSizeToDownload, 0);
    });

    test('returns missing delta entries when partially downloaded', () {
      final res = BundleResolver.resolve(
        bundle: animeBundle,
        catalog: catalog,
        isModelDownloaded: (id) => id == 'safmn-x4',
      );
      expect(res.isReady, isFalse);
      expect(res.presentEntries.map((e) => e.id), ['safmn-x4']);
      expect(
        res.missingEntries.map((e) => e.id),
        ['nafnet-tiny', 'animeline-sharpen'],
      );
      expect(res.totalSizeToDownload, 400000 + 70000);
    });

    test('throws StateError when a bundle model ID is not in catalog', () {
      const invalidBundle = ModelBundle(
        id: 'bad-bundle',
        name: 'Bad',
        taskType: TaskType.general,
        modelIds: ['unknown-model'],
      );
      expect(
        () => BundleResolver.resolve(
          bundle: invalidBundle,
          catalog: catalog,
          isModelDownloaded: (id) => false,
        ),
        throwsStateError,
      );
    });
  });
}
