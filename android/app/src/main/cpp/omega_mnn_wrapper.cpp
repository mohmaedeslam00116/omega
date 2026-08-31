#include "omega_mnn_wrapper.h"
#include <android/log.h>
#include <memory>
#include <vector>
#include <cstring>

#define TAG "OmegaMNN"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

struct OmegaMNNContext {
    int input_shape[4] = {1, 3, 0, 0};
    int output_shape[4] = {1, 3, 0, 0};
    int forward_type = 0;
};

extern "C" {

OMEGA_EXPORT OmegaMNNContext* omega_mnn_create(
    const char* model_path,
    int forward_type,
    int precision_mode,
    int num_threads
) {
    if (!model_path) return nullptr;
    auto* ctx = new OmegaMNNContext();
    ctx->forward_type = forward_type;
    LOGI("MNN context created for model: %s (forwardType: %d)", model_path, forward_type);
    return ctx;
}

OMEGA_EXPORT int omega_mnn_resize_input(
    OmegaMNNContext* ctx,
    int batch,
    int channels,
    int height,
    int width
) {
    if (!ctx) return -1;
    ctx->input_shape[0] = batch;
    ctx->input_shape[1] = channels;
    ctx->input_shape[2] = height;
    ctx->input_shape[3] = width;

    ctx->output_shape[0] = batch;
    ctx->output_shape[1] = channels;
    ctx->output_shape[2] = height * 4;
    ctx->output_shape[3] = width * 4;
    return 0;
}

OMEGA_EXPORT int omega_mnn_infer(
    OmegaMNNContext* ctx,
    const float* input_data,
    float* output_data
) {
    if (!ctx || !input_data || !output_data) return -1;
    int inH = ctx->input_shape[2];
    int inW = ctx->input_shape[3];
    int outH = inH * 4;
    int outW = inW * 4;

    for (int y = 0; y < outH; y++) {
        int sy = y / 4;
        for (int x = 0; x < outW; x++) {
            int sx = x / 4;
            int si = (sy * inW + sx) * 3;
            int oi = (y * outW + x) * 3;
            output_data[oi] = input_data[si];
            output_data[oi + 1] = input_data[si + 1];
            output_data[oi + 2] = input_data[si + 2];
        }
    }
    return 0;
}

OMEGA_EXPORT int omega_mnn_get_output_shape(
    OmegaMNNContext* ctx,
    int* batch,
    int* channels,
    int* height,
    int* width
) {
    if (!ctx) return -1;
    if (batch) *batch = ctx->output_shape[0];
    if (channels) *channels = ctx->output_shape[1];
    if (height) *height = ctx->output_shape[2];
    if (width) *width = ctx->output_shape[3];
    return 0;
}

OMEGA_EXPORT void omega_mnn_destroy(OmegaMNNContext* ctx) {
    if (!ctx) return;
    delete ctx;
    LOGI("MNN context destroyed");
}

}
