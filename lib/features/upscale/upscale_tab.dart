import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/catalog/catalog_entry.dart';
import '../../core/download/download_manager.dart';
import '../../core/image/image_io_service.dart';
import '../../core/pipeline/upscale_job_runner.dart';
import '../../core/pipeline/upscale_pipeline.dart';
import '../../core/settings/settings_service.dart';

class UpscaleTab extends StatefulWidget {
  final ImageIoService? imageIo;
  final UpscaleJobRunner? runner;
  final DownloadManager? downloadManager;
  final SettingsService? settingsService;
  final bool? useGpu;
  final List<CatalogEntry>? catalog;

  const UpscaleTab({
    super.key,
    this.imageIo,
    this.runner,
    this.downloadManager,
    this.settingsService,
    this.useGpu,
    this.catalog,
  });

  @override
  State<UpscaleTab> createState() => _UpscaleTabState();
}

class _UpscaleTabState extends State<UpscaleTab> {
  late final ImageIoService _imageIo;
  late final UpscaleJobRunner _runner;
  late final DownloadManager _downloadManager;
  late List<CatalogEntry> _catalog;

  Uint8List? _inputBytes;
  Uint8List? _outputBytes;
  bool _isProcessing = false;
  double _progress = 0;
  String? _error;
  double _slider = 0.5;
  CatalogEntry? _selected;
  CancelToken? _activeToken;
  SettingsService? _settings;

  /// CatalogEntry ids available locally: bundled always, Downloaded on demand.
  final Set<String> _downloadedIds = {};
  String? _downloadingId;
  double? _downloadProgress;

  @override
  void initState() {
    super.initState();
    _imageIo = widget.imageIo ?? ImageIoServiceImpl();
    _runner = widget.runner ?? IsolateUpscaleJobRunner();
    _downloadManager =
        widget.downloadManager ?? DownloadManagerImpl(client: http.Client());
    _catalog = widget.catalog ?? _defaultCatalog;
    _selected =
        _catalog.firstWhere((e) => e.bundled, orElse: () => _catalog.first);
    _refreshDownloadedIds();
    _initSettings();
  }

  Future<void> _initSettings() async {
    _settings = widget.settingsService ?? await SettingsService.init();
  }

  static final List<CatalogEntry> _defaultCatalog = [
    CatalogEntry(
      id: 'realesr-general-x4v3',
      name: 'General Photo 4×',
      scale: 4,
      type: ModelType.general,
      tier: ModelTier.balanced,
      inputSize: 128,
      fileSize: 8389964,
      sha256: '86d076d2acce51190d41cfdde3acdc431c2861dd747f5707cc65003a2e2c5814',
      url: 'https://github.com/mohmaedeslam00116/omega-models/releases/download/v1.0.0/realesr-general-x4v3_fp16.tflite',
      license: 'BSD-3-Clause',
      version: '1.0.0',
      bundled: true,
    ),
    CatalogEntry(
      id: 'realesr-animevideov3',
      name: 'Anime & Digital Art 4×',
      scale: 4,
      type: ModelType.anime,
      tier: ModelTier.fast,
      inputSize: 128,
      fileSize: 1271540,
      sha256: '74189d7c0b8e7aafcfef3038e5f76d7d73b28d19327e82f28cb43d179cc5be99',
      url: 'https://github.com/mohmaedeslam00116/omega-models/releases/download/v1.0.0/realesr-animevideov3_fp16.tflite',
      license: 'BSD-3-Clause',
      version: '1.0.0',
      bundled: true,
    ),
    CatalogEntry(
      id: 'realesr-anime-6b-int8',
      name: 'Anime Pro 4× (6B INT8)',
      scale: 4,
      type: ModelType.anime,
      backend: EngineBackend.mnn,
      tier: ModelTier.balanced,
      inputSize: 128,
      fileSize: 4518000,
      sha256: '3a5df67926ce40498b8ec66ac898863fba880a6b7e05e54612c6f112fa89b275',
      url: 'https://github.com/mohmaedeslam00116/omega-models/releases/download/v1.0.0/RealESRGAN_x4plus_anime_6B_int8.mnn',
      license: 'BSD-3-Clause',
      version: '1.0.0',
      bundled: false,
    ),
    CatalogEntry(
      id: 'realesr-x4plus-int8',
      name: 'Ultra Quality 4× (RRDBNet INT8)',
      scale: 4,
      type: ModelType.general,
      backend: EngineBackend.mnn,
      tier: ModelTier.quality,
      inputSize: 128,
      fileSize: 17180132,
      sha256: '4c9bd6946666a1ec62d622d60847166c31394d6d741d43d5f83eb3ef11e68ab8',
      url: 'https://github.com/mohmaedeslam00116/omega-models/releases/download/v1.0.0/RealESRGAN_x4plus_int8.mnn',
      license: 'BSD-3-Clause',
      version: '1.0.0',
      bundled: false,
    ),
    CatalogEntry(
      id: 'realesr-x4plus-fp16',
      name: 'Ultra Quality 4× (RRDBNet FP16)',
      scale: 4,
      type: ModelType.general,
      backend: EngineBackend.mnn,
      tier: ModelTier.quality,
      inputSize: 128,
      fileSize: 33660484,
      sha256: '719a4e97ef9780599235f0b9a287f4f51c96e5e20d3a01d89bd093f4ab96731f',
      url: 'https://github.com/mohmaedeslam00116/omega-models/releases/download/v1.0.0/RealESRGAN_x4plus_fp16.mnn',
      license: 'BSD-3-Clause',
      version: '1.0.0',
      bundled: false,
    ),
  ];

