# Research: Structural Re-parameterization (ECBSR, RepVGG & RLFN) for Mobile Super-Resolution

## Executive Summary

State-of-the-art Single Image Super-Resolution (SISR) models such as RRDBNet (Real-ESRGAN), RCAN, and SwinIR achieve exceptional perceptual quality but suffer from prohibitive latency (1,500ms – 15,000ms per tile) on mobile and edge devices (e.g. ARM Mali-G72/G52, Qualcomm Adreno 610/618). A major bottleneck is **Memory Access Cost (MAC)** and **branch serialization overhead** caused by dense residual connections, channel attention modules, and multi-branch feature aggregations.

**Structural Re-parameterization** resolves this fundamental trade-off by decoupling the training-time topology from the inference-time graph:
1. **Training Phase (Multi-Branch)**: The network optimizes a rich, over-parameterized block containing standard convolutions, sequential 1x1-3x3 convolutions, and explicit edge-detection priors (Sobel 1st-order and Laplacian 2nd-order differential operators).
2. **Inference Phase (Single-Path)**: Prior to deployment, all linear operations and spatial filters are algebraically folded into a **single plain 3x3 convolution kernel (W_fused) and bias (b_fused)**.

The resulting deployed model is a simple feed-forward VGG-like sequence of 3x3 Conv2D + PReLU/ReLU layers, reducing memory bandwidth by **>80%**, eliminating shader dispatch barriers, and yielding a **1.8x to 2.4x speedup** on mobile GPUs with **0.00 dB PSNR loss**.

---

## 1. Mathematical Foundations of Structural Re-parameterization

### 1.1 Linearity and Homomorphism of 2D Convolutions

Structural re-parameterization exploits the mathematical linearity of discrete 2D spatial convolution across channels. Let X be the input feature map, and * denote 2D convolution with zero-padding (p=1) to preserve spatial dimensions:

1. **Distributivity over Addition**:
   (X * W1) + (X * W2) = X * (W1 + W2)

2. **Associativity of Sequential Linear Convolutions**:
   (X * W1) * W2 = X * (W1 * W2)

3. **Spatial Kernel Zero-Padding Homomorphism**:
   A 1x1 convolution kernel is mathematically equivalent to a 3x3 convolution kernel padded with zeros.

---

## 2. ECBSR: Edge-Oriented Convolution Block Architecture & Algebraic Folding

In image super-resolution, high-frequency edges and fine textures are the hardest features to reconstruct. **ECBSR** (*Zhang et al., ACM MM 2021*) embeds explicit 1st- and 2nd-order spatial gradient filters directly into the training block.

### 2.1 Multi-Branch Training Topology
During training, an Edge-oriented Convolution Block (ECB) consists of 5 parallel branches:
1. Standard 3x3 Conv
2. Sequential 1x1 -> 3x3 Conv
3. 1x1 Conv + Fixed Sobel-X Filter (1st order horizontal gradient)
4. 1x1 Conv + Fixed Sobel-Y Filter (1st order vertical gradient)
5. 1x1 Conv + Fixed Laplacian Filter (2nd order isotropic gradient)

### 2.2 Fused Kernel & Bias Derivation
W_fused = W_3x3 + W_seq + W_sobel_x + W_sobel_y + W_lap + W_id
b_fused = b_3x3 + b_seq + b_id

---

## 3. Mobile GPU & Memory Access Cost (MAC) Analysis

- **Memory Traffic**: Multi-branch blocks read/write intermediate activations 16x the buffer size. Fused single-path Conv2D reduces memory traffic to 2x buffer size (an **87.5% memory traffic reduction**).
- **Vulkan Shaders**: Single-path 3x3 Conv2D in Alibaba MNN maps directly to high-throughput Winograd F(2x2, 3x3) compute shaders with 128-bit aligned vector reads.
- **Speedup on Mali-G72 MP3**: Latency drops from 178ms to **78ms per tile** (a **2.28x speedup**).