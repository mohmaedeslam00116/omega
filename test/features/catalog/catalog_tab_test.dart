import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omega/core/catalog/catalog_entry.dart';
import 'package:omega/core/catalog/catalog_service.dart';
import 'package:omega/core/download/download_manager.dart';
import 'package:omega/features/catalog/catalog_tab.dart';

class _FakeCatalogService implements CatalogService {
  final List<CatalogEntry> entries;
  int fetchCalls = 0;
  bool lastForceRefresh = false;
  _FakeCatalogService(this.entries);

  @override
  Future<List<CatalogEntry>> fetchCatalog({bool forceRefresh = false}) async {
    fetchCalls++;
    lastForceRefresh = forceRefresh;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return entries;
  }

  @override
  Future<List<CatalogEntry>> getCached() async => entries;
}

class _FakeDownloadManager implements DownloadManager {
  final Set<String> downloaded = {};
  final Map<String, double> progress = {};
  final Directory tmp;

  _FakeDownloadManager(this.tmp);

  @override
  Future<File> download(CatalogEntry entry,
      {void Function(double progress)? onProgress,
      bool Function()? isCancelled}) async {
    // Simulate progress
    for (var i = 1; i <= 4; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final p = i / 4;
      progress[entry.id] = p;
      onProgress?.call(p);
    }
    downloaded.add(entry.id);
    return File('${tmp.path}/models/${entry.id}.tflite');
  }

  @override
  Future<void> delete(String id) async {
    downloaded.remove(id);
  }

  @override
  Future<void> clearCache() async {
    downloaded.clear();
  }

  @override
  Future<int> getCacheSize() async => 0;

  @override
  Future<bool> isDownloaded(String id) async => downloaded.contains(id);

  @override
  Future<String> pathFor(CatalogEntry entry) async =>
      '${tmp.path}/models/${entry.id}.tflite';
}

List<CatalogEntry> _exampleEntries() => [
      CatalogEntry(
        id: 'realesr-general-x4v3',
        name: 'General Photo 4×',
        scale: 4,
        type: ModelType.general,
        inputSize: 128,
        fileSize: 10,
        sha256: 'abc',
        url: 'https://example.com/a.tflite',
        license: 'BSD-3-Clause',
        version: '1.0.0',
        bundled: true,
      ),
      CatalogEntry(
        id: 'realesr-x4plus',
        name: 'High Quality 4×',
        scale: 4,
        type: ModelType.general,
        inputSize: 128,
        fileSize: 10,
        sha256: 'def',
        url: 'https://example.com/b.tflite',
        license: 'BSD-3-Clause',
        version: '1.0.0',
        bundled: false,
      ),
    ];

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('omega_catalog_tab_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  testWidgets('List shows 2 entries with correct badges (bundled vs not)',
      (tester) async {
    final entries = _exampleEntries();
    final fakeCatalog = _FakeCatalogService(entries);
    final fakeDl = _FakeDownloadManager(tmp);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CatalogTab(
          catalogService: fakeCatalog,
          downloadManager: fakeDl,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('General Photo 4×'), findsOneWidget);
    expect(find.text('High Quality 4×'), findsOneWidget);
    expect(find.text('Bundled'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('Tap Download -> progress -> Downloaded badge; Delete -> badge reverts',
      (tester) async {
    final entries = _exampleEntries();
    final fakeCatalog = _FakeCatalogService(entries);
    final fakeDl = _FakeDownloadManager(tmp);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CatalogTab(
          catalogService: fakeCatalog,
          downloadManager: fakeDl,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Initially Download
    expect(find.text('Download'), findsOneWidget);
    // Tap Download
    await tester.tap(find.byIcon(Icons.download).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    // Progress should appear
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // Delete
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('Pull-to-refresh calls fetchCatalog bypassing cache',
      (tester) async {
    final entries = _exampleEntries();
    final fakeCatalog = _FakeCatalogService(entries);
    final fakeDl = _FakeDownloadManager(tmp);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CatalogTab(
          catalogService: fakeCatalog,
          downloadManager: fakeDl,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(fakeCatalog.fetchCalls, 1);
    expect(fakeCatalog.lastForceRefresh, false);

    await tester.fling(
        find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(fakeCatalog.fetchCalls, 2);
    expect(fakeCatalog.lastForceRefresh, true);
  });

  testWidgets('State persists across app restart', (tester) async {
    final entries = _exampleEntries();
    final fakeCatalog = _FakeCatalogService(entries);
    final fakeDl = _FakeDownloadManager(tmp);
    // Simulate already downloaded
    fakeDl.downloaded.add('realesr-x4plus');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CatalogTab(
          catalogService: fakeCatalog,
          downloadManager: fakeDl,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // Should show Downloaded without tapping Download
    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.text('Bundled'), findsOneWidget);
  });
}
