# Omega — Image Upscaler

Mobile app that upscales images on-device using downloadable TFLite models hosted as a versioned catalog on GitHub Releases.

## Language

### Catalog
A versioned list of downloadable upscale models published as GitHub Release assets with metadata (scale, type, size, sha256).
_Avoid_: model store, release list

### Model
A single TFLite file representing weights for a specific upscale type and scale.
_Avoid_: weights, checkpoint, network

### Engine
The on-device TFLite Interpreter that executes a Model, optionally with GPU delegate.
_Avoid_: runtime, executor, inference engine

### Scale
Integer factor by which an image is enlarged (e.g., 2x, 4x). A property of a Model.
_Avoid_: zoom, magnification, ratio

### Tile
A rectangular sub-region of an input image processed independently when the image exceeds memory limits; tiles overlap to avoid seam artifacts.
_Avoid_: chunk, patch, block

### Upscale
To increase image resolution using a Model, preserving content while synthesizing detail.
_Avoid_: enhance, super-resolve, enlarge (as generic terms)

### CatalogEntry
One item in a Catalog describing a single downloadable Model (id, scale, type, inputSize, url, sha256, license).
_Avoid_: model info, catalog item

### Download
The process of fetching a CatalogEntry's Model to local storage with verification and caching.
_Avoid_: fetch, pull

### Preprocess
Turning a source Tile into the float32 tensor an Engine consumes (normalize 0..1 + RGB layout) before inference.
_Avoid_: normalize step, input preparation

### Stitch
Compositing the upscaled Tiles into the final image, feathering overlapping borders so no seams show.
_Avoid_: glue, mosaic, paste

### UpscaleJob
A single, cancellable upscale operation with progress reporting, executed in a background Isolate.
_Avoid_: upscale task, job queue

## Notes
- Scope: Round 4 settled — Real inference end-to-end (engine contract Float32List), full pipeline in a fresh Isolate per UpscaleJob, seam-free Stitch with blended overlap, 512MB pre-flight memory guard, cancel button, Model picker in Upscale tab (bundled + downloaded, auto-download), PNG/JPEG save sheet (preference remembered), remove scaffold button. Tree closed.
- Design: `impeccable` UI — distinctive, intentional, not templated; use design tokens, typography, and icon system.
