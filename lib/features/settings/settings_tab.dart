import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/download/download_manager.dart';
import '../../core/engine/tflite_engine.dart';
import '../../core/settings/settings_service.dart';

class SettingsTab extends StatefulWidget {
  final SettingsService? settingsService;
  final DownloadManager? downloadManager;
  final TfliteEngine? engine;
  final Future<bool> Function()? requestPermissionOverride;
  final Future<String> Function()? loadNoticesOverride;

  const SettingsTab({
    super.key,
    this.settingsService,
    this.downloadManager,
    this.engine,
    this.requestPermissionOverride,
    this.loadNoticesOverride,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  SettingsService? _settings;
  bool _useGpu = false;
  int _cacheLimit = 500 * 1024 * 1024;
  int _cacheSize = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final svc = widget.settingsService ?? await SettingsService.init();
      final size = widget.downloadManager != null
          ? await widget.downloadManager!.getCacheSize()
          : 0;
      if (mounted) {
        setState(() {
          _settings = svc;
          _useGpu = svc.useGpu;
          _cacheLimit = svc.cacheLimitBytes;
          _cacheSize = size;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleGpu(bool v) async {
    setState(() => _useGpu = v);
    await _settings?.setUseGpu(v);
    if (widget.engine != null) {
      await widget.engine!.setUseGpu(v);
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('GPU ${v ? 'enabled' : 'disabled'}')));
    }
  }

  Future<void> _setCacheLimit(double mb) async {
    final bytes = (mb * 1024 * 1024).toInt();
    setState(() => _cacheLimit = bytes);
    await _settings?.setCacheLimitBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Cache limit: ${mb.toInt()} MB')));
    }
  }

  Future<void> _clearCache() async {
    try {
      await widget.downloadManager?.clearCache();
      final size = await widget.downloadManager?.getCacheSize() ?? 0;
      if (mounted) {
        setState(() => _cacheSize = size);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Cache cleared')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Clear failed: $e')));
      }
    }
  }

  Future<void> _requestPermission() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gallery permission'),
        content: const Text(
            'Omega needs gallery access to pick and save images. Please allow access in settings.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Allow')),
        ],
      ),
    );
    if (confirmed == true) {
      bool granted = false;
      if (widget.requestPermissionOverride != null) {
        granted = await widget.requestPermissionOverride!();
      } else {
        // In real app, would call permission_handler; for scaffold, simulate granted
        granted = true;
      }
      if (!mounted) return;
      if (granted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Permission granted')));
      } else {
        // Show rationale and re-request
        final retry = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Permission denied'),
            content: const Text(
                'Without gallery access, you cannot pick or save images. Try again?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Try again')),
            ],
          ),
        );
        if (retry == true) {
          bool granted2 = false;
          if (widget.requestPermissionOverride != null) {
            granted2 = await widget.requestPermissionOverride!();
          }
          if (!mounted) return;
          if (granted2) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Permission granted')));
          }
        }
      }
    }
  }

  Future<String> _loadNotices() async {
    if (widget.loadNoticesOverride != null) {
      return widget.loadNoticesOverride!();
    }
    return rootBundle.loadString('assets/NOTICES');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Settings', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('GPU acceleration'),
                  subtitle: const Text('Use GPU delegate if available'),
                  value: _useGpu,
                  onChanged: _toggleGpu,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Cache limit'),
                          Text('${(_cacheLimit / 1024 / 1024).toInt()} MB',
                              style: theme.textTheme.labelLarge),
                        ],
                      ),
                      Slider(
                        value: (_cacheLimit / 1024 / 1024).clamp(100, 1000).toDouble(),
                        min: 100,
                        max: 1000,
                        divisions: 9,
                        label: '${(_cacheLimit / 1024 / 1024).toInt()} MB',
                        onChanged: (v) => _setCacheLimit(v),
                      ),
                      Text('Used: ${(_cacheSize / 1024).toStringAsFixed(1)} KB',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 11, color: const Color(0xFF6B7280))),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Clear all models'),
                  subtitle: const Text('Remove downloaded models'),
                  onTap: _clearCache,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Gallery permission'),
                  subtitle: const Text('Request gallery access'),
                  onTap: _requestPermission,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('About', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  FutureBuilder<String>(
                    future: _loadNotices(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const SizedBox(
                            height: 60,
                            child: Center(child: CircularProgressIndicator()));
                      }
                      return Text(
                        snap.data!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 11, color: const Color(0xFF374151)),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text('Omega v1.0.0 • MIT • github.com/mohmaedeslam00116/omega',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 10, color: const Color(0xFF9CA3AF))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
