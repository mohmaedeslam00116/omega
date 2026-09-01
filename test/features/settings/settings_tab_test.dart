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

    final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile).first);
    expect(sw.value, true);
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    expect(engine.useGpu, false);
    expect(svc.useGpu, false);
  });

  testWidgets('Setting cache limit to 100MB persists', (tester) async {
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
    // Drag slider to 100
    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);
    // Slider at 500 default, drag to 100 (leftmost)
    await tester.drag(slider, const Offset(-500, 0));
    await tester.pumpAndSettle();
    // Check persisted (should be close to 100)
    expect(svc.cacheLimitBytes, lessThanOrEqualTo(300 * 1024 * 1024));
  });

  testWidgets('Clear all models calls DownloadManager', (tester) async {
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
    await tester.tap(find.text('Clear all models'));
    await tester.pumpAndSettle();
    expect(dl.cleared, true);
  });

  testWidgets('Denied permission shows rationale and re-request', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final svc = SettingsService(prefs);
    var firstCall = true;
    Future<bool> requestOverride() async {
      if (firstCall) {
        firstCall = false;
        return false; // denied first
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
    await tester.tap(find.text('Gallery permission'));
    await tester.pumpAndSettle();
    expect(find.text('Gallery permission'), findsWidgets);
    // First dialog
    expect(find.text('Allow'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    // Second dialog for denied
    expect(find.text('Permission denied'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    // After retry, should show granted SnackBar
    expect(find.text('Permission granted'), findsOneWidget);
  });

  testWidgets('About shows NOTICES containing BSD-3 + Apache-2', (tester) async {
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
    expect(find.textContaining('BSD-3'), findsOneWidget);
    expect(find.textContaining('Apache-2.0'), findsOneWidget);
  });
}
