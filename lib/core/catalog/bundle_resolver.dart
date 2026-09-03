import 'catalog_entry.dart';

/// Result of evaluating a [ModelBundle]'s availability on local storage.
class BundleResolutionResult {
  final ModelBundle bundle;
  final bool isReady;
  final List<CatalogEntry> missingEntries;
  final List<CatalogEntry> presentEntries;

  const BundleResolutionResult({
    required this.bundle,
    required this.isReady,
    required this.missingEntries,
    required this.presentEntries,
  });

  int get totalSizeToDownload =>
      missingEntries.fold<int>(0, (sum, entry) => sum + entry.fileSize);
}

/// Evaluates whether a [ModelBundle] has all its required models downloaded,
/// and identifies missing delta models.
class BundleResolver {
  static BundleResolutionResult resolve({
    required ModelBundle bundle,
    required List<CatalogEntry> catalog,
    required bool Function(String modelId) isModelDownloaded,
  }) {
    final missing = <CatalogEntry>[];
    final present = <CatalogEntry>[];

    for (final id in bundle.modelIds) {
      final entry = catalog.cast<CatalogEntry?>().firstWhere(
            (e) => e?.id == id,
            orElse: () => null,
          );
      if (entry == null) {
        throw StateError(
          'Model "$id" required by bundle "${bundle.id}" is missing from catalog.',
        );
      }
      if (isModelDownloaded(id)) {
        present.add(entry);
      } else {
        missing.add(entry);
      }
    }

    return BundleResolutionResult(
      bundle: bundle,
      isReady: missing.isEmpty,
      missingEntries: missing,
      presentEntries: present,
    );
  }
}
