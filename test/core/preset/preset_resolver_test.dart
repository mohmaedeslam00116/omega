import 'package:flutter_test/flutter_test.dart';
import 'package:omega/core/catalog/catalog_entry.dart';
import 'package:omega/core/preset/human_friendly_preset.dart';

List<CatalogEntry> _mockCatalog() => [
      CatalogEntry(
        id: 'plainusr-x4-int8',
        name: 'PlainUSR 4× (⚡ Lightning INT8)',
        scale: 4,
        type: ModelType.general,
        backend: EngineBackend.mnn,
        tier: ModelTier.fast,
        inputSize: 128,
        fileSize: 311000,
        sha256: '24425fae',
        url: 'https://example.com/plainusr.mnn',
        license: 'BSD-3-Clause',
        version: '1.1.0',
        bundled: false,
      ),
      CatalogEntry(
        id: 'realesr-general-x4v3',
        name: 'General Photo 4×',
        scale: 4,
        type: ModelType.general,
        backend: EngineBackend.tflite,
        tier: ModelTier.balanced,
        inputSize: 128,
        fileSize: 8389964,
        sha256: '86d076d2',
        url: 'https://example.com/general.tflite',
        license: 'BSD-3-Clause',
        version: '1.0.0',
        bundled: true,
      ),
      CatalogEntry(
        id: 'realesr-animevideov3',
        name: 'Anime & Digital Art 4×',
        scale: 4,
        type: ModelType.anime,
        backend: EngineBackend.tflite,
        tier: ModelTier.fast,
        inputSize: 128,
        fileSize: 1271540,
        sha256: '74189d7c',
        url: 'https://example.com/animev3.tflite',
        license: 'BSD-3-Clause',
        version: '1.0.0',
        bundled: true,
      ),
      CatalogEntry(
        id: 'realesr-anime-6b-int8',
        name: 'Anime Pro 4× (6B INT8)',
        scale: 4,
        type: ModelType.anime,
        backend: EngineBackend.mnn,
        tier: ModelTier.balanced,
        inputSize: 128,
        fileSize: 4599808,
        sha256: '3bb23e92',
        url: 'https://example.com/anime6b.mnn',
        license: 'BSD-3-Clause',
        version: '1.0.0',
        bundled: false,
      ),
      CatalogEntry(
        id: 'realesr-x4plus-int8',
        name: 'Ultra Quality 4× (RRDBNet INT8)',
        scale: 4,
        type: ModelType.general,
        backend: EngineBackend.mnn,
        tier: ModelTier.quality,
        inputSize: 128,
        fileSize: 17180132,
        sha256: '4c9bd694',
        url: 'https://example.com/x4plus.mnn',
        license: 'BSD-3-Clause',
        version: '1.0.0',
        bundled: false,
      ),
    ];

void main() {
  group('PresetResolver', () {
    final catalog = _mockCatalog();

    test('resolves Photo + Lightning to PlainUSR MNN model', () {
      final model = PresetResolver.resolveBestModel(
        catalog: catalog,
        contentType: PresetContentType.photo,
        qualityTier: PresetQualityTier.lightning,
        useGpu: true,
      );
      expect(model.id, 'plainusr-x4-int8');
      expect(model.type, ModelType.general);
      expect(model.tier, ModelTier.fast);
    });

    test('resolves Photo + Balanced to General Photo bundled model', () {
      final model = PresetResolver.resolveBestModel(
        catalog: catalog,
        contentType: PresetContentType.photo,
        qualityTier: PresetQualityTier.balanced,
        useGpu: true,
      );
      expect(model.id, 'realesr-general-x4v3');
    });

    test('resolves Photo + Ultra Quality to RRDBNet INT8', () {
      final model = PresetResolver.resolveBestModel(
        catalog: catalog,
        contentType: PresetContentType.photo,
        qualityTier: PresetQualityTier.ultraQuality,
        useGpu: true,
      );
      expect(model.id, 'realesr-x4plus-int8');
      expect(model.tier, ModelTier.quality);
    });

    test('resolves Anime + Lightning to RealESRGAN AnimeVideoV3', () {
      final model = PresetResolver.resolveBestModel(
        catalog: catalog,
        contentType: PresetContentType.anime,
        qualityTier: PresetQualityTier.lightning,
        useGpu: true,
      );
      expect(model.id, 'realesr-animevideov3');
      expect(model.type, ModelType.anime);
    });

    test('resolves Anime + Balanced to Anime 6B INT8', () {
      final model = PresetResolver.resolveBestModel(
        catalog: catalog,
        contentType: PresetContentType.anime,
        qualityTier: PresetQualityTier.balanced,
        useGpu: true,
      );
      expect(model.id, 'realesr-anime-6b-int8');
      expect(model.type, ModelType.anime);
    });

    test('falls back gracefully to bundled model if tier not found', () {
      final model = PresetResolver.resolveBestModel(
        catalog: catalog,
        contentType: PresetContentType.anime,
        qualityTier: PresetQualityTier.ultraQuality, // no anime quality tier in mock
        useGpu: true,
      );
      expect(model.type, ModelType.anime); // falls back to anime
    });
  });
}
