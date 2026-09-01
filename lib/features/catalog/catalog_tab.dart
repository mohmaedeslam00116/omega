import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/catalog/catalog_entry.dart';
import '../../core/catalog/catalog_service.dart';
import '../../core/download/download_manager.dart';

class CatalogTab extends StatefulWidget {
  final CatalogService? catalogService;
  final DownloadManager? downloadManager;

  const CatalogTab({
    super.key,
    this.catalogService,
    this.downloadManager,
  });

  @override
  State<CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<CatalogTab> {
  late final CatalogService _catalogService;
  late final DownloadManager _downloadManager;

  List<CatalogEntry> _entries = [];
  bool _loading = true;
  final Map<String, double> _progress = {};
  final Set<String> _downloaded = {};



  @override
  void initState() {
    super.initState();
    // Default: stub catalog + real download manager (with http client)
    const exampleJson = '''
[
  {
    "id": "realesr-general-x4v3",
    "name": "General Photo 4×",
    "scale": 4,
    "type": "general",
    "tier": "balanced",
    "inputSize": 128,
    "fileSize": 8389964,
    "sha256": "86d076d2acce51190d41cfdde3acdc431c2861dd747f5707cc65003a2e2c5814",
    "url": "https://github.com/mohmaedeslam00116/omega-models/releases/download/v1.0.0/realesr-general-x4v3_fp16.tflite",
    "license": "BSD-3-Clause",
    "version": "1.0.0",
    "bundled": true
  },
  {
    "id": "realesr-animevideov3",
    "name": "Anime & Digital Art 4×",
    "scale": 4,
    "type": "anime",
    "tier": "fast",
    "inputSize": 128,
    "fileSize": 1271540,
    "sha256": "74189d7c0b8e7aafcfef3038e5f76d7d73b28d19327e82f28cb43d179cc5be99",
    "url": "https://github.com/mohmaedeslam00116/omega-models/releases/download/v1.0.0/realesr-animevideov3_fp16.tflite",
    "license": "BSD-3-Clause",
    "version": "1.0.0",
    "bundled": true
  },
  {
    "id": "realesr-anime-6b-int8",
    "name": "Anime Pro 4× (6B INT8)",
    "scale": 4,
    "type": "anime",
    "backend": "mnn",
    "tier": "balanced",
    "inputSize": 128,
    "fileSize": 4599808,
    "sha256": "3bb23e924541b7df75ac147c6baec44ed822a21917da7f77873d66db69f036f8",
    "url": "https://github.com/mohmaedeslam00116/omega-models/releases/download/v1.0.0/RealESRGAN_x4plus_anime_6B_int8.mnn",
    "license": "BSD-3-Clause",
    "version": "1.0.0",
    "bundled": false
  },
  {
    "id": "realesr-x4plus-int8",
    "name": "Ultra Quality 4× (RRDBNet INT8)",
    "scale": 4,
    "type": "general",
    "backend": "mnn",
    "tier": "quality",
    "inputSize": 128,
    "fileSize": 17180132,
    "sha256": "4c9bd6946666a1ec62d622d60847166c31394d6d741d43d5f83eb3ef11e68ab8",
    "url": "https://github.com/mohmaedeslam00116/omega-models/releases/download/v1.0.0/RealESRGAN_x4plus_int8.mnn",
    "license": "BSD-3-Clause",
    "version": "1.0.0",
    "bundled": false
  },
  {
    "id": "realesr-x4plus-fp16",
    "name": "Ultra Quality 4× (RRDBNet FP16)",
    "scale": 4,
    "type": "general",
    "backend": "mnn",
    "tier": "quality",
    "inputSize": 128,
    "fileSize": 33660484,
    "sha256": "719a4e97ef9780599235f0b9a287f4f51c96e5e20d3a01d89bd093f4ab96731f",
    "url": "https://github.com/mohmaedeslam00116/omega-models/releases/download/v1.0.0/RealESRGAN_x4plus_fp16.mnn",
    "license": "BSD-3-Clause",
    "version": "1.0.0",
    "bundled": false
  }
]
''';
    _catalogService =
        widget.catalogService ?? CatalogServiceStub(exampleJson);
    _downloadManager =
        widget.downloadManager ?? DownloadManagerImpl(client: http.Client());
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() => _loading = true);
    try {
      final list = await _catalogService.fetchCatalog(forceRefresh: refresh);
      // Check downloaded state for each entry (with timeout for test env)
      final downloaded = <String>{};
      for (final e in list) {
        if (!e.bundled) {
          try {
            final isDl = await _downloadManager
                .isDownloaded(e.id)
                .timeout(const Duration(milliseconds: 200),
                    onTimeout: () => false);
            if (isDl) downloaded.add(e.id);
          } catch (_) {}
        }
      }
      if (mounted) {
        setState(() {
          _entries = list;
          _downloaded
            ..clear()
            ..addAll(downloaded);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to load catalog: $e')));
      }
    }
  }

  Future<void> _download(CatalogEntry entry) async {
    setState(() => _progress[entry.id] = 0);
    try {
      await _downloadManager.download(
        entry,
        onProgress: (p) {
          if (mounted) setState(() => _progress[entry.id] = p);
        },
      );
      if (mounted) {
        setState(() {
          _progress.remove(entry.id);
          _downloaded.add(entry.id);
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${entry.name} downloaded')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _progress.remove(entry.id));
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  Future<void> _delete(CatalogEntry entry) async {
    try {
      await _downloadManager.delete(entry.id);
      if (mounted) {
        setState(() => _downloaded.remove(entry.id));
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${entry.name} deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
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
                Text('Catalog', style: theme.textTheme.titleLarge),
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
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final e = _entries[i];
                        final isBundled = e.bundled;
                        final isDownloading = _progress.containsKey(e.id);
                        final isDownloaded = _downloaded.contains(e.id);
                        String badge;
                        Color badgeBg;
                        Color badgeFg;
                        if (isBundled) {
                          badge = 'Bundled';
                          badgeBg = const Color(0xFFECFDF5);
                          badgeFg = const Color(0xFF047857);
                        } else if (isDownloaded) {
                          badge = 'Downloaded';
                          badgeBg = const Color(0xFFEFF6FF);
                          badgeFg = const Color(0xFF1D4ED8);
                        } else {
                          badge = 'Download';
                          badgeBg = const Color(0xFFF3F4F6);
                          badgeFg = const Color(0xFF374151);
                        }

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
                                        : isDownloaded
                                            ? const Color(0xFFEFF6FF)
                                            : const Color(0xFFF9FAFB),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: isBundled
                                            ? const Color(0xFFA7F3D0)
                                            : isDownloaded
                                                ? const Color(0xFFBFDBFE)
                                                : const Color(0xFFE5E7EB)),
                                  ),
                                  child: Icon(
                                    isBundled
                                        ? Icons.verified
                                        : isDownloaded
                                            ? Icons.check_circle
                                            : Icons.download_outlined,
                                    color: isBundled
                                        ? const Color(0xFF047857)
                                        : isDownloaded
                                            ? const Color(0xFF1D4ED8)
                                            : const Color(0xFF6B7280),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.name,
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Color(e.tier.bgColorValue),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              e.tier.label,
                                              style: theme.textTheme.labelLarge
                                                  ?.copyWith(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: Color(e.tier.fgColorValue),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: badgeBg,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              badge,
                                              style: theme.textTheme.labelLarge
                                                  ?.copyWith(
                                                fontSize: 10,
                                                color: badgeFg,
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
                                      if (isDownloading) ...[
                                        const SizedBox(height: 8),
                                        LinearProgressIndicator(
                                            value: _progress[e.id]),
                                        const SizedBox(height: 4),
                                        Text(
                                            '${((_progress[e.id] ?? 0) * 100).toInt()}%',
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                    fontSize: 10,
                                                    color:
                                                        const Color(0xFF6B7280))),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (!isBundled)
                                  isDownloading
                                      ? SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                              value: _progress[e.id],
                                              strokeWidth: 2))
                                      : isDownloaded
                                          ? IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 20),
                                              tooltip: 'Delete',
                                              onPressed: () => _delete(e),
                                            )
                                          : IconButton(
                                              icon: const Icon(
                                                  Icons.download, size: 20),
                                              tooltip: 'Download',
                                              onPressed: () => _download(e),
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
