import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../catalog/catalog_entry.dart';

/// Fast statistical analyzer and task router (ADR-0013 / ADR-0014).
/// Classifies images into Anime vs Photo based on edge gradient density
/// and color saturation variance, with explicit user manual selection precedence.
class AdaptiveRouter {
  /// Analyzes an image and returns the recommended [TaskType].
  static TaskType classify(img.Image image) {
    // Fast analysis on downsampled 64x64 thumbnail for <3ms execution
    final thumb = (image.width > 64 || image.height > 64)
        ? img.copyResize(image, width: 64, height: 64)
        : image;

    final w = thumb.width;
    final h = thumb.height;
    if (w < 2 || h < 2) return TaskType.general;

    double edgeMagnitudeSum = 0.0;
    int edgeCount = 0;
    double saturationSum = 0.0;

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final p = thumb.getPixel(x, y);
        final pr = thumb.getPixel(x + 1, y);
        final pb = thumb.getPixel(x, y + 1);

        // Approximate luminance
        final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        final lumR = 0.299 * pr.r + 0.587 * pr.g + 0.114 * pr.b;
        final lumB = 0.299 * pb.r + 0.587 * pb.g + 0.114 * pb.b;

        final dx = lumR - lum;
        final dy = lumB - lum;
        final grad = math.sqrt(dx * dx + dy * dy);

        edgeMagnitudeSum += grad;
        if (grad > 20.0) {
          edgeCount++;
        }

        // Saturation estimate
        final maxC = math.max(p.r, math.max(p.g, p.b));
        final minC = math.min(p.r, math.min(p.g, p.b));
        if (maxC > 0) {
          saturationSum += (maxC - minC) / maxC;
        }
      }
    }

    final totalPixels = (w - 2) * (h - 2);
    final edgeDensity = edgeCount / totalPixels;
    final avgSaturation = saturationSum / totalPixels;

    // Anime / Illustration: distinct sharp edges and higher color saturation
    if (edgeDensity > 0.04 && avgSaturation > 0.15) {
      return TaskType.anime;
    }

    return TaskType.photo;
  }

  /// Resolves the effective task type, giving 100% priority to explicit user manual selection.
  static TaskType route({
    required img.Image image,
    TaskType? userManualOverride,
  }) {
    if (userManualOverride != null && userManualOverride != TaskType.general) {
      return userManualOverride;
    }
    return classify(image);
  }
}
