import 'package:flutter/material.dart';
import '../../core/catalog/catalog_entry.dart';
import '../../core/catalog/catalog_service.dart';

class CatalogTab extends StatefulWidget {
  const CatalogTab({super.key});

  @override
  State<CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<CatalogTab> {
  late final CatalogService _service;
  List<CatalogEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Scaffold: load example catalog from asset file string (fake)
    const exampleJson = '''
[
  {
    "id": "realesr-general-x4v3",
    "name": "General Photo 4×",
    "scale": 4,
    "type": "general",
    "inputSize": 128,
    "fileSize": 3670016,
    "sha256": "e614f430e100a1c0b1a2e3d4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5",
    "url": "https://github.com/mohmaedeslam00116/omega-models/releases/download/v1.0.0/realesr-general-x4v3_fp16.tflite",
    "license": "BSD-3-Clause",
    "version": "1.0.0",
    "bundled": true
  },
  {
    "id": "realesr-x4plus",
    "name": "High Quality 4×",
    "scale": 4,
    "type": "general",
    "inputSize": 128,
    "fileSize": 16777216,
    "sha256": "7f954497b9a1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5",
    "url": "https://github.com/mohmaedeslam00116/omega-models/releases/download/v1.0.0/realesr-x4plus_w8a8.tflite",
    "license": "BSD-3-Clause",
    "version": "1.0.0",
    "bundled": false
  }
]
''';
    _service = CatalogServiceStub(exampleJson);
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() => _loading = true);
    final list = await _service.fetchCatalog(forceRefresh: refresh);
    if (mounted) {
      setState(() {
        _entries = list;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Text('Catalog',
                    style: theme.textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  onPressed: () => _load(refresh: true),
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'GitHub Releases • 24h cache • SHA256 verified',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: const Color(0xFF6B7280), fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => _load(refresh: true),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _entries.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final e = _entries[i];
                        final isBundled = e.bundled;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: isBundled
                                        ? const Color(0xFFECFDF5)
                                        : const Color(0xFFF9FAFB),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: isBundled
                                            ? const Color(0xFFA7F3D0)
                                            : const Color(0xFFE5E7EB)),
                                  ),
                                  child: Icon(
                                    isBundled
                                        ? Icons.verified
                                        : Icons.download_outlined,
                                    color: isBundled
                                        ? const Color(0xFF047857)
                                        : const Color(0xFF6B7280),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(e.name,
                                                style: theme.textTheme
                                                    .titleMedium),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isBundled
                                                  ? const Color(0xFFECFDF5)
                                                  : const Color(0xFFF3F4F6),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              isBundled
                                                  ? 'Bundled'
                                                  : 'Download',
                                              style: theme.textTheme.labelLarge
                                                  ?.copyWith(
                                                fontSize: 10,
                                                color: isBundled
                                                    ? const Color(0xFF047857)
                                                    : const Color(0xFF374151),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${e.type.name} • ${e.scale}× • ${e.inputSize}→${e.inputSize * e.scale} per Tile • ${(e.fileSize / 1024 / 1024).toStringAsFixed(1)} MB • ${e.license}',
                                        style:
                                            theme.textTheme.bodyMedium?.copyWith(
                                                color: const Color(0xFF6B7280),
                                                fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
