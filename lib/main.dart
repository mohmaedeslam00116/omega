import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/upscale/upscale_tab.dart';
import 'features/catalog/catalog_tab.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OmegaApp());
}

class OmegaApp extends StatelessWidget {
  const OmegaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Omega Upscaler',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _tabs = [
    UpscaleTab(),
    CatalogTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 20),
            SizedBox(width: 8),
            Text('Omega'),
          ],
        ),
      ),
      body: _tabs[_index],
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
            label: 'Catalog',
          ),
        ],
      ),
    );
  }
}
