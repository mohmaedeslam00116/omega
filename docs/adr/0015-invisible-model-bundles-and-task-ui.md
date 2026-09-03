# ADR-0015: SuperImage-Style Invisible Model Bundles and Pure Task-Driven UI

## Status
Accepted

## Context
Exposing low-level deep learning technical jargon (model filenames, parameter counts, tensor formats, architectures, catalog stores) confuses everyday mobile users. Popular high-quality mobile vision applications (such as SuperImage) completely hide internal model machinery behind pure task concepts (e.g., "Art & Anime" vs "Photos & Portraits").

## Decision
1. **Elimination of Technical Catalog Navigation**: Remove the standalone "Models / Catalog" tab from the primary user navigation. Users interact exclusively with task modes.
2. **Invisible On-Demand Bundle Resolution**: When a user selects a task (Anime vs Photos) or taps Upscale, the system transparently checks if the required micro-model bundle is cached locally. If missing, a clean, brief download overlay appears ("Preparing Anime Enhancer (~770 KB)...") and automatically begins upscaling upon completion.
3. **Pure Task-Driven Home Screen**: The main screen presents a clean mode switcher (`🎨 Art & Anime` | `📸 Photos & Portraits`), an image picker container (supporting single image and batch selection), and a 1-click Upscale action.
4. **Settings Access**: App settings (GPU acceleration, output format, dark/light theme, storage cache management) are accessible via a clean settings icon in the top app bar.

## Consequences
### Positive
- **Frictionless UX**: Everyday users never need to understand neural network models, weights, or INT8 quantization.
- **Visual Simplicity**: Screen real estate is entirely dedicated to the image picker, batch queue, and the before/after comparison slider.
- **Lean Footprint**: The app maintains a tiny APK size while fetching tiny specialized micro-model bundles on demand in 2-3 seconds.

### Negative / Trade-offs
- Advanced power users cannot manually inspect raw model tensor architectures from within the primary UI (manageable via settings storage cache).
