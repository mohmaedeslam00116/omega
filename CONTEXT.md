# Omega — Image Upscaler

Mobile app that upscales images 100% on-device using a pluggable multi-engine architecture (Alibaba MNN Vulkan GPU + Google TFLite), with downloadable neural network models hosted as a versioned catalog on GitHub Releases.

## Language

### Catalog
A versioned list of downloadable upscale models published as GitHub Release assets with cryptographic verification metadata (scale, type, size, backend, sha256).
_Avoid_: model store, release list

### Model
A single weight file (`.tflite` or `.mnn`) representing weights and computational graph for a specific upscale type, architecture, and scale.
_Avoid_: checkpoint, network

### Engine
An on-device execution backend implementing `TfliteEngine` (e.g. `MnnEngineImpl` via Dart FFI with Vulkan GPU shaders, or `TfliteEngineImpl` via TFLite C API).
_Avoid_: runtime, executor, inference engine

### EngineBackend
Enum specifying the target execution engine (`tflite`, `mnn`, `onnx`). Inferred automatically from model extension or explicitly declared in `CatalogEntry`.
_Avoid_: model runner, delegate type

### Scale
Integer factor by which an image is enlarged (e.g., 4x). A property of a Model.
_Avoid_: zoom, magnification, ratio

### Tile
A rectangular sub-region of an input image processed independently to bound memory; tiles overlap to avoid seam artifacts.
_Avoid_: chunk, patch, block

### Adaptive Tiling
Dynamic selection between `64x64` tiles (low memory tier <= 4GB RAM, heavy models) and `128x128` tiles (high memory tier >= 8GB RAM) based on device RAM and model architecture.
_Avoid_: dynamic resizing, auto-crop

### MemoryGuard
Pre-flight verification system validating memory bounds against `DeviceRamTier` before allocation, with automatic runtime fallback from 128 to 64 tiles on memory pressure.
_Avoid_: OOM killer, ram limiter

### Upscale
To increase image resolution using a Model, preserving content while synthesizing detail on-device.
_Avoid_: enhance, super-resolve, enlarge (as generic terms)

### CatalogEntry
One item in a Catalog describing a single downloadable Model (id, name, scale, type, backend, inputSize, url, sha256, license, bundled).
_Avoid_: model info, catalog item

### Download
The process of fetching a CatalogEntry's Model to local storage with SHA256 verification and caching.
_Avoid_: fetch, pull

### Preprocess
Turning a source Tile into the float32 tensor an Engine consumes (normalize 0..1 + NHWC layout) before inference.
_Avoid_: normalize step, input preparation

### Stitch
Compositing upscaled Tiles into the final image, feather-blending overlapping borders so no seams show.
_Avoid_: glue, mosaic, paste

### UpscaleJob
A single, cancellable upscale operation with progress reporting, executed in a fresh background Isolate.
_Avoid_: upscale task, job queue

## Notes
- Architecture: Pluggable Multi-Engine (ADR-0008) routing models to `MnnEngineImpl` or `TfliteEngineImpl`.
- Memory & Performance: Adaptive Tiling (ADR-0009) with dynamic overlap feathering and runtime OOM fallback.
- Security & Privacy: 100% on-device local processing, zero network transmission of user images, cryptographic SHA256 download verification.
- Design: `impeccable` UI — distinctive, intentional, tokens-driven dark theme with before/after slider and format-remembering save sheet.