  /// Bundled Models ship at `assets/models/<id>_fp16.tflite` (ADR-0004
  /// convention; matches the bundled CatalogEntry ids).
  static String _bundledAssetPath(CatalogEntry entry) =>
      'assets/models/${entry.id}_fp16.tflite';

  /// The selected Model is ready when bundled or already Downloaded.
  bool get _modelReady {
    final entry = _selected;
    if (entry == null) return false;
    return entry.bundled || _downloadedIds.contains(entry.id);
  }

  void _refreshDownloadedIds() {
    for (final e in _catalog.where((e) => !e.bundled)) {
      _downloadManager.isDownloaded(e.id).then((ok) {
        if (ok && mounted && !_downloadedIds.contains(e.id)) {
          setState(() => _downloadedIds.add(e.id));
        }
      }).catchError((_) {});
    }
  }

  Future<void> _onModelSelected(CatalogEntry? entry) async {
    if (entry == null || identical(entry, _selected)) return;
    if (_downloadingId != null) return; // one Download at a time
    final previous = _selected;
    setState(() => _selected = entry);
    if (entry.bundled || _downloadedIds.contains(entry.id)) return;

    setState(() {
      _downloadingId = entry.id;
      _downloadProgress = 0;
    });
    try {
      await _downloadManager.download(entry, onProgress: (p) {
        if (mounted) setState(() => _downloadProgress = p);
      });
      if (!mounted) return;
      setState(() {
        _downloadedIds.add(entry.id);
        _downloadingId = null;
        _downloadProgress = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _selected = previous; // revert to the last usable Model
        _downloadingId = null;
        _downloadProgress = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  Future<void> _pickGallery() async {
    try {
      final bytes = await _imageIo.pickFromGallery();
      if (bytes == null) return;
      if (!mounted) return;
      setState(() {
        _inputBytes = bytes;
        _outputBytes = null;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _pickCamera() async {
    try {
      final bytes = await _imageIo.pickFromCamera();
      if (bytes == null) return;
      if (!mounted) return;
      setState(() {
        _inputBytes = bytes;
        _outputBytes = null;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _upscale() async {
    if (_inputBytes == null || _isProcessing) return;
    final entry = _selected;
    if (entry == null || !_modelReady) {
      setState(() => _error = 'Model not ready');
      return;
    }
    final token = CancelToken();
    setState(() {
      _isProcessing = true;
      _progress = 0;
      _error = null;
      _activeToken = token;
    });
    try {
      final modelPath = entry.bundled
          ? _bundledAssetPath(entry)
          : await _downloadManager.pathFor(entry);

      final effectiveGpu =
          widget.settingsService?.useGpu ?? widget.useGpu ?? true;
      debugPrint(
          '[Omega-UI] Triggering upscale: model=${entry.id}, name="${entry.name}", backend=${entry.backend.name}, bundled=${entry.bundled}');
      debugPrint('[Omega-UI] Model path: $modelPath, GPU enabled: $effectiveGpu');
      final out = await _runner.run(
        _inputBytes!,
        config: UpscaleJobConfig(modelPath: modelPath, useGpu: effectiveGpu),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        cancelToken: token,
      );
      debugPrint('[Omega-UI] Upscale completed successfully! Output bytes: ${out.length}');
      if (mounted) {
        setState(() {
          _outputBytes = out;
          _isProcessing = false;
        });
      }
    } on UpscaleCancelledException {
      debugPrint('[Omega-UI] Upscale cancelled by user');
      // Cancelled from the UI — quietly return to the preview state.
      if (mounted) setState(() => _isProcessing = false);
    } catch (e, stack) {
      debugPrint('UPSCALE ERROR: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _error = e.toString();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      _activeToken = null;
    }
  }

  void _cancelUpscale() => _activeToken?.cancel();

  Future<void> _save() async {
    if (_outputBytes == null) return;
    final choice = await showModalBottomSheet<(String, int)>(
      context: context,
      builder: (_) => _SaveFormatSheet(
        initialFormat: _settings?.saveFormat ?? 'png',
        initialQuality: _settings?.jpegQuality ?? 90,
      ),
    );
    if (choice == null) return;
    final format = choice.$1;
    final quality = choice.$2;
    await _settings?.setSaveFormat(format);
    await _settings?.setJpegQuality(quality);
    try {
      final filename =
          format == 'jpeg' ? 'omega_upscaled.jpg' : 'omega_upscaled.png';
      final path = await _imageIo.saveToGallery(
        _outputBytes!,
        filename: filename,
        asJpeg: format == 'jpeg',
        jpegQuality: quality,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Future<void> _share() async {
    if (_outputBytes == null) return;
    try {
      await _imageIo.shareImage(_outputBytes!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Upscale', style: theme.textTheme.titleLarge),
                      Text('Pick an image → 4× on-device',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF6B7280), fontSize: 12)),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                      '${_selected?.backend.name.toUpperCase() ?? "TFLITE"} • ${_selected?.scale ?? 4}×'),
                  backgroundColor: const Color(0xFFFFF0F0),
                  labelStyle: theme.textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF9A3412), fontSize: 11),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Model selector
            Row(
              children: [
                const Icon(Icons.layers_outlined, size: 16, color: Color(0xFF6B7280)),
                const SizedBox(width: 6),
                Text('Model:', style: theme.textTheme.labelLarge?.copyWith(fontSize: 11, color: const Color(0xFF6B7280))),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<CatalogEntry>(
                    value: _selected,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: _catalog
                        .map((e) => DropdownMenuItem(
                              value: e,
                              child: Text('${e.tier == ModelTier.fast ? "⚡ " : e.tier == ModelTier.quality ? "💎 " : "⚖️ "}${e.name}${e.bundled ? " • Bundled" : ""}',
                                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12)),
                            ))
                        .toList(),
                    onChanged: (v) => _onModelSelected(v),
                  ),
                ),
                if (_downloadingId != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            value: _downloadProgress, strokeWidth: 2)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Container(
                constraints: const BoxConstraints(maxHeight: 70),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFF991B1B), fontSize: 12),
                  ),
                ),
              ),
            if (_error != null) const SizedBox(height: 8),
            if (_isProcessing)
              Column(
                children: [
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 6),
                  Text('${(_progress * 100).toInt()}% • ${(_progress * 64).toInt()}/64 tiles',
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11, color: const Color(0xFF6B7280))),
                  const SizedBox(height: 8),
                ],
              ),
            // Main content
            Expanded(
              child: _inputBytes == null
                  ? _emptyState(theme)
                  : _outputBytes == null
                      ? _previewInput(theme)
                      : _beforeAfter(theme),
            ),
            const SizedBox(height: 12),
            // Action bar
            if (_inputBytes == null)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _pickGallery,
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Gallery'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickCamera,
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('Camera'),
                    ),
                  ),
                ],
              )
            else if (_outputBytes == null)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          (!_modelReady || _isProcessing) ? null : _upscale,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: Text(_isProcessing ? 'Upscaling...' : 'Upscale 4×'),
                    ),
                  ),
                  if (_isProcessing) ...[
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _cancelUpscale,
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Cancel'),
                    ),
                  ],
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_alt, size: 18),
                      label: const Text('Save to Gallery'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _share,
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),

          ],
        ),
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
              ),
              child: const Icon(Icons.add_photo_alternate_outlined, size: 36, color: Color(0xFF9CA3AF)),
            ),
            const SizedBox(height: 16),
            Text('No image selected', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Choose from Gallery, Camera, or Share an image to Omega.\nMax 4096×4096 • Tiled 128 → 512 per Tile.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewInput(ThemeData theme) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Image.memory(_inputBytes!, fit: BoxFit.contain),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: const Color(0xFFF9FAFB),
            child: Text(
              'Preview • ${_inputBytes!.length ~/ 1024} KB • Ready to upscale',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11, color: const Color(0xFF6B7280)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _beforeAfter(ThemeData theme) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // After (full)
                    Positioned.fill(
                      child: Image.memory(_outputBytes!, fit: BoxFit.contain),
                    ),
                    // Before clipped by slider
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: width * _slider,
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: width,
                          maxWidth: width,
                          minHeight: height,
                          maxHeight: height,
                          child: Image.memory(_inputBytes!, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    // Divider
                    Positioned(
                      left: (width * _slider - 1).clamp(0.0, width - 2.0),
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: Colors.white),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Text('Before', style: TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
                Expanded(
                  child: Slider(
                    value: _slider,
                    onChanged: (v) => setState(() => _slider = v),
                  ),
                ),
                const Text('After', style: TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for the save flow: PNG (lossless) or JPEG with a quality
/// slider. Pre-filled from the remembered SettingsService preference and
/// returns `(format, quality)` — persisted by the caller.
class _SaveFormatSheet extends StatefulWidget {
  final String initialFormat;
  final int initialQuality;

  const _SaveFormatSheet({
    required this.initialFormat,
    required this.initialQuality,
  });

  @override
  State<_SaveFormatSheet> createState() => _SaveFormatSheetState();
}

class _SaveFormatSheetState extends State<_SaveFormatSheet> {
  late String _format = widget.initialFormat;
  late int _quality = widget.initialQuality.clamp(1, 100);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Save options', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _formatCard(
                  context,
                  label: 'PNG',
                  subtitle: 'Lossless',
                  selected: _format == 'png',
                  onTap: () => setState(() => _format = 'png'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _formatCard(
                  context,
                  label: 'JPEG',
                  subtitle: 'Smaller files',
                  selected: _format == 'jpeg',
                  onTap: () => setState(() => _format = 'jpeg'),
                ),
              ),
            ],
          ),
          if (_format == 'jpeg') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Quality',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                Expanded(
                  child: Slider(
                    key: const ValueKey('jpegQuality'),
                    value: _quality.toDouble(),
                    min: 1,
                    max: 100,
                    divisions: 99,
                    label: '$_quality',
                    onChanged: (v) => setState(() => _quality = v.round()),
                  ),
                ),
                Text('$_quality', style: theme.textTheme.labelLarge),
              ],
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(context, (_format, _quality)),
            child: const Text('Save image'),
          ),
        ],
      ),
    );
  }

  Widget _formatCard(
    BuildContext context, {
    required String label,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF1A1A2E) : const Color(0xFFE5E7EB),
            width: selected ? 1.6 : 1,
          ),
          color: selected ? const Color(0xFFF3F4FF) : Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.titleMedium),
            Text(subtitle,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontSize: 11, color: const Color(0xFF6B7280))),
          ],
        ),
      ),
    );
  }
}
