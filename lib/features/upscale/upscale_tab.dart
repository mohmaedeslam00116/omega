import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../../core/catalog/catalog_entry.dart';
import '../../core/download/download_manager.dart';
import '../../core/image/image_io_service.dart';
import '../../core/pipeline/upscale_job_runner.dart';
import '../../core/pipeline/upscale_pipeline.dart';
import '../../core/preset/human_friendly_preset.dart';
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
  int? _inputWidth;
  int? _inputHeight;
  int? _inputSizeBytes;

  bool _isProcessing = false;
  double _progress = 0;
  String? _error;
  double _slider = 0.5;
  CancelToken? _activeToken;
  SettingsService? _settings;

  // 2D Human-friendly presets
  PresetContentType _contentType = PresetContentType.photo;
  PresetQualityTier _qualityTier = PresetQualityTier.lightning;
  CatalogEntry? _selected;

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
    _refreshDownloadedIds();
    _initSettings();
  }

  Future<void> _initSettings() async {
    _settings = widget.settingsService ?? await SettingsService.init();
    _resolveSelectedModel();
    if (mounted) setState(() {});
  }

  void _resolveSelectedModel() {
    final bool useGpu = widget.useGpu ?? _settings?.useGpu ?? true;
    _selected = PresetResolver.resolveBestModel(
      catalog: _catalog,
      contentType: _contentType,
      qualityTier: _qualityTier,
      useGpu: useGpu,
    );
  }

  static final List<CatalogEntry> _defaultCatalog = [
    CatalogEntry(
      id: 'plainusr-x4-int8',
      name: 'PlainUSR 4× (⚡ Lightning INT8)',
      scale: 4,
      type: ModelType.general,
      backend: EngineBackend.mnn,
      tier: ModelTier.fast,
      inputSize: 128,
      fileSize: 310960,
      sha256: '24425fae8c69a2c99a89ae79b826fbd8b9d621462e5255b8c4a55d80b9bd1250',
      url: 'https://github.com/mohmaedeslam00116/omega-models/releases/download/v1.1.0/plainusr_x4_int8.mnn',
      license: 'GPL-3.0',
      version: '1.1.0',
      bundled: false,
    ),
    CatalogEntry(
      id: 'safmn-x4-int8',
      name: 'SAFMN 4× (⚡ Lightning INT8)',
      scale: 4,
      type: ModelType.anime,
      backend: EngineBackend.mnn,
      tier: ModelTier.fast,
      inputSize: 128,
      fileSize: 320992,
      sha256: '2c522e4b1b3e8f080b5fdbf35e2d483428efbeea2dc390421f4b87835e7c061f',
      url: 'https://github.com/mohmaedeslam00116/omega-models/releases/download/v1.1.0/safmn_x4_int8.mnn',
      license: 'GPL-3.0',
      version: '1.1.0',
      bundled: false,
    ),
    CatalogEntry(
      id: 'realesr-general-x4v3',
      name: 'General Photo 4×',
      scale: 4,
      type: ModelType.general,
      backend: EngineBackend.tflite,
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
      backend: EngineBackend.tflite,
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
      fileSize: 4599808,
      sha256: '3bb23e924541b7df75ac147c6baec44ed822a21917da7f77873d66db69f036f8',
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
  ];

  static String _bundledAssetPath(CatalogEntry entry) =>
      'assets/models/${entry.id}_fp16.tflite';

  Future<void> _refreshDownloadedIds() async {
    final ids = <String>{};
    for (final e in _catalog) {
      if (e.bundled) {
        ids.add(e.id);
      } else {
        try {
          if (await _downloadManager.isDownloaded(e.id)) {
            ids.add(e.id);
          }
        } catch (_) {}
      }
    }
    if (mounted) {
      setState(() {
        _downloadedIds
          ..clear()
          ..addAll(ids);
      });
    }
  }

  void _setImageBytes(Uint8List? bytes) {
    _inputBytes = bytes;
    _outputBytes = null;
    _error = null;
    _progress = 0;
    if (bytes != null) {
      _inputSizeBytes = bytes.lengthInBytes;
      try {
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          _inputWidth = decoded.width;
          _inputHeight = decoded.height;
        }
      } catch (_) {}
    } else {
      _inputWidth = null;
      _inputHeight = null;
      _inputSizeBytes = null;
    }
    setState(() {});
  }

  Future<void> _pickImage() async {
    try {
      final bytes = await _imageIo.pickFromGallery();
      if (bytes != null) _setImageBytes(bytes);
    } catch (e) {
      setState(() => _error = 'Failed to pick image: $e');
    }
  }

  Future<void> _pickCamera() async {
    try {
      final bytes = await _imageIo.pickFromCamera();
      if (bytes != null) _setImageBytes(bytes);
    } catch (e) {
      setState(() => _error = 'Failed to pick image from camera: $e');
    }
  }

  Future<void> _upscale() async {
    if (_inputBytes == null) return;
    _resolveSelectedModel();
    final selected = _selected;
    if (selected == null) {
      setState(() => _error = 'No suitable AI model found');
      return;
    }

    // Auto-download model if not present locally
    if (!selected.bundled && !_downloadedIds.contains(selected.id)) {
      setState(() {
        _downloadingId = selected.id;
        _downloadProgress = 0;
      });
      try {
        await _downloadManager.download(
          selected,
          onProgress: (p) {
            if (mounted && _downloadingId == selected.id) {
              setState(() => _downloadProgress = p);
            }
          },
        );
        _downloadedIds.add(selected.id);
      } catch (e) {
        if (mounted) {
          setState(() {
            _downloadingId = null;
            _downloadProgress = null;
            _error = 'Failed to download AI model: $e';
          });
        }
        return;
      } finally {
        if (mounted) {
          setState(() {
            _downloadingId = null;
            _downloadProgress = null;
          });
        }
      }
    }

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _error = null;
      _outputBytes = null;
    });

    final token = CancelToken();
    _activeToken = token;

    try {
      final bool useGpu = widget.useGpu ?? _settings?.useGpu ?? true;
      final String modelPath = selected.bundled
          ? _bundledAssetPath(selected)
          : await _downloadManager.pathFor(selected);

      final config = UpscaleJobConfig(
        modelPath: modelPath,
        tileSize: selected.inputSize,
        scale: selected.scale,
        useGpu: useGpu,
      );

      final out = await _runner.run(
        _inputBytes!,
        config: config,
        onProgress: (p) {
          if (mounted && !token.isCancelled) {
            setState(() => _progress = p);
          }
        },
        cancelToken: token,
      );

      if (mounted && !token.isCancelled) {
        setState(() {
          _outputBytes = out;
          _isProcessing = false;
          _progress = 1.0;
        });

        if (_settings?.autoSave ?? false) {
          _autoSave(out);
        }
      }
    } catch (e) {
      if (mounted) {
        final errText = '$e';
        setState(() {
          _isProcessing = false;
          _error = token.isCancelled ? null : errText;
        });
        if (!token.isCancelled) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                errText.startsWith('Exception: ')
                    ? errText.substring(11)
                    : errText,
              ),
            ),
          );
        }
      }
    } finally {
      _activeToken = null;
    }
  }

  Future<void> _autoSave(Uint8List bytes) async {
    try {
      final fmtStr = _settings?.saveFormat ?? 'png';
      final fmt = fmtStr == 'jpeg'
          ? OutputImageFormat.jpeg
          : fmtStr == 'webp'
              ? OutputImageFormat.webp
              : OutputImageFormat.png;
      await _imageIo.saveToGallery(
        bytes,
        asJpeg: fmt == OutputImageFormat.jpeg,
        jpegQuality: _settings?.jpegQuality ?? 90,
        format: fmt,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Auto-saved upscaled image to gallery')),
        );
      }
    } catch (_) {}
  }

  void _cancel() {
    _activeToken?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _resolveSelectedModel();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // Header
          Row(
            children: [
              Text(
                'Omega AI',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              if (_inputBytes != null)
                IconButton(
                  tooltip: 'Clear image',
                  onPressed: _isProcessing ? null : () => _setImageBytes(null),
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 1. Hero Image Container
          _buildHeroCard(theme),
          const SizedBox(height: 20),

          // 2. 2D Preset Selection (Content Type & Quality)
          if (_outputBytes == null) ...[
            _buildContentTypeSelector(theme),
            const SizedBox(height: 16),
            _buildQualityTierSelector(theme),
            const SizedBox(height: 20),
          ],

          // 3. Error Banner
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 4. Action Section (Upscale button / Progress / Save)
          _buildActionSection(theme),
        ],
      ),
    );
  }

  Widget _buildHeroCard(ThemeData theme) {
    if (_outputBytes != null && _inputBytes != null) {
      // Comparison View
      return Column(
        children: [
          Container(
            height: 340,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: theme.colorScheme.surfaceContainerHigh,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.memory(_outputBytes!, fit: BoxFit.contain),
                ),
                Positioned.fill(
                  child: ClipRect(
                    clipper: _HorizontalSplitClipper(_slider),
                    child: Image.memory(_inputBytes!, fit: BoxFit.contain),
                  ),
                ),
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('Before', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('After (4×)', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Slider(
            value: _slider,
            onChanged: (v) => setState(() => _slider = v),
          ),
        ],
      );
    }

    if (_inputBytes != null) {
      // Selected Image Hero Preview
      return Container(
        height: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: theme.colorScheme.surfaceContainerHigh,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Image.memory(_inputBytes!, fit: BoxFit.contain),
            ),
            Positioned(
              bottom: 12,
              child: _buildDimensionsBadge(theme),
            ),
          ],
        ),
      );
    }

    // Empty State Hero Card
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_photo_alternate_rounded,
                size: 36,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No image selected',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Select an image to upscale with high-performance AI',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _isProcessing ? null : _pickImage,
                  icon: const Icon(Icons.photo_library_rounded, size: 18),
                  label: const Text('Gallery'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _pickCamera,
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: const Text('Camera'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDimensionsBadge(ThemeData theme) {
    if (_inputWidth == null || _inputHeight == null) return const SizedBox.shrink();
    final outW = _inputWidth! * 4;
    final outH = _inputHeight! * 4;
    final sizeKb = ((_inputSizeBytes ?? 0) / 1024).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.aspect_ratio, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            '$_inputWidth × $_inputHeight',
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward, size: 14, color: Colors.white70),
          ),
          Text(
            '$outW × $outH (4×)',
            style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Text(
            '• ${sizeKb} KB',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildContentTypeSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Image Type',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SegmentedButton<PresetContentType>(
          segments: [
            ButtonSegment(
              value: PresetContentType.photo,
              label: const Text('Photos'),
              icon: Icon(
                _contentType == PresetContentType.photo
                    ? PresetContentType.photo.activeIcon
                    : PresetContentType.photo.icon,
              ),
            ),
            ButtonSegment(
              value: PresetContentType.anime,
              label: const Text('Art & Anime'),
              icon: Icon(
                _contentType == PresetContentType.anime
                    ? PresetContentType.anime.activeIcon
                    : PresetContentType.anime.icon,
              ),
            ),
          ],
          selected: {_contentType},
          onSelectionChanged: (set) {
            setState(() {
              _contentType = set.first;
              _resolveSelectedModel();
            });
          },
        ),
      ],
    );
  }

  Widget _buildQualityTierSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quality & Speed',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SegmentedButton<PresetQualityTier>(
          segments: const [
            ButtonSegment(
              value: PresetQualityTier.lightning,
              label: Text('⚡ Lightning'),
            ),
            ButtonSegment(
              value: PresetQualityTier.balanced,
              label: Text('⚖️ Balanced'),
            ),
            ButtonSegment(
              value: PresetQualityTier.ultraQuality,
              label: Text('💎 Ultra'),
            ),
          ],
          selected: {_qualityTier},
          onSelectionChanged: (set) {
            setState(() {
              _qualityTier = set.first;
              _resolveSelectedModel();
            });
          },
        ),
      ],
    );
  }

  Widget _buildActionSection(ThemeData theme) {
    if (_outputBytes != null) {
      // Save & Share Buttons
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _showSaveModal(context),
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('Save to Gallery'),
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filledTonal(
            tooltip: 'Share',
            onPressed: () => _imageIo.shareImage(_outputBytes!),
            icon: const Icon(Icons.share_rounded),
          ),
        ],
      );
    }

    if (_isProcessing) {
      return Column(
        children: [
          LinearProgressIndicator(value: _progress > 0 ? _progress : null),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Upscaling... ${(_progress * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              TextButton(
                onPressed: _cancel,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      );
    }

    if (_downloadingId != null) {
      final p = _downloadProgress ?? 0;
      return Column(
        children: [
          LinearProgressIndicator(value: p > 0 ? p : null),
          const SizedBox(height: 8),
          Text(
            'Downloading AI Model... ${(p * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: _inputBytes == null ? null : _upscale,
        icon: const Icon(Icons.auto_awesome_rounded),
        label: const Text(
          'Upscale 4×',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _showSaveModal(BuildContext context) {
    var format = _settings?.saveFormat ?? 'png';
    var quality = _settings?.jpegQuality ?? 90;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Save image', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'png', label: Text('PNG')),
                    ButtonSegment(value: 'jpeg', label: Text('JPEG')),
                    ButtonSegment(value: 'webp', label: Text('WebP')),
                  ],
                  selected: {format},
                  onSelectionChanged: (set) => setModalState(() => format = set.first),
                ),
                if (format == 'jpeg') ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('JPEG Quality'),
                      Text('$quality%'),
                    ],
                  ),
                  Slider(
                    key: const ValueKey('jpegQuality'),
                    value: quality.toDouble(),
                    min: 50,
                    max: 100,
                    divisions: 10,
                    onChanged: (v) => setModalState(() => quality = v.round()),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final outFmt = format == 'jpeg'
                        ? OutputImageFormat.jpeg
                        : format == 'webp'
                            ? OutputImageFormat.webp
                            : OutputImageFormat.png;
                    await _imageIo.saveToGallery(
                      _outputBytes!,
                      asJpeg: format == 'jpeg',
                      jpegQuality: quality,
                      format: outFmt,
                    );
                    _settings?.setSaveFormat(format);
                    _settings?.setJpegQuality(quality);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Saved to Gallery!')),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HorizontalSplitClipper extends CustomClipper<Rect> {
  final double split;
  _HorizontalSplitClipper(this.split);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * split, size.height);

  @override
  bool shouldReclip(covariant _HorizontalSplitClipper oldClipper) =>
      oldClipper.split != split;
}
