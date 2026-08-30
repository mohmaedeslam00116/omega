import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/catalog/catalog_entry.dart';
import '../../core/image/image_io_service.dart';
import '../../core/pipeline/upscale_job_runner.dart';
import '../../core/pipeline/upscale_pipeline.dart';

class UpscaleTab extends StatefulWidget {
  final ImageIoService? imageIo;
  final UpscaleJobRunner? runner;
  final String? modelPath;
  final bool useGpu;
  final List<CatalogEntry>? catalog;

  const UpscaleTab({
    super.key,
    this.imageIo,
    this.runner,
    this.modelPath,
    this.useGpu = false,
    this.catalog,
  });

  @override
  State<UpscaleTab> createState() => _UpscaleTabState();
}

class _UpscaleTabState extends State<UpscaleTab> {
  static const _defaultModelPath =
      'assets/models/realesr-general-x4v3_fp16.tflite';

  late final ImageIoService _imageIo;
  late final UpscaleJobRunner _runner;
  late final String _modelPath;
  late List<CatalogEntry> _catalog;

  Uint8List? _inputBytes;
  Uint8List? _outputBytes;
  bool _isProcessing = false;
  bool _modelReady = false;
  double _progress = 0;
  String? _error;
  double _slider = 0.5;
  CatalogEntry? _selected;
  CancelToken? _activeToken;

  @override
  void initState() {
    super.initState();
    _imageIo = widget.imageIo ?? ImageIoServiceImpl();
    _runner = widget.runner ?? IsolateUpscaleJobRunner();
    _modelPath = widget.modelPath ?? _defaultModelPath;
    _catalog = widget.catalog ?? _defaultCatalog;
    _selected =
        _catalog.firstWhere((e) => e.bundled, orElse: () => _catalog.first);
    _checkModelReady();
  }

  static final List<CatalogEntry> _defaultCatalog = [
    CatalogEntry(
      id: 'realesr-general-x4v3',
      name: 'General Photo 4×',
      scale: 4,
      type: ModelType.general,
      inputSize: 128,
      fileSize: 3549456,
      sha256: '6d597b46d812ada42bdde641ec6e78c0ef0b78ff5a825fcfd74b9a1b3bcbe9a4',
      url: 'https://github.com/mohmaedeslam00116/omega-models/releases/download/v1.0.0/realesr-general-x4v3_fp16.tflite',
      license: 'BSD-3-Clause',
      version: '1.0.0',
      bundled: true,
    ),
    CatalogEntry(
      id: 'realesr-x4plus',
      name: 'High Quality 4×',
      scale: 4,
      type: ModelType.general,
      inputSize: 128,
      fileSize: 3549456,
      sha256: '6d597b46d812ada42bdde641ec6e78c0ef0b78ff5a825fcfd74b9a1b3bcbe9a4',
      url: 'https://github.com/mohmaedeslam00116/omega-models/releases/download/v1.0.0/realesr-x4plus_w8a8.tflite',
      license: 'BSD-3-Clause',
      version: '1.0.0',
      bundled: false,
    ),
  ];

  Future<void> _checkModelReady() async {
    try {
      if (_modelPath.startsWith('assets/')) {
        await rootBundle.load(_modelPath);
      } else if (!File(_modelPath).existsSync()) {
        throw StateError('Model file missing: $_modelPath');
      }
      if (mounted) setState(() => _modelReady = true);
    } catch (_) {
      if (mounted) setState(() => _modelReady = false);
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
    if (!_modelReady) {
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
      final out = await _runner.run(
        _inputBytes!,
        config: UpscaleJobConfig(modelPath: _modelPath, useGpu: widget.useGpu),
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        cancelToken: token,
      );
      if (mounted) {
        setState(() {
          _outputBytes = out;
          _isProcessing = false;
        });
      }
    } on UpscaleCancelledException {
      // Cancelled from the UI — quietly return to the preview state.
      if (mounted) setState(() => _isProcessing = false);
    } catch (e) {
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
    try {
      final path = await _imageIo.saveToGallery(_outputBytes!);
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
                  label: const Text('TFLite • 4×'),
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
                              child: Text('${e.name} ${e.bundled ? "• Bundled" : ""}',
                                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12)),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selected = v),
                  ),
                ),
                if (!_modelReady)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(_error!, style: const TextStyle(color: Color(0xFF991B1B), fontSize: 12)),
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
            // Keep scaffold verify for backward compat
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                try {
                  final data = await rootBundle.load('assets/models/realesr-general-x4v3_fp16.tflite');
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Bundled Model ready • ${data.lengthInBytes} bytes')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Asset missing: $e')));
                }
              },
              icon: const Icon(Icons.verified_outlined, size: 16),
              label: const Text('Verify bundled Model', style: TextStyle(fontSize: 11)),
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
            child: Stack(
              children: [
                // After (full)
                Positioned.fill(
                  child: Image.memory(_outputBytes!, fit: BoxFit.contain),
                ),
                // Before clipped by slider
                ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: _slider,
                    child: Image.memory(_inputBytes!, fit: BoxFit.contain),
                  ),
                ),
                // Divider
                Positioned(
                  left: MediaQuery.of(context).size.width * _slider - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: Colors.white),
                ),
              ],
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
