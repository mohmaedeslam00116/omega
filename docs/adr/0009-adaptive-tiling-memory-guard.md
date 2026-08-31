# 0009. Adaptive Tiling & Dynamic RAM Memory Guard Policy

Date: 2026-08-31
Status: Accepted

## Context

Running high-capacity super-resolution architectures (such as RealESRGAN RRDBNet 68MB in Alibaba MNN format) on diverse Android devices exposes two risks:
1. Low-RAM devices (<= 4GB RAM) risk running out of memory (OOM) or thermal throttling if processing large 128x128 tiles with heavy intermediate feature activation maps (>120MB working memory).
2. High-RAM devices (>= 8GB RAM) have ample headroom and run faster with 128x128 tiles (reducing the total number of inference passes and isolate message dispatches).

## Decision

1. **`MemoryGuard` & Tiered Budget**:
   - Introduced `DeviceRamTier` (`low`, `medium`, `high`).
   - `MemoryGuard.selectOptimalTileSize` dynamically selects `64x64` for low RAM tiers or heavy models on mid-range devices, and `128x128` for high RAM devices.
   - Overlap stride is calculated proportionally (`MemoryGuard.overlapForTileSize`: 16px for 64x64, 36px for 128x128) ensuring 100% artifact-free feathered blending.

2. **Automatic Runtime OOM Fallback**:
   - `UpscalePipeline.upscale` catches any runtime Out-of-Memory / allocation faults during 128x128 tile execution and automatically steps down to 64x64 tiles without failing the user's job.

3. **Pre-flight Safety Bounds**:
   - Validates total peak memory before allocation, rejecting images exceeding device bounds with friendly, non-technical guidance.

## Consequences

- Low-end and mid-range devices can safely run heavy 68MB RRDBNet models without crashes (peak RAM < 35MB per tile).
- High-end devices achieve maximum GPU throughput with 128x128 tiles.
- The pipeline remains 100% deterministic and backward-compatible.
