import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'catalog_entry.dart';

/// Highest-level catalog seam. Fetches versioned Catalog from GitHub Releases
/// raw URL with 24h file cache (file + in-memory).
abstract class CatalogService {
  Future<List<CatalogEntry>> fetchCatalog({bool forceRefresh = false});
  Future<List<CatalogEntry>> getCached();
}

/// Minimal in-memory implementation for scaffold; kept for tests.
class CatalogServiceStub implements CatalogService {
  final String catalogJson;
  List<CatalogEntry>? _cache;
  DateTime? _cachedAt;

  CatalogServiceStub(this.catalogJson);

  @override
  Future<List<CatalogEntry>> fetchCatalog({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null && _cachedAt != null) {
      final age = DateTime.now().difference(_cachedAt!);
      if (age.inHours < 24) return _cache!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final entries = CatalogEntry.listFromJson(catalogJson);
    _cache = entries;
    _cachedAt = DateTime.now();
    return entries;
  }

  @override
  Future<List<CatalogEntry>> getCached() async => _cache ?? [];
}

/// HTTP-backed implementation with 24h disk + memory cache.
/// Ticket 02: real catalog from GitHub Releases raw URL.
class HttpCatalogService implements CatalogService {
  final http.Client client;
  final String catalogUrl;
  final Future<Directory> Function()? getCacheDirOverride;
  final Duration expiry;
  List<CatalogEntry>? _cache;
  DateTime? _cachedAt;

  HttpCatalogService({
    required this.client,
    required this.catalogUrl,
    this.getCacheDirOverride,
    this.expiry = const Duration(hours: 24),
  });

  Future<Directory> _getCacheDir() async {
    if (getCacheDirOverride != null) return getCacheDirOverride!();
    try {
      return await getApplicationSupportDirectory().timeout(
        const Duration(milliseconds: 50),
        onTimeout: () => Directory.systemTemp,
      );
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  File _cacheFile(Directory dir) => File('${dir.path}/catalog.json');

  @override
  Future<List<CatalogEntry>> fetchCatalog({bool forceRefresh = false}) async {
    final dir = await _getCacheDir();
    final file = _cacheFile(dir);

    if (!forceRefresh) {
      // 1) in-memory check
      if (_cache != null && _cachedAt != null) {
        if (DateTime.now().difference(_cachedAt!) < expiry) return _cache!;
      }
      // 2) disk check
      if (await file.exists()) {
        final stat = await file.stat();
        final age = DateTime.now().difference(stat.modified);
        if (age < expiry) {
          try {
            final content = await file.readAsString();
            final entries = CatalogEntry.listFromJson(content);
            _cache = entries;
            _cachedAt = stat.modified;
            return entries;
          } catch (_) {
            // corrupt cache → fall through to network
          }
        }
      }
    }

    final res = await client.get(Uri.parse(catalogUrl));
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch catalog: ${res.statusCode}');
    }
    final bodyStr = utf8.decode(res.bodyBytes);
    final entries = CatalogEntry.listFromJson(bodyStr);
    // write to disk (overwrite)
    await file.create(recursive: true);
    await file.writeAsString(bodyStr);
    _cache = entries;
    _cachedAt = DateTime.now();
    return entries;
  }

  @override
  Future<List<CatalogEntry>> getCached() async {
    if (_cache != null) return _cache!;
    // try disk
    try {
      final dir = await _getCacheDir();
      final file = _cacheFile(dir);
      if (await file.exists()) {
        final stat = await file.stat();
        if (DateTime.now().difference(stat.modified) < expiry) {
          final content = await file.readAsString();
          return CatalogEntry.listFromJson(content);
        }
      }
    } catch (_) {}
    return [];
  }
}
