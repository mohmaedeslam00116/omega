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

### CascadedPipeline
A sequential multi-stage vision workflow chaining specialized micro-models (e.g. Denoise 1x -> Upscale 4x -> Feature Refine) in a single unified job.
_Avoid_: model chaining, multi-pass runner, pipeline stack

### ModelRole
The specific functional role of a micro-model within a pipeline (`denoise`, `upscale`, `face_refine`, `line_refine`).
_Avoid_: model purpose, stage type

### ModelBundle
A logical grouping of atomic micro-models required to execute an end-to-end task pipeline (e.g. Anime Bundle, Photo Bundle), downloaded transparently on demand without exposing technical model names to the user.
_Avoid_: model pack, zip archive, model list

### TaskDrivenUI
A minimalist, consumer-friendly user interface pattern inspired by SuperImage that eliminates technical catalog browsing, organizing the user experience entirely around task modes (Anime vs Photo) with automated background bundle resolution.
_Avoid_: model store UI, catalog tab, developer mode

### BundleResolver
A service that verifies whether all atomic models in a required ModelBundle exist locally on disk, and calculates the exact list of missing models to download.
_Avoid_: bundle checker, dependency solver

### AdaptiveRouter
Decision logic that inspects image metadata, edge density heuristics, or user preset selection to route tiles through the optimal CascadedPipeline chain.
_Avoid_: model selector, type detector, auto switch

### HybridTiledPipeline
Tile-by-tile streaming execution across cascaded model stages with bounded intermediate tile memory and feather blending, avoiding full-frame intermediate RAM allocation.
_Avoid_: tile buffer, in-memory bridge, stream processor

### StageProgress
Granular multi-stage progress telemetry reporting both current human-friendly stage description (e.g. "Step 1/2: Denoising") and unified 0-100% completion.
_Avoid_: sub-progress, step tracker

### UpscaleJob
A single, cancellable upscale operation with progress reporting, executed in a fresh background Isolate.
_Avoid_: upscale task, job queue

### OmegaEdge
A separate GPL-3.0 research repository (`omega-edge`) focused on making heavy super-resolution models run efficiently on low-end ARM Mali GPUs without training. Produces optimized Models (`.mnn`) that feed into the Omega Catalog, and a standalone C++ inference engine.
_Avoid_: omega-core, turbo engine

### PostTrainingQuantization (PTQ)
Weight and activation compression applied to a pre-trained Model without re-training (INT8, W4A8, FP16). The only quantization path available when no training GPU exists.
_Avoid_: QAT, fine-tuning, retraining

### StructuralReParameterization
Algebraic fusion of multi-branch training architectures (1×1 + 3×3 + identity + edge filters) into a single plain 3×3 convolution at export time, eliminating branch overhead on mobile GPUs.
_Avoid_: model pruning, layer merging

### HumanFriendlyPreset
User-facing high-level intent configuration (Content Type: `Photos` vs `Art & Anime` + Quality Tier: `Lightning` vs `Balanced` vs `Ultra`) that automatically maps to the optimal on-device Model without exposing confusing neural network jargon.
_Avoid_: model selector, engine picker

### UpscaleCoordinator
A deep architectural module orchestrating model bundle resolution, delta downloading, multi-stage engine initialization, and cascaded execution behind a single unified interface.
_Avoid_: upscale manager, workflow orchestrator

### ComparisonSlider
Interactive Before/After split-screen viewer widget supporting real-time horizontal drag divider and synchronized two-finger pinch-to-zoom & panning across original and upscaled images.
_Avoid_: split view, diff viewer

### BatchQueue
An ordered sequence of user-selected images processed sequentially in the background with individual and aggregate progress telemetry.
_Avoid_: job list, bulk task

## Notes
- Architecture: Pluggable Multi-Engine (ADR-0008, ADR-0009) routing models to `MnnEngineImpl` or `TfliteEngineImpl`.
- Memory & Performance: Adaptive Tiling (ADR-0009) with dynamic overlap feathering and runtime OOM fallback.
- Security & Privacy: 100% on-device local processing, zero network transmission of user images, cryptographic SHA256 download verification.
- Design: SuperImage-inspired Task-Driven single-screen UI (ADR-0015) with Lucide Vector Icons design system (ADR-0016), ComparisonSlider, and streaming Gallery saving for large 4000px+ images.
- Model Distribution: GitHub Releases CDN with dual bundled starter models (SAFMN & SRVGGNet Anime) for instant offline usage (ADR-0017).
- Edge Research: OmegaEdge (ADR-0011) — separate GPL-3.0 repo for compression research, hybrid integration with Omega via model artifacts.

