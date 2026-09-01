# Material 3 Expressive UI Overhaul with Human-Friendly Presets and High-Resolution Gallery Saving

We are completely overhauling Omega's UI and interaction design to deliver a modern, intuitive experience inspired by SuperImage on Android, while replacing confusing machine learning model names with human-friendly presets and fixing gallery saves for large 4000px+ images.

## Considered Options

- **Technical Dropdown & Raw Architecture Names**: Rejected because casual users do not understand deep learning model acronyms (e.g. `RRDBNet`, `SAFMN`, `INT8`, `6B`).
- **2-Tab Layout with App Bar Actions**: Rejected in favor of a clean, dedicated 3-tab Material 3 NavigationBar (`Upscale`, `Models`, `Settings`).
- **Pure In-Memory Image Decoding for Gallery Saving**: Rejected because decoding large 4000×4000+ images in main Dart isolate causes out-of-memory crashes and triggers artificial >4096px size rejections.

## Decision

1. **3-Tab Navigation Hierarchy:**
   - 🖼️ **Upscale:** Hero image picker, HumanFriendlyPresets selection, floating upscale button with animated progress, and Batch Queue carousel.
   - 📦 **Models / Catalog:** Clean model download manager and library.
   - ⚙️ **Settings:** Material 3 card-based settings (Dark/Light theme, Output format PNG/JPEG/WebP, GPU acceleration toggle with hardware specs card, Auto-save toggle).
2. **Human-Friendly Presets:**
   - **Content Mode:** Photos & Pictures 🖼️ (maps to PlainUSR/General) vs. Art & Anime 🎨 (maps to SAFMN/Anime 6B).
   - **Performance Tier:** ⚡ Lightning (~56ms) vs. 💎 Ultra Quality (RRDBNet deep synthesis).
   - Technical details remain accessible inside the Models tab for power users.
3. **Interactive Comparison Slider:**
   - Horizontal drag split divider with synchronized pinch-to-zoom and pan via `InteractiveViewer`.
4. **High-Resolution Gallery Saving (4000px+):**
   - Stream saved images directly to Android MediaStore/Gallery via `Gal.putImage` and remove the restrictive 4096px validation blocker.
