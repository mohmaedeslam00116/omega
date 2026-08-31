# ADR 0008: Pluggable Multi-Engine Architecture for Super-Resolution Models

- **Date:** 2026-08-31
- **Status:** Accepted

## Context
Omega initially supported TFLite for on-device inference (ADR-0003). However, state-of-the-art super-resolution models (such as RealESRGAN RRDBNet 68MB and Vision Transformers) exceed TFLite's mobile GPU acceleration efficiency and memory bandwidth limits. Alibaba MNN provides superior Vulkan/OpenCL shader scheduling and FP16/INT8 weight quantization on ARM mobile GPUs.

## Decision
We evolve Omega's inference engine into a **Pluggable Multi-Engine Architecture**:
1. **Engine Interface Contract**: The \TfliteEngine\ interface acts as the universal super-resolution engine contract (NHWC float32 tensors, tile-based inference).
2. **Pluggable Engine Implementations**:
   - \TfliteEngineImpl\: Default Google TFLite / LiteRT backend for standard lightweight models (.tflite).
   - \MnnEngineImpl\: Alibaba MNN backend with Vulkan/OpenCL GPU acceleration via Dart FFI (\libomega_mnn.so\) for heavy models (.mnn).
3. **Engine Factory Routing**: \EngineFactory.createForModel()\ dynamically inspects model format and instantiates the optimal backend engine inside worker isolates.
4. **Catalog Schema Extension**: \CatalogEntry\ includes an \EngineBackend\ field (\	flite\, \mnn\, \onnx\) with automatic URL inference.

## Alternatives Considered
- **Monolithic TFLite Only**: Cannot execute heavy RRDBNet models at high frame rates due to lack of custom Vulkan shader pipelines.
- **Android Platform Channels for MNN**: High data copying overhead (>50MB per tile across JNI) causing garbage collection frame drops. Direct FFI was selected instead.

## Consequences
- Clean separation of concerns between upscale pipeline / tiling logic and native inference runtimes.
- Transparent support for both TFLite models and heavy MNN Vulkan models in the catalog.
- Zero-copy native tensor execution inside background worker isolates.
