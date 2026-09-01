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
      title: 'Omega Super-Resolution',
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

class RootShell extends StatefulWidget {
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
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final Widget currentTab;
    switch (_index) {
      case 0:
        currentTab = UpscaleTab(
          settingsService: widget.settingsService,
          downloadManager: widget.downloadManager,
        );
        break;
      case 1:
        currentTab = CatalogTab(
          catalogService: widget.catalogService,
          downloadManager: widget.downloadManager,
        );
        break;
      case 2:
      default:
        currentTab = SettingsTab(
          settingsService: widget.settingsService,
          downloadManager: widget.downloadManager,
          onThemeChanged: widget.onThemeChanged,
        );
        break;
    }

    return Scaffold(
      body: currentTab,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Upscale',
          ),
          NavigationDestination(
            icon: Icon(Icons.layers_outlined),
            selectedIcon: Icon(Icons.layers),
            label: 'Models',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
