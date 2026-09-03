# ADR-0013: Cascaded Multi-Model Pipeline with Adaptive Routing and Hybrid Tiling

## Status
Accepted

## Context
A single monolithic Super-Resolution model attempts to perform all visual restoration tasks simultaneously (denoising, deblurring, super-resolution, line sharpening). On budget mobile hardware (ARM Mali-G72), monolithic models suffer from high inference latency (>1500ms) and large memory footprints.

Instead of monolithic models, lightweight specialized SOTA micro-models (e.g. Denoise 1x, SAFMN 4x, ECBSR RepVGG 4x) each excel at a single focused task with sub-100ms latency. Chaining these micro-models in a sequential multi-stage pipeline yields superior visual fidelity while preserving low peak VRAM.

## Decision
1. **Cascaded Pipeline Architecture**: Implement CascadedPipeline that executes an ordered sequence of specialized micro-models (e.g. Stage 1: Denoise 1x -> Stage 2: Super-Resolution 4x).
2. **Adaptive Routing**: Introduce AdaptiveRouter which analyzes image characteristics (edge density, frequency variance, and preset selection) to dynamically select the optimal model sequence for Anime vs Real-world photos.
3. **Hybrid Tiled Pipeline**: Stream tiles sequentially across stages within an in-memory tile cache without writing uncompressed intermediate frames to storage.
4. **StageProgress Telemetry**: Report multi-phase human-friendly progress (e.g. 'Step 1/2: Denoising 40%') alongside an internal monotonically increasing 0-100% completion metric.

## Consequences
### Positive
- **Visual Quality**: Cleaner edges and superior noise suppression compared to single-pass models.
- **Modularity**: Individual specialized models can be updated, quantized, or replaced independently.
- **Low Memory Overhead**: Streaming tile-by-tile chaining bounds RAM consumption to single tile buffers (<10 MB).

### Negative / Trade-offs
- Multiple inference passes slightly increase total processing duration relative to a single ultra-fast micro-model (e.g. 58ms + 48ms = ~106ms total).
- Requires managing multiple model weights in storage and runtime memory.
