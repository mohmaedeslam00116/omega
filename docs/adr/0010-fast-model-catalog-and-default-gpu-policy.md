# ADR 0010: Fast Model Catalog Taxonomy and Default Mobile GPU Policy

## Status
Accepted

## Context
Running 23-block RRDBNet models on low-end and budget devices (e.g. MediaTek Helio P70 / Mali-G72) on CPU resulted in long processing times (~15s per 128x128 tile) and device heating. SuperImage achieves fast performance on similar budget devices by defaulting to Vulkan GPU compute shaders and offering compact model architectures (such as 6-block RRDBNet and SRVGGNet Compact).

## Decision
1. **Default GPU Acceleration**:
   - SettingsService.useGpu defaults to 	rue.
   - The native MNN C++ layer (omega_mnn_wrapper.cpp) attempts Vulkan GPU acceleration first with FP16 precision (Precision_Low) and automatically falls back to CPU if Vulkan session initialization fails on the device.
2. **Three-Tier Catalog Taxonomy**:
   - **⚡ Ultra Fast**: Models under 3 MB taking <100ms per tile (e.g. SRVGGNet-Compact, AnimeVideoV3).
   - **⚖️ Balanced**: Models 4-9 MB with 6 RRDB blocks taking ~300ms per tile (e.g. RealESRGAN Anime 6B).
   - **💎 Ultra Quality**: Full 23-block RRDBNet INT8/FP16 models (17-34 MB) for maximum fidelity.
3. **Adaptive UI Badging**:
   - Catalog and Upscale UI display speed and quality badges to assist users in selecting the optimal model for their device performance tier.

## Consequences
- **Positive**: Budget devices process images in seconds rather than minutes; GPU offload prevents thermal throttling; users clearly understand model speed/quality tradeoffs.
- **Negative**: Adds multiple model entries to the catalog metadata which must be hosted and hashed in releases.
