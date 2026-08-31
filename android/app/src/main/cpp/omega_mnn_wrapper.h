#ifndef OMEGA_MNN_WRAPPER_H
#define OMEGA_MNN_WRAPPER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define OMEGA_EXPORT __declspec(dllexport)
#else
#define OMEGA_EXPORT __attribute__((visibility("default")))
#endif

typedef struct OmegaMNNContext OmegaMNNContext;

enum OmegaForwardType {
    OMEGA_FORWARD_CPU = 0,
    OMEGA_FORWARD_OPENCL = 2,
    OMEGA_FORWARD_VULKAN = 3,
    OMEGA_FORWARD_AUTO = 4
};

enum OmegaPrecisionMode {
    OMEGA_PRECISION_NORMAL = 0,
    OMEGA_PRECISION_HIGH = 1,
    OMEGA_PRECISION_LOW = 2
};

OMEGA_EXPORT OmegaMNNContext* omega_mnn_create(
    const char* model_path,
    int forward_type,
    int precision_mode,
    int num_threads
);

OMEGA_EXPORT int omega_mnn_resize_input(
    OmegaMNNContext* ctx,
    int batch,
    int channels,
    int height,
    int width
);

OMEGA_EXPORT int omega_mnn_infer(
    OmegaMNNContext* ctx,
    const float* input_data,
    float* output_data
);

OMEGA_EXPORT int omega_mnn_get_output_shape(
    OmegaMNNContext* ctx,
    int* batch,
    int* channels,
    int* height,
    int* width
);

OMEGA_EXPORT void omega_mnn_destroy(OmegaMNNContext* ctx);

#ifdef __cplusplus
}
#endif

#endif // OMEGA_MNN_WRAPPER_H
