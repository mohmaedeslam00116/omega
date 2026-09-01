# Separate GPL-3.0 Research Repository (omega-edge) for Edge AI Model Optimization

We are creating a separate repository `omega-edge` (GPL-3.0) dedicated to researching and building techniques that make heavy super-resolution models (RealESRGAN 6–23 block RRDBNet) run under 500ms/tile on low-end ARM Mali GPUs (Helio P70 / Mali-G72 MP3), without any training GPU. The research focuses on Post-Training Quantization (PTQ), Structural Re-parameterization, and converting pre-trained lightweight architectures (SAFMN, PlainUSR, RFDN) to MNN format.

## Considered Options

- **Package inside Omega**: Rejected because research code (Python/PyTorch experiments, conversion scripts, benchmark harnesses) would pollute the Flutter production codebase with unrelated tooling and dependencies.
- **MIT license**: Rejected by the user in favor of GPL-3.0 to ensure all derivative optimization work remains open source.

## Consequences

- **Hybrid integration model**: The C++ inference engine stays in `omega-edge`; only converted model artifacts (`.mnn` files) flow into `omega-models` GitHub Releases and the Omega Catalog. Model weight files are data, not code, so GPL-3.0 copyleft does not propagate to Omega through them.
- **If Omega ever links `omega-edge` C++ engine code directly** (as a `.so`), Omega's distribution would need to comply with GPL-3.0. The current architecture avoids this: Omega uses its own MNN wrapper (`omega_mnn_wrapper.cpp`) independently.
- **No training GPU constraint** limits the research to PTQ, re-parameterization of existing checkpoints, and adoption of pre-trained lightweight models. Knowledge Distillation and NAS are deferred until a training GPU becomes available.
