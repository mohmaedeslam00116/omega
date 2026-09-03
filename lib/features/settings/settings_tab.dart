import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/download/download_manager.dart';
import '../../core/engine/tflite_engine.dart';
import '../../core/settings/settings_service.dart';

class SettingsTab extends StatefulWidget {
  final SettingsService? settingsService;
  final DownloadManager? downloadManager;
  final TfliteEngine? engine;
  final Future<bool> Function()? requestPermissionOverride;
  final Future<String> Function()? loadNoticesOverride;
  final void Function(ThemeMode mode)? onThemeChanged;

  const SettingsTab({
    super.key,
    this.settingsService,
    this.downloadManager,
    this.engine,
    this.requestPermissionOverride,
    this.loadNoticesOverride,
    this.onThemeChanged,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  SettingsService? _settings;
  bool _useGpu = true;
  int _cacheLimit = 500 * 1024 * 1024;
  int _cacheSize = 0;
  String _themeMode = 'system';
  String _saveFormat = 'png';
  int _jpegQuality = 90;
  bool _autoSave = false;
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
          _themeMode = svc.themeMode;
          _saveFormat = svc.saveFormat;
          _jpegQuality = svc.jpegQuality;
          _autoSave = svc.autoSave;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(v ? 'GPU acceleration enabled' : 'CPU fallback enabled'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _setTheme(String mode) async {
    setState(() => _themeMode = mode);
    await _settings?.setThemeMode(mode);
    ThemeMode tm = ThemeMode.system;
    if (mode == 'dark') tm = ThemeMode.dark;
    if (mode == 'light') tm = ThemeMode.light;
    widget.onThemeChanged?.call(tm);
  }

  Future<void> _setSaveFormat(String format) async {
    setState(() => _saveFormat = format);
    await _settings?.setSaveFormat(format);
  }

  Future<void> _setJpegQuality(double q) async {
    final intQuality = q.round();
    setState(() => _jpegQuality = intQuality);
    await _settings?.setJpegQuality(intQuality);
  }

  Future<void> _toggleAutoSave(bool v) async {
    setState(() => _autoSave = v);
    await _settings?.setAutoSave(v);
  }

  Future<void> _setCacheLimit(double mb) async {
    final bytes = (mb * 1024 * 1024).toInt();
    setState(() => _cacheLimit = bytes);
    await _settings?.setCacheLimitBytes(bytes);
  }

  Future<void> _clearCache() async {
    try {
      await widget.downloadManager?.clearCache();
      final size = await widget.downloadManager?.getCacheSize() ?? 0;
      if (mounted) {
        setState(() => _cacheSize = size);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All downloaded models cleared')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Clear failed: $e')),
        );
      }
    }
  }

  Future<void> _requestPermission() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gallery Permission'),
        content: const Text(
          'Omega requires storage access to pick images and save high-resolution results directly to your gallery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Grant'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      bool granted = false;
      if (widget.requestPermissionOverride != null) {
        granted = await widget.requestPermissionOverride!();
      } else {
        granted = true;
      }
      if (!mounted) return;
      if (granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission granted')),
        );
      }
    }
  }

  Future<String> _loadNotices() async {
    if (widget.loadNoticesOverride != null) {
      return widget.loadNoticesOverride!();
    }
    try {
      return await rootBundle.loadString('assets/NOTICES');
    } catch (_) {
      return 'Omega Super-Resolution — MIT License';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          Text(
            'Settings',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),

          // 1. Appearance Section
          _buildSectionHeader(context, 'Appearance', LucideIcons.palette),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Theme Mode',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'system', label: Text('System'), icon: Icon(LucideIcons.laptop, size: 16)),
                      ButtonSegment(value: 'light', label: Text('Light'), icon: Icon(LucideIcons.sun, size: 16)),
                      ButtonSegment(value: 'dark', label: Text('Dark'), icon: Icon(LucideIcons.moon, size: 16)),
                    ],
                    selected: {_themeMode},
                    onSelectionChanged: (set) => _setTheme(set.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. Export & Storage Section
          _buildSectionHeader(context, 'Export & Quality', LucideIcons.download),
          Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Default Output Format',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'png', label: Text('PNG (Lossless)')),
                          ButtonSegment(value: 'jpeg', label: Text('JPEG')),
                          ButtonSegment(value: 'webp', label: Text('WebP')),
                        ],
                        selected: {_saveFormat},
                        onSelectionChanged: (set) => _setSaveFormat(set.first),
                      ),
                      if (_saveFormat == 'jpeg') ...[
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('JPEG Quality', style: theme.textTheme.bodyMedium),
                            Text('$_jpegQuality%', style: theme.textTheme.labelLarge),
                          ],
                        ),
                        Slider(
                          value: _jpegQuality.toDouble(),
                          min: 80,
                          max: 100,
                          divisions: 20,
                          label: '$_jpegQuality%',
                          onChanged: _setJpegQuality,
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Auto-Save to Gallery'),
                  subtitle: const Text('Automatically save upscaled images upon completion'),
                  value: _autoSave,
                  onChanged: _toggleAutoSave,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Hardware & Performance Section
          _buildSectionHeader(context, 'Engine & Performance', LucideIcons.cpu),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Hardware GPU Acceleration'),
                  subtitle: const Text('Use Alibaba MNN Vulkan compute shaders for 10x-100x speedups'),
                  value: _useGpu,
                  onChanged: _toggleGpu,
                ),
                const Divider(height: 1),
                Container(
                  padding: const EdgeInsets.all(16),
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  child: Row(
                    children: [
                      Icon(LucideIcons.zap, color: colorScheme.primary, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Device Neural Pipeline',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Vulkan GPU Shaders + Adaptive Tiling (64/128)',
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Cache & Maintenance Section
          _buildSectionHeader(context, 'Storage & Maintenance', LucideIcons.hardDrive),
          Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Models Cache Limit'),
                          Text(
                            '${(_cacheLimit / 1024 / 1024).toInt()} MB',
                            style: theme.textTheme.labelLarge,
                          ),
                        ],
                      ),
                      Slider(
                        value: (_cacheLimit / 1024 / 1024).clamp(100, 1000).toDouble(),
                        min: 100,
                        max: 1000,
                        divisions: 9,
                        label: '${(_cacheLimit / 1024 / 1024).toInt()} MB',
                        onChanged: _setCacheLimit,
                      ),
                      Text(
                        'Current Cache Used: ${(_cacheSize / 1024).toStringAsFixed(1)} KB',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(LucideIcons.trash2, color: Colors.redAccent),
                  title: const Text('Clear All Downloaded Models'),
                  subtitle: const Text('Free up storage on device'),
                  onTap: _clearCache,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(LucideIcons.image),
                  title: const Text('Gallery Storage Permission'),
                  subtitle: const Text('Check and grant gallery permissions'),
                  onTap: _requestPermission,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 5. About Section
          _buildSectionHeader(context, 'About Omega', LucideIcons.info),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.sparkles, color: Color(0xFF6366F1), size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Omega Image Upscaler',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '100% On-Device AI Upscaler powered by Alibaba MNN Vulkan GPU & Google TFLite.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<String>(
                    future: _loadNotices(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const SizedBox(
                          height: 40,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      return Text(
                        snap.data!,
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: Colors.grey),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Version 1.1.0 • GPL-3.0 & BSD-3-Clause • github.com/mohmaedeslam00116/omega',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ],
      ),
    );
  }
}
