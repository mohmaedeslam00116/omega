import 'dart:typed_data';
import 'package:flutter/material.dart';

class ComparisonSlider extends StatefulWidget {
  final Uint8List beforeBytes;
  final Uint8List afterBytes;
  final int? inputWidth;
  final int? inputHeight;
  final Duration? duration;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onNewImage;

  const ComparisonSlider({
    super.key,
    required this.beforeBytes,
    required this.afterBytes,
    this.inputWidth,
    this.inputHeight,
    this.duration,
    required this.onSave,
    required this.onShare,
    required this.onNewImage,
  });

  @override
  State<ComparisonSlider> createState() => _ComparisonSliderState();
}

class _ComparisonSliderState extends State<ComparisonSlider> {
  double _split = 0.5;
  final TransformationController _transformController =
      TransformationController();
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05;
    if (zoomed != _isZoomed) {
      setState(() => _isZoomed = zoomed);
    }
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
    setState(() => _isZoomed = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final int? inW = widget.inputWidth;
    final int? inH = widget.inputHeight;
    final int? outW = inW != null ? inW * 4 : null;
    final int? outH = inH != null ? inH * 4 : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Metadata Overlay Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              if (inW != null && inH != null) ...[
                Text(
                  '$inW × $inH',
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward, size: 14, color: theme.colorScheme.onSurfaceVariant),
                ),
                Text(
                  '$outW × $outH (4×)',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              if (widget.duration != null) ...[
                const SizedBox(width: 8),
                Text(
                  '• ${widget.duration!.inMilliseconds}ms',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              const Spacer(),
              if (_isZoomed)
                IconButton(
                  tooltip: 'Reset Zoom',
                  visualDensity: VisualDensity.compact,
                  onPressed: _resetZoom,
                  icon: const Icon(Icons.zoom_out_map, size: 18),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Interactive Zoomable Image Area with Split Slider
        Container(
          height: 360,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: theme.colorScheme.surfaceContainerHigh,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Synchronized Zoom & Pan Container
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 1.0,
                  maxScale: 8.0,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Layer 1: Upscaled (After) Full Image
                      Image.memory(
                        widget.afterBytes,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),

                      // Layer 2: Original (Before) Clipped Image
                      ClipRect(
                        clipper: _SplitClipper(_split),
                        child: Image.memory(
                          widget.beforeBytes,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Visual Split Line Overlay
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SplitLinePainter(split: _split, color: Colors.white),
                  ),
                ),
              ),

              // Floating Chips: 'Before' and 'After'
              Positioned(
                left: 14,
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Before',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'After (4×)',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Split Slider Control
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            trackHeight: 4,
          ),
          child: Slider(
            value: _split,
            onChanged: (v) => setState(() => _split = v),
          ),
        ),
        const SizedBox(height: 16),

        // Bottom Action Buttons
        Row(
          children: [
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                onPressed: widget.onSave,
                icon: const Icon(Icons.save_alt_rounded),
                label: const Text('Save to Gallery'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Share image',
              onPressed: widget.onShare,
              icon: const Icon(Icons.share_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: widget.onNewImage,
                icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                label: const Text('New Image'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SplitClipper extends CustomClipper<Rect> {
  final double split;
  _SplitClipper(this.split);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * split, size.height);

  @override
  bool shouldReclip(covariant _SplitClipper oldClipper) => oldClipper.split != split;
}

class _SplitLinePainter extends CustomPainter {
  final double split;
  final Color color;
  _SplitLinePainter({required this.split, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width * split;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 2.0;

    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _SplitLinePainter oldDelegate) =>
      oldDelegate.split != split || oldDelegate.color != color;
}
