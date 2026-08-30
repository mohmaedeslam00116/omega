import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UpscaleTab extends StatelessWidget {
  const UpscaleTab({super.key});

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
                      Text('Upscale',
                          style: theme.textTheme.titleLarge),
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
            const SizedBox(height: 24),
            // Drop zone (scaffold placeholder)
            Expanded(
              child: Card(
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
                          border: Border.all(
                              color: const Color(0xFFE5E7EB), width: 1.5),
                        ),
                        child: const Icon(Icons.add_photo_alternate_outlined,
                            size: 36, color: Color(0xFF9CA3AF)),
                      ),
                      const SizedBox(height: 16),
                      Text('No image selected',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(
                        'Choose from Gallery, Camera, or Share an image to Omega.\nMax 4096×4096 • Tiled 128 → 512 per Tile.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF6B7280)),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () async {
                          // Scaffold: verify bundled asset is loadable
                          try {
                            final data = await rootBundle
                                .load('assets/models/realesr-general-x4v3_fp16.tflite');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Bundled Model ready • ${data.lengthInBytes} bytes')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Asset missing: $e')),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.verified_outlined, size: 18),
                        label: const Text('Verify bundled Model'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.photo_library_outlined,
                            size: 18),
                        label: const Text('Pick from Gallery (stub)'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'MVP scaffold • TFLiteEngine stub + CatalogEntry ready • Next: real pipeline in Ticket 05',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: const Color(0xFF9CA3AF), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
