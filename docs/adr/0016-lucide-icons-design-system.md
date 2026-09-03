# ADR-0016: Studio-Grade Vector Design System with Lucide Icons

## Status
Accepted

## Context
Relying on raw Unicode emojis (e.g. 🎨, 📸, ⚡, 💎) in UI labels, preset buttons, and status indicators introduces visual inconsistency across different Android OS skins (EMUI, MIUI, OneUI, ColorOS) and makes the user interface feel unpolished. A professional mobile AI application requires a consistent, sharp vector icon design language.

## Decision
1. **Adopt `lucide_icons_flutter`**: Standardize all application icons on Lucide Icons (2px stroke line art with clean geometric symmetry).
2. **Complete Emoji Purge**: Remove all text-based emojis from:
   - `PresetContentType` (`LucideIcons.camera` for Photos, `LucideIcons.palette` for Art & Anime).
   - `PresetQualityTier` and `ModelTier` (`LucideIcons.zap` for Lightning, `LucideIcons.scale` for Balanced, `LucideIcons.sparkles` for Ultra Quality).
   - Mode selectors, dimensions badge, action buttons, and status indicators.
3. **High-Contrast State Styling**: Active/selected items dynamically transition icon colors to the theme's primary color with high contrast.

## Consequences
### Positive
- **Visual Elegance**: Consistent, studio-grade aesthetic across all devices and screen densities regardless of OEM Android version.
- **Scalability**: Clean icon API with hundreds of matching stroke-based glyphs.
- **Zero OS Font Dependency**: Icons render identically on stock Android, custom ROMs, and tablets.

### Negative / Trade-offs
- Adds a small vector font asset (`lucide_icons_flutter`) to the APK footprint (~100KB).
