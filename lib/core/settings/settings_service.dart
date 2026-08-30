import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _kUseGpu = 'useGpu';
  static const _kCacheLimit = 'cacheLimitBytes';
  static const _kRefreshHours = 'catalogRefreshHours';

  final SharedPreferences prefs;

  SettingsService(this.prefs);

  static Future<SettingsService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  bool get useGpu => prefs.getBool(_kUseGpu) ?? false;
  Future<void> setUseGpu(bool v) => prefs.setBool(_kUseGpu, v);

  int get cacheLimitBytes =>
      prefs.getInt(_kCacheLimit) ?? 500 * 1024 * 1024;
  Future<void> setCacheLimitBytes(int v) => prefs.setInt(_kCacheLimit, v);

  int get catalogRefreshHours => prefs.getInt(_kRefreshHours) ?? 24;
  Future<void> setCatalogRefreshHours(int v) =>
      prefs.setInt(_kRefreshHours, v);
}
