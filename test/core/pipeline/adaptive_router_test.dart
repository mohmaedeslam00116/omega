import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:omega/core/catalog/catalog_entry.dart';
import 'package:omega/core/pipeline/adaptive_router.dart';

void main() {
  group('AdaptiveRouter', () {
    test('classifies sharp high-saturation drawing as Anime', () {
      final image = img.Image(width: 64, height: 64);
      // Fill background with bright flat saturated color
      img.fill(image, color: img.ColorRgb8(255, 100, 100));
      // Draw sharp black line art borders
      for (int i = 10; i < 54; i++) {
        image.setPixelRgb(i, 20, 0, 0, 0);
        image.setPixelRgb(i, 40, 0, 0, 0);
        image.setPixelRgb(20, i, 0, 0, 0);
        image.setPixelRgb(40, i, 0, 0, 0);
      }

      final task = AdaptiveRouter.classify(image);
      expect(task, TaskType.anime);
    });

    test('classifies natural gradient / low-contrast texture as Photo', () {
      final image = img.Image(width: 64, height: 64);
      for (int y = 0; y < 64; y++) {
        for (int x = 0; x < 64; x++) {
          final v = (100 + (x + y) * 0.5).round().clamp(0, 255);
          image.setPixelRgb(x, y, v, v, v); // Grayscale gradient
        }
      }

      final task = AdaptiveRouter.classify(image);
      expect(task, TaskType.photo);
    });

    test('userManualOverride takes 100% precedence over heuristic classification', () {
      final image = img.Image(width: 64, height: 64);
      img.fill(image, color: img.ColorRgb8(255, 100, 100));
      for (int i = 10; i < 54; i++) {
        image.setPixelRgb(i, 20, 0, 0, 0);
        image.setPixelRgb(i, 40, 0, 0, 0);
      }

      final autoResult = AdaptiveRouter.classify(image);
      expect(autoResult, TaskType.anime);

      // User manually selected Photo
      final routedResult = AdaptiveRouter.route(
        image: image,
        userManualOverride: TaskType.photo,
      );
      expect(routedResult, TaskType.photo);
    });
  });
}
