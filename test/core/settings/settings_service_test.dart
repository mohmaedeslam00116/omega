import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omega/core/settings/settings_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('GPU toggle persists', () async {
    final prefs = await SharedPreferences.getInstance();
    final svc = SettingsService(prefs);
    expect(svc.useGpu, false);
    await svc.setUseGpu(true);
    expect(svc.useGpu, true);
    // New instance should read persisted
    final svc2 = SettingsService(await SharedPreferences.getInstance());
    expect(svc2.useGpu, true);
  });

  test('Cache limit persists', () async {
    final prefs = await SharedPreferences.getInstance();
    final svc = SettingsService(prefs);
    expect(svc.cacheLimitBytes, 500 * 1024 * 1024);
    await svc.setCacheLimitBytes(100 * 1024 * 1024);
    expect(svc.cacheLimitBytes, 100 * 1024 * 1024);
  });

  test('Catalog refresh hours defaults to 24', () async {
    final prefs = await SharedPreferences.getInstance();
    final svc = SettingsService(prefs);
    expect(svc.catalogRefreshHours, 24);
    await svc.setCatalogRefreshHours(12);
    expect(svc.catalogRefreshHours, 12);
  });
}
