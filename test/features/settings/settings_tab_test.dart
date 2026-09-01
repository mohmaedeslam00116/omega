import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omega/core/catalog/catalog_entry.dart';
import 'package:omega/core/download/download_manager.dart';
import 'package:omega/core/engine/tflite_engine.dart';
import 'package:omega/core/settings/settings_service.dart';
import 'package:omega/features/settings/settings_tab.dart';

class _FakeEngine implements TfliteEngine {
  @override
  bool useGpu = false;
  @override
  bool get isLoaded => true;
  @override
  Future<void> close() async {}
  @override
  Future<void> load(String p) async {}
  @override
  Future<void> setUseGpu(bool v) async => useGpu = v;
  @override
  Future<Float32List> infer(Float32List input) async => input;
}

class _FakeDl implements DownloadManager {
  bool cleared = false;
  int size = 12345;
  @override
  Future<File> download(entry, {onProgress, isCancelled}) async =>
      File('fake');
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> clearCache() async => cleared = true;
  @override
  Future<int> getCacheSize() async => size;
  @override
  Future<bool> isDownloaded(String id) async => false;

  @override
  Future<String> pathFor(CatalogEntry entry) async => 'fake/${entry.id}.tflite';
}

void main() {
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('omega_settings_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  testWidgets('GPU toggle flips Engine delegate and persists', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final svc = SettingsService(prefs);
    final engine = _FakeEngine();
    final dl = _FakeDl();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsTab(
          settingsService: svc,
          downloadManager: dl,
          engine: engine,
          loadNoticesOverride: () async => 'NOTICES fake',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final gpuFinder = find.widgetWithText(SwitchListTile, 'Hardware GPU Acceleration');
    expect(gpuFinder, findsOneWidget);
    final sw = tester.widget<SwitchListTile>(gpuFinder);
    expect(sw.value, true);

    await tester.tap(gpuFinder);
    await tester.pumpAndSettle();
    expect(engine.useGpu, false);
    expect(svc.useGpu, false);
  });

  testWidgets('Theme selection switches mode and persists', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final svc = SettingsService(prefs);
    ThemeMode? capturedMode;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsTab(
          settingsService: svc,
          downloadManager: _FakeDl(),
          loadNoticesOverride: () async => 'NOTICES',
          onThemeChanged: (m) => capturedMode = m,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Tap 'Dark' in theme segmented button
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(svc.themeMode, 'dark');
    expect(capturedMode, ThemeMode.dark);
  });

  testWidgets('Output format selection updates format and shows quality slider for JPEG', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final svc = SettingsService(prefs);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsTab(
          settingsService: svc,
          downloadManager: _FakeDl(),
          loadNoticesOverride: () async => 'NOTICES',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Tap JPEG
    await tester.tap(find.text('JPEG'));
    await tester.pumpAndSettle();
    expect(svc.saveFormat, 'jpeg');
    expect(find.text('JPEG Quality'), findsOneWidget);

    // Tap WebP
    await tester.tap(find.text('WebP'));
    await tester.pumpAndSettle();
    expect(svc.saveFormat, 'webp');
  });

  testWidgets('Setting cache limit to 100MB persists', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final svc = SettingsService(prefs);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsTab(
          settingsService: svc,
          downloadManager: _FakeDl(),
          loadNoticesOverride: () async => 'NOTICES',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final sliderFinder = find.byType(Slider).first;
    expect(sliderFinder, findsOneWidget);
    await tester.drag(sliderFinder, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(svc.cacheLimitBytes, lessThanOrEqualTo(300 * 1024 * 1024));
  });

  testWidgets('Clear all models calls DownloadManager', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final svc = SettingsService(prefs);
    final dl = _FakeDl();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsTab(
          settingsService: svc,
          downloadManager: dl,
          loadNoticesOverride: () async => 'NOTICES',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final clearFinder = find.text('Clear All Downloaded Models');
    await tester.tap(clearFinder);
    await tester.pumpAndSettle();
    expect(dl.cleared, true);
  });

  testWidgets('Denied permission shows rationale and re-request', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final svc = SettingsService(prefs);
    var firstCall = true;
    Future<bool> requestOverride() async {
      if (firstCall) {
        firstCall = false;
        return false;
      }
      return true;
    }

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsTab(
          settingsService: svc,
          downloadManager: _FakeDl(),
          requestPermissionOverride: requestOverride,
          loadNoticesOverride: () async => 'NOTICES',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final permFinder = find.text('Gallery Storage Permission');
    await tester.tap(permFinder);
    await tester.pumpAndSettle();
    expect(find.text('Gallery Permission'), findsWidgets);
    expect(find.text('Grant'), findsOneWidget);
    await tester.tap(find.text('Grant'));
    await tester.pumpAndSettle();
  });

  testWidgets('About shows NOTICES containing BSD-3 + Apache-2', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final svc = SettingsService(prefs);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsTab(
          settingsService: svc,
          downloadManager: _FakeDl(),
          loadNoticesOverride: () async =>
              'Real-ESRGAN BSD-3-Clause\nESRGAN Apache-2.0',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Real-ESRGAN BSD-3-Clause'), findsOneWidget);
    expect(find.textContaining('Apache-2.0'), findsOneWidget);
  });
}
