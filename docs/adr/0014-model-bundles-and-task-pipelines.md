# ADR-0014: Model Bundles and Task-Based Cascaded Pipelines

## Status
Accepted

## Context
Executing specialized multi-stage vision workflows (such as Anime restoration or Real Photo enhancement) requires coordinating multiple atomic micro-models (e.g. Denoise 1x + Upscale 4x + Detail Refinement). If models are treated purely as isolated downloads, users may attempt to run multi-stage pipelines with missing intermediate models, leading to incomplete processing or unexpected degradation.

## Decision
1. **Atomic Micro-Models with Roles**: Individual models in `catalog.json` declare a specific `role` (`denoise`, `upscale`, `face_refine`, `line_refine`).
2. **Model Bundles**: Introduce `ModelBundle` to group the atomic micro-models required for a target task (e.g., `AnimeTaskBundle`, `PhotoTaskBundle`).
3. **Bundle Resolver & Delta Download Policy**: Before starting a task pipeline, `BundleResolver` verifies local presence of all models in the bundle. If any models are missing, only the missing delta models are downloaded before executing the full pipeline. Pipelines never execute in an unconfigured partial state by default.
4. **Hybrid Adaptive Routing**: Image type detection uses fast edge-density and color-variance heuristics by default, but explicit user manual selection always holds highest priority.

## Consequences
### Positive
- **Guaranteed Output Fidelity**: Pipelines always execute with their full intended set of specialized models.
- **Efficient Bandwidth**: Missing models are detected and downloaded selectively without re-downloading existing components.
- **Declarative Schema**: New workflows can be added to `catalog.json` dynamically without changing pipeline code.

### Negative / Trade-offs
- First-time execution of a new task bundle may require downloading 2-3 small models rather than 1.
