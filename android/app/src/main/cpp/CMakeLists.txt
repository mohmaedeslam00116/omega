cmake_minimum_required(VERSION 3.18.1)
project(omega_mnn LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Include directories
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)

# Import prebuilt MNN libraries
add_library(MNN SHARED IMPORTED)
set_target_properties(MNN PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libMNN.so"
)

add_library(MNN_Vulkan SHARED IMPORTED)
set_target_properties(MNN_Vulkan PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libMNN_Vulkan.so"
)

add_library(MNN_CL SHARED IMPORTED)
set_target_properties(MNN_CL PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libMNN_CL.so"
)

# Build Omega C wrapper
add_library(omega_mnn SHARED
    omega_mnn_wrapper.cpp
)

# Link dependencies
find_library(log-lib log)
find_library(vulkan-lib vulkan)
find_library(dl-lib dl)

target_link_libraries(omega_mnn
    MNN
    MNN_Vulkan
    MNN_CL
    ${log-lib}
    ${vulkan-lib}
    ${dl-lib}
)
