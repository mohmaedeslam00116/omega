import 'package:flutter_test/flutter_test.dart';
import 'package:omega/core/pipeline/memory_guard.dart';

void main() {
  group('MemoryGuard - Overlap Calculation', () {
    test('Calculates appropriate overlap for tile sizes', () {
      expect(MemoryGuard.overlapForTileSize(64), 16);
      expect(MemoryGuard.overlapForTileSize(96), 24);
      expect(MemoryGuard.overlapForTileSize(128), 36);
      expect(MemoryGuard.overlapForTileSize(256), 36);
    });
  });

  group('MemoryGuard - Memory Estimation', () {
    test('Calculates base memory footprint correctly', () {
      // 100x100 input -> 400x400 output at 4x
      // Input pixels: 10,000 * 4 = 40,000 bytes
      // Output pixels: 160,000 * 4 = 640,000 bytes
      // Total = 40,000 + 640,000 = 680,000 bytes
      final est = estimateUpscaleMemoryBytes(100, 100, scale: 4);
      expect(est, 680000);
    });

    test('Heavy model multiplier increases working memory buffer in estimateTotalPeakMemory', () {
      final normal = estimateTotalPeakMemory(
        100,
        100,
        scale: 4,
        tileSize: 128,
        isHeavyModel: false,
      );
      final heavy = estimateTotalPeakMemory(
        100,
        100,
        scale: 4,
        tileSize: 128,
        isHeavyModel: true,
      );
      expect(heavy, greaterThan(normal));
    });
  });

  group('MemoryGuard - Adaptive Tile Size Selection', () {
    test('Low RAM tier always uses 64x64 tiles', () {
      final ts = MemoryGuard.selectOptimalTileSize(
        width: 1024,
        height: 1024,
        ramTier: DeviceRamTier.low,
      );
      expect(ts, 64);
    });

    test('Low memory limit (<300MB) forces 64x64 tiles', () {
      final ts = MemoryGuard.selectOptimalTileSize(
        width: 1024,
        height: 1024,
        memoryLimitBytes: 250 * 1024 * 1024,
        ramTier: DeviceRamTier.high,
      );
      expect(ts, 64);
    });

    test('Heavy models use 64x64 on medium RAM tier', () {
      final ts = MemoryGuard.selectOptimalTileSize(
        width: 1024,
        height: 1024,
        isHeavyModel: true,
        ramTier: DeviceRamTier.medium,
      );
      expect(ts, 64);
    });

    test('Heavy models use 128x128 on high RAM tier', () {
      final ts = MemoryGuard.selectOptimalTileSize(
        width: 1024,
        height: 1024,
        isHeavyModel: true,
        ramTier: DeviceRamTier.high,
      );
      expect(ts, 128);
    });

    test('Lightweight models use 128x128 on medium/high RAM tier', () {
      final tsMedium = MemoryGuard.selectOptimalTileSize(
        width: 1024,
        height: 1024,
        isHeavyModel: false,
        ramTier: DeviceRamTier.medium,
      );
      expect(tsMedium, 128);

      final tsHigh = MemoryGuard.selectOptimalTileSize(
        width: 1024,
        height: 1024,
        isHeavyModel: false,
        ramTier: DeviceRamTier.high,
      );
      expect(tsHigh, 128);
    });

    test('Small images (<=128px) use 64x64 tiles', () {
      final ts = MemoryGuard.selectOptimalTileSize(
        width: 100,
        height: 100,
        ramTier: DeviceRamTier.high,
      );
      expect(ts, 64);
    });
  });

  group('MemoryGuard - Validation & Exceptions', () {
    test('Throws UnsupportedError when image exceeds 4096px', () {
      expect(
        () => MemoryGuard.validateMemory(width: 4097, height: 100),
        throwsUnsupportedError,
      );
      expect(
        () => MemoryGuard.validateMemory(width: 100, height: 5000),
        throwsUnsupportedError,
      );
    });

    test('Throws MemoryEstimateExceededException when exceeding budget', () {
      expect(
        () => MemoryGuard.validateMemory(
          width: 2048,
          height: 2048,
          memoryLimitBytes: 10 * 1024 * 1024, // 10MB budget
        ),
        throwsA(isA<MemoryEstimateExceededException>()),
      );
    });

    test('Passes validation when within memory budget', () {
      expect(
        () => MemoryGuard.validateMemory(
          width: 512,
          height: 512,
          memoryLimitBytes: 512 * 1024 * 1024,
        ),
        returnsNormally,
      );
    });

    test('MemoryEstimateExceededException formats friendly message', () {
      const ex = MemoryEstimateExceededException(60 * 1024 * 1024, 50 * 1024 * 1024);
      expect(ex.toString(), contains('needs ~60 MB, limit is 50 MB'));
    });
  });
}
