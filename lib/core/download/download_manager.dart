import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../catalog/catalog_entry.dart';

class CancelledException implements Exception {
  final String message;
  CancelledException([this.message = 'Download cancelled']);
  @override
  String toString() => 'CancelledException: $message';
}

abstract class DownloadManager {
  Future<File> download(
    CatalogEntry entry, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  });

  /// Local file path where this CatalogEntry's Model lives once Downloaded
  /// (the Upscale job loads it inside its worker Isolate).
  Future<String> pathFor(CatalogEntry entry);

  Future<void> delete(String id);
  Future<void> clearCache();
  Future<int> getCacheSize();
  Future<bool> isDownloaded(String id);
}

class DownloadManagerImpl implements DownloadManager {
  final http.Client client;
  final Future<Directory> Function()? getCacheDirOverride;
  final int cacheLimitBytes;

  DownloadManagerImpl({
    required this.client,
    this.getCacheDirOverride,
    this.cacheLimitBytes = 500 * 1024 * 1024,
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

  Directory _modelsDir(Directory base) => Directory('${base.path}/models');

  static String extensionFor(CatalogEntry entry) {
    if (entry.backend == EngineBackend.mnn || entry.url.endsWith('.mnn')) {
      return '.mnn';
    }
    if (entry.backend == EngineBackend.onnx || entry.url.endsWith('.onnx')) {
      return '.onnx';
    }
    return '.tflite';
  }

  File _fileForEntry(Directory base, CatalogEntry entry) {
    final ext = extensionFor(entry);
    return File('${_modelsDir(base).path}/${entry.id}$ext');
  }

  Future<File?> _findExistingFile(Directory base, String id) async {
    final dir = _modelsDir(base);
    for (final ext in ['.tflite', '.mnn', '.onnx']) {
      final f = File('${dir.path}/$id$ext');
      if (await f.exists()) return f;
    }
    return null;
  }

  @override
  Future<File> download(
    CatalogEntry entry, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final base = await _getCacheDir();
    final modelsDir = _modelsDir(base);
    await modelsDir.create(recursive: true);
    final file = _fileForEntry(base, entry);

    int existing = 0;
    if (await file.exists()) {
      existing = await file.length();
      // If already fully downloaded and hash matches, return early
      if (existing == entry.fileSize) {
        try {
          final bytes = await file.readAsBytes();
          final hash = sha256.convert(bytes).toString();
          if (hash.toLowerCase() == entry.sha256.toLowerCase()) {
            if (onProgress != null) onProgress(1.0);
            return file;
          }
        } catch (_) {}
        // otherwise re-download (truncate)
        existing = 0;
      } else if (existing > entry.fileSize) {
        // corrupt larger file
        await file.delete();
        existing = 0;
      }
    }

    final headers = <String, String>{};
    if (existing > 0) {
      headers['Range'] = 'bytes=$existing-';
    }

    final request = http.Request('GET', Uri.parse(entry.url));
    headers.forEach((k, v) => request.headers[k] = v);

    final streamed = await client.send(request);
    if (streamed.statusCode != 200 && streamed.statusCode != 206) {
      throw Exception(
          'Failed to download ${entry.id}: ${streamed.statusCode}');
    }

    final bool isResume = streamed.statusCode == 206;
    final int remaining = streamed.contentLength ?? (entry.fileSize - existing);
    final int total = isResume ? existing + remaining : remaining;

    // If server ignored Range and returned 200, truncate
    final IOSink sink;
    if (!isResume && existing > 0) {
      sink = file.openWrite(mode: FileMode.write);
      existing = 0;
    } else if (isResume) {
      sink = file.openWrite(mode: FileMode.writeOnlyAppend);
    } else {
      sink = file.openWrite();
    }

    int received = existing;
    // Initial progress
    if (onProgress != null && total > 0) {
      onProgress(received / total);
    }

    try {
      await for (final chunk in streamed.stream) {
        if (isCancelled != null && isCancelled()) {
          await sink.close();
          throw CancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && total > 0) {
          final p = (received / total).clamp(0.0, 1.0);
          onProgress(p);
        }
      }
      await sink.close();
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      rethrow;
    }

    // Verify SHA256
    final bytes = await file.readAsBytes();
    final hash = sha256.convert(bytes).toString();
    if (hash.toLowerCase() != entry.sha256.toLowerCase()) {
      try {
        await file.delete();
      } catch (_) {}
      throw FormatException(
          'SHA256 mismatch for ${entry.id}: expected ${entry.sha256}, got $hash');
    }

    await _enforceCacheLimit(modelsDir);

    return file;
  }

  Future<void> _enforceCacheLimit(Directory modelsDir) async {
    if (cacheLimitBytes <= 0) return;
    final files = await modelsDir
        .list()
        .where((e) => e is File)
        .cast<File>()
        .toList();
    // Sort oldest first
    files.sort((a, b) {
      final sa = a.statSync().modified;
      final sb = b.statSync().modified;
      return sa.compareTo(sb);
    });
    int total = 0;
    for (final f in files) {
      total += f.statSync().size;
    }
    for (final f in files) {
      if (total <= cacheLimitBytes) break;
      final size = f.statSync().size;
      try {
        await f.delete();
        total -= size;
      } catch (_) {}
    }
  }

  @override
  Future<void> delete(String id) async {
    final base = await _getCacheDir();
    final dir = _modelsDir(base);
    for (final ext in ['.tflite', '.mnn', '.onnx']) {
      final file = File('${dir.path}/$id$ext');
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<void> clearCache() async {
    final base = await _getCacheDir();
    final dir = _modelsDir(base);
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        if (e is File) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    }
  }

  @override
  Future<int> getCacheSize() async {
    final base = await _getCacheDir();
    final dir = _modelsDir(base);
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final e in dir.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  @override
  Future<bool> isDownloaded(String id) async {
    final base = await _getCacheDir();
    final existing = await _findExistingFile(base, id);
    return existing != null;
  }

  @override
  Future<String> pathFor(CatalogEntry entry) async {
    final base = await _getCacheDir();
    final expectedFile = _fileForEntry(base, entry);
    if (!await expectedFile.exists()) {
      final legacyFile = await _findExistingFile(base, entry.id);
      if (legacyFile != null && await legacyFile.exists()) {
        try {
          if (await legacyFile.length() == entry.fileSize) {
            await legacyFile.rename(expectedFile.path);
            print('[DownloadManager] Migrated legacy file ${legacyFile.path} -> ${expectedFile.path}');
            return expectedFile.path;
          } else {
            await legacyFile.delete();
          }
        } catch (e) {
          print('[DownloadManager] Error during legacy file migration: $e');
        }
      }
    }
    return expectedFile.path;
  }
}
