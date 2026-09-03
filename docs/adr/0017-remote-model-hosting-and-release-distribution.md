# ADR-0017: Remote Model Hosting via GitHub Releases and Dual Bundled Starter Models

- **Status**: Accepted
- **Date**: 2026-09-03
- **Deciders**: Mohmaed Eslam, Antigravity Agent

## Context

Omega utilizes a suite of ultra-lightweight SOTA neural super-resolution models (SAFMN, SRVGGNet Compact, RealESRGAN Anime 6B, RFDN, PlainUSR, NAFNet-Tiny, and SCUNet-Compact).
To provide an exceptional out-of-the-box user experience while maintaining a tiny application download size, we must decide:
1. Which models are bundled directly within the APK.
2. Where and how non-bundled models are hosted, versioned, and distributed on demand.

## Decision

1. **Dual Bundled Starter Models**:
   - `models/safmn_x4_int8.mnn` (240 KB): Bundled offline asset for General / Photos upscaling.
   - `models/srvggnet_compact_anime_int8.mnn` (320 KB): Bundled offline asset for Art & Anime upscaling.
   - *Total APK footprint impact*: $< 600$ KB.
   - *User benefit*: Instant, zero-network, out-of-the-box 4x upscaling for both Photos and Anime immediately upon installation.

2. **GitHub Releases Model CDN**:
   - All models are hosted as release assets under GitHub tag `models-v1.0.0` at repository `mohmaedeslam00116/omega`.
   - Asset URL schema: `https://github.com/mohmaedeslam00116/omega/releases/download/models-v1.0.0/<model_id>.mnn`
   - Every entry in `catalog.json` specifies:
     - `fileSize`: Exact payload byte count.
     - `sha256`: Cryptographic integrity verification string.
     - `url`: Direct HTTPS asset link.
     - `bundled`: Boolean indicating offline availability.

3. **Autonomous Delta Download & Storage**:
   - Downloaded models are cached in the app's sandboxed models directory.
   - Cached models are subject to user-managed storage limits (default 500 MB) with clean eviction and verification.

## Consequences

- **Zero External Third-Party Hosting Dependencies**: Relies purely on GitHub Infrastructure.
- **Immediate Offline Usability**: Both primary modes (Photos and Anime) work 100% offline without initial network access.
- **Bandwidth Efficiency**: Higher-tier and multi-stage refinement models download only when selected by the user.
