import 'dart:math' as math;

/// Device RAM tiers for selecting memory safety margins and tile sizing.
enum DeviceRamTier {
  /// Devices with <= 4 GB RAM: uses compact 64x64 tiles for maximum safety.
  low,

  /// Devices with 4 - 6 GB RAM: balanced 64/128 depending on model weight.
  medium,

  /// Devices with >= 8 GB RAM: full 128x128 tiles for maximum throughput.
  high,
}

/// Thrown by the pre-flight memory guard when the estimated decode + output
/// footprint exceeds the pipeline's memory limit. The message is
/// user-facing (shown in the Upscale tab) — keep it free of OOM jargon so it
/// never looks like an out-of-memory retry trigger.
class MemoryEstimateExceededException implements Exception {
  final int estimatedBytes;
  final int limitBytes;

  const MemoryEstimateExceededException(this.estimatedBytes, this.limitBytes);

  static String _mb(int bytes) => (bytes / (1024 * 1024)).round().toString();

  @override
  String toString() =>
      'Image is too large to upscale on this device '
      '(needs ~${_mb(estimatedBytes)} MB, limit is ${_mb(limitBytes)} MB). '
      'Try a smaller image.';
}

/// Pre-flight estimate of the peak pixel memory one upscale needs:
/// the decoded input image plus the full output canvas, both RGBA
/// (4 bytes per pixel).
int estimateUpscaleMemoryBytes(int width, int height, {int scale = 4}) =>
    (width * height + width * scale * (height * scale)) * 4;

/// Complete estimate including active tile tensor working memory buffers.
int estimateTotalPeakMemory(
  int width,
  int height, {
  int scale = 4,
  int tileSize = 128,
  bool isHeavyModel = false,
}) {
  final imageBytes = estimateUpscaleMemoryBytes(width, height, scale: scale);
  final tensorBufferMultiplier = isHeavyModel ? 16 : 4;
  final tensorBytes = tileSize * tileSize * 3 * 4 * tensorBufferMultiplier;
  return imageBytes + tensorBytes;
}

/// Memory Guard and Adaptive Tiling helper.
class MemoryGuard {
  /// Default memory limit for mobile devices (512 MB).
  static const int defaultMemoryLimitBytes = 512 * 1024 * 1024;

  /// High-tier device memory limit (1.5 GB).
  static const int highTierMemoryLimitBytes = 1536 * 1024 * 1024;

  /// Returns the recommended overlap in pixels for a given tile size
  /// to ensure seamless feathered blending without seam artifacts.
  static int overlapForTileSize(int tileSize) {
    if (tileSize <= 64) return 16;
    if (tileSize <= 96) return 24;
    return 36;
  }

  /// Selects the optimal tile size based on image dimensions, model weight,
  /// and device memory budget.
  static int selectOptimalTileSize({
    required int width,
    required int height,
    bool isHeavyModel = false,
    int memoryLimitBytes = defaultMemoryLimitBytes,
    DeviceRamTier ramTier = DeviceRamTier.medium,
  }) {
    // Low RAM devices or small memory limits always use 64x64
    if (ramTier == DeviceRamTier.low || memoryLimitBytes < 300 * 1024 * 1024) {
      return 64;
    }

    // Heavy models (like RRDBNet 68MB) on medium tier phones use 64x64 for thermal & RAM safety
    if (isHeavyModel && ramTier != DeviceRamTier.high) {
      return 64;
    }

    // For smaller images (< 256x256), 64x64 provides finer granularity
    if (math.max(width, height) <= 128) {
      return 64;
    }

    return 128;
  }

  /// Validates whether the image can be safely processed within the memory budget.
  static void validateMemory({
    required int width,
    required int height,
    int scale = 4,
    int tileSize = 128,
    bool isHeavyModel = false,
    int memoryLimitBytes = defaultMemoryLimitBytes,
  }) {
    if (width > 4096 || height > 4096) {
      throw UnsupportedError(
        'Image exceeds 4096px, please crop or choose smaller',
      );
    }

    final estimated = estimateTotalPeakMemory(
      width,
      height,
      scale: scale,
      tileSize: tileSize,
      isHeavyModel: isHeavyModel,
    );

    if (estimated > memoryLimitBytes) {
      throw MemoryEstimateExceededException(estimated, memoryLimitBytes);
    }
  }
}
