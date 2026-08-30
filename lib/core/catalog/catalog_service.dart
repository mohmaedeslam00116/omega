import 'dart:convert';
import 'package:http/http.dart' as http;

import 'catalog_entry.dart';

/// Highest-level catalog seam. Fetches versioned Catalog from GitHub Releases
/// raw URL with 24h file cache (simplified for scaffold: in-memory cache).
abstract class CatalogService {
  Future<List<CatalogEntry>> fetchCatalog({bool forceRefresh = false});
  Future<List<CatalogEntry>> getCached();
}

/// Minimal in-memory implementation for scaffold; real implementation (Ticket 02)
/// will add disk cache, 24h expiry, and HTTP fetch.
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
    // Simulate network delay for stub
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final entries = CatalogEntry.listFromJson(catalogJson);
    _cache = entries;
    _cachedAt = DateTime.now();
    return entries;
  }

  @override
  Future<List<CatalogEntry>> getCached() async => _cache ?? [];
}

/// HTTP-backed implementation (skeleton for Ticket 02).
class HttpCatalogService implements CatalogService {
  final http.Client client;
  final String catalogUrl;
  List<CatalogEntry>? _cache;
  DateTime? _cachedAt;

  HttpCatalogService({required this.client, required this.catalogUrl});

  @override
  Future<List<CatalogEntry>> fetchCatalog({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null && _cachedAt != null) {
      if (DateTime.now().difference(_cachedAt!).inHours < 24) return _cache!;
    }
    final res = await client.get(Uri.parse(catalogUrl));
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch catalog: ${res.statusCode}');
    }
    final entries = CatalogEntry.listFromJson(utf8.decode(res.bodyBytes));
    _cache = entries;
    _cachedAt = DateTime.now();
    return entries;
  }

  @override
  Future<List<CatalogEntry>> getCached() async => _cache ?? [];
}
