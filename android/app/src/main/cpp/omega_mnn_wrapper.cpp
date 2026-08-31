#include "omega_mnn_wrapper.h"
#include <MNN/Interpreter.hpp>
#include <MNN/Tensor.hpp>
#include <MNN/ImageProcess.hpp>
#include <android/log.h>
#include <memory>
#include <vector>
#include <cstring>
#include <algorithm>

#define TAG "OmegaMNN"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

struct OmegaMNNContext {
    std::shared_ptr<MNN::Interpreter> net;
    MNN::Session* session = nullptr;
    MNN::Tensor* input_tensor = nullptr;
    MNN::Tensor* output_tensor = nullptr;
    std::shared_ptr<MNN::Tensor> host_input;
    std::shared_ptr<MNN::Tensor> host_output;
    int current_side = 0;
    int scale = 4;
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

    ctx->net = std::shared_ptr<MNN::Interpreter>(MNN::Interpreter::createFromFile(model_path));
    if (!ctx->net) {
        LOGE("Failed to create MNN Interpreter from file: %s", model_path);
        delete ctx;
        return nullptr;
    }

    MNN::ScheduleConfig config;
    config.type = static_cast<MNNForwardType>(forward_type); // 3 = Vulkan, 2 = OpenCL, 0 = CPU
    config.numThread = num_threads > 0 ? num_threads : 4;

    MNN::BackendConfig backendConfig;
    backendConfig.precision = static_cast<MNN::BackendConfig::PrecisionMode>(precision_mode); // 2 = Low (FP16), 1 = Normal
    backendConfig.power = MNN::BackendConfig::Power_High;
    config.backendConfig = &backendConfig;

    ctx->session = ctx->net->createSession(config);
    if (!ctx->session && forward_type != MNN_FORWARD_CPU) {
        // Fallback to CPU if Vulkan/OpenCL fails
        LOGI("GPU session creation failed, falling back to CPU...");
        config.type = MNN_FORWARD_CPU;
        ctx->session = ctx->net->createSession(config);
    }

    if (!ctx->session) {
        LOGE("Failed to create MNN session for: %s", model_path);
        delete ctx;
        return nullptr;
    }

    ctx->input_tensor = ctx->net->getSessionInput(ctx->session, nullptr);
    ctx->output_tensor = ctx->net->getSessionOutput(ctx->session, nullptr);

    LOGI("MNN session created successfully for: %s (forward: %d)", model_path, forward_type);
    return ctx;
}

OMEGA_EXPORT int omega_mnn_resize_input(
    OmegaMNNContext* ctx,
    int batch,
    int channels,
    int height,
    int width
) {
    if (!ctx || !ctx->net || !ctx->session || !ctx->input_tensor) return -1;

    std::vector<int> shape = {batch, channels, height, width};
    ctx->net->resizeTensor(ctx->input_tensor, shape);
    ctx->net->resizeSession(ctx->session);
    ctx->current_side = width;

    // Refresh pointers after resize
    ctx->input_tensor = ctx->net->getSessionInput(ctx->session, nullptr);
    ctx->output_tensor = ctx->net->getSessionOutput(ctx->session, nullptr);

    // Create host tensors in NCHW float format for zero-copy / clean buffer feeding
    ctx->host_input = std::shared_ptr<MNN::Tensor>(
        new MNN::Tensor(ctx->input_tensor, MNN::Tensor::CAFFE)
    );
    ctx->host_output = std::shared_ptr<MNN::Tensor>(
        new MNN::Tensor(ctx->output_tensor, MNN::Tensor::CAFFE)
    );

    LOGI("Resized MNN session to [%d, %d, %d, %d]", batch, channels, height, width);
    return 0;
}

OMEGA_EXPORT int omega_mnn_infer(
    OmegaMNNContext* ctx,
    const float* input_data, // NHWC float32 [1, H, W, 3]
    float* output_data       // NHWC float32 [1, H*4, W*4, 3]
) {
    if (!ctx || !ctx->net || !ctx->session || !input_data || !output_data) return -1;
    if (!ctx->host_input || !ctx->host_output) {
        omega_mnn_resize_input(ctx, 1, 3, 64, 64);
    }

    int inH = ctx->input_tensor->height() > 0 ? ctx->input_tensor->height() : ctx->current_side;
    int inW = ctx->input_tensor->width() > 0 ? ctx->input_tensor->width() : ctx->current_side;
    int inPlane = inH * inW;

    // Convert NHWC (Dart float32 [0..1]) -> NCHW host tensor (MNN)
    float* host_in_ptr = ctx->host_input->host<float>();
    for (int y = 0; y < inH; y++) {
        for (int x = 0; x < inW; x++) {
            int nhwc_idx = (y * inW + x) * 3;
            int nchw_idx = y * inW + x;
            host_in_ptr[nchw_idx] = input_data[nhwc_idx];                 // R
            host_in_ptr[inPlane + nchw_idx] = input_data[nhwc_idx + 1];     // G
            host_in_ptr[2 * inPlane + nchw_idx] = input_data[nhwc_idx + 2]; // B
        }
    }

    // Transfer host input -> device tensor
    ctx->input_tensor->copyFromHostTensor(ctx->host_input.get());

    // Execute Neural Network Graph on Vulkan GPU / CPU
    MNN::ErrorCode err = ctx->net->runSession(ctx->session);
    if (err != MNN::NO_ERROR) {
        LOGE("MNN runSession error: %d", err);
        return static_cast<int>(err);
    }

    // Transfer device output -> host tensor
    ctx->output_tensor->copyToHostTensor(ctx->host_output.get());

    int outH = ctx->output_tensor->height();
    int outW = ctx->output_tensor->width();
    int outPlane = outH * outW;
    const float* host_out_ptr = ctx->host_output->host<float>();

    // Convert NCHW host output (MNN) -> NHWC output (Dart float32 [0..1])
    for (int y = 0; y < outH; y++) {
        for (int x = 0; x < outW; x++) {
            int nhwc_idx = (y * outW + x) * 3;
            int nchw_idx = y * outW + x;
            // Clamp output to [0..1] range
            output_data[nhwc_idx] = std::max(0.0f, std::min(1.0f, host_out_ptr[nchw_idx]));
            output_data[nhwc_idx + 1] = std::max(0.0f, std::min(1.0f, host_out_ptr[outPlane + nchw_idx]));
            output_data[nhwc_idx + 2] = std::max(0.0f, std::min(1.0f, host_out_ptr[2 * outPlane + nchw_idx]));
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
    if (!ctx || !ctx->output_tensor) return -1;
    if (batch) *batch = ctx->output_tensor->batch();
    if (channels) *channels = ctx->output_tensor->channel();
    if (height) *height = ctx->output_tensor->height();
    if (width) *width = ctx->output_tensor->width();
    return 0;
}

OMEGA_EXPORT void omega_mnn_destroy(OmegaMNNContext* ctx) {
    if (!ctx) return;
    if (ctx->net && ctx->session) {
        ctx->net->releaseSession(ctx->session);
    }
    delete ctx;
    LOGI("MNN context destroyed cleanly");
}

}
