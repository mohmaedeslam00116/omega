import 'package:flutter/material.dart';
import 'core/catalog/catalog_service.dart';
import 'core/download/download_manager.dart';
import 'core/settings/settings_service.dart';
import 'core/theme/app_theme.dart';
import 'features/catalog/catalog_tab.dart';
import 'features/settings/settings_tab.dart';
import 'features/upscale/upscale_tab.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsService.init();
  runApp(OmegaApp(initialSettings: settings));
}

class OmegaApp extends StatefulWidget {
  final SettingsService? initialSettings;
  final CatalogService? catalogService;
  final DownloadManager? downloadManager;

  const OmegaApp({
    super.key,
    this.initialSettings,
    this.catalogService,
    this.downloadManager,
  });

  @override
  State<OmegaApp> createState() => _OmegaAppState();
}

class _OmegaAppState extends State<OmegaApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    if (widget.initialSettings != null) {
      _applyThemeString(widget.initialSettings!.themeMode);
    }
  }

  void _applyThemeString(String mode) {
    if (mode == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (mode == 'light') {
      _themeMode = ThemeMode.light;
    } else {
      _themeMode = ThemeMode.system;
    }
  }

  void _onThemeChanged(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Omega Upscaler',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      debugShowCheckedModeBanner: false,
      home: RootShell(
        settingsService: widget.initialSettings,
        catalogService: widget.catalogService,
        downloadManager: widget.downloadManager,
        onThemeChanged: _onThemeChanged,
      ),
    );
  }
}

class RootShell extends StatelessWidget {
  final SettingsService? settingsService;
  final CatalogService? catalogService;
  final DownloadManager? downloadManager;
  final void Function(ThemeMode mode)? onThemeChanged;

  const RootShell({
    super.key,
    this.settingsService,
    this.catalogService,
    this.downloadManager,
    this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Omega',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => Scaffold(
                    appBar: AppBar(title: const Text('Settings')),
                    body: SettingsTab(
                      settingsService: settingsService,
                      downloadManager: downloadManager,
                      onThemeChanged: onThemeChanged,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: UpscaleTab(
        settingsService: settingsService,
        downloadManager: downloadManager,
      ),
    );
  }
}
