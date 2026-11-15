cmake_minimum_required(VERSION 3.18)
project(blur_native LANGUAGES CXX)

find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs)

# ONNX Runtime (CUDA 13 build), fetched once into a per-user cache shared by
# every build directory.
if(DEFINED ENV{XDG_CACHE_HOME} AND NOT "$ENV{XDG_CACHE_HOME}" STREQUAL "")
  set(_cache_home "$ENV{XDG_CACHE_HOME}")
else()
  set(_cache_home "$ENV{HOME}/.cache")
endif()
set(BLUR_DEPS_DIR "${_cache_home}/blur-app/deps" CACHE PATH
    "Where downloaded build dependencies are kept")
set(ORT_VERSION 1.32.0)
set(ORT_NAME "onnxruntime-linux-x64-gpu_cuda13-${ORT_VERSION}")
set(ORT_ROOT "${BLUR_DEPS_DIR}/${ORT_NAME}")
if(NOT EXISTS "${ORT_ROOT}/lib/libonnxruntime.so.${ORT_VERSION}")
  message(STATUS "Fetching ${ORT_NAME} into ${BLUR_DEPS_DIR}")
  file(DOWNLOAD
    "https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/${ORT_NAME}.tgz"
    "${BLUR_DEPS_DIR}/${ORT_NAME}.tgz"
    EXPECTED_HASH SHA256=f7f4bdaa2db5edd0652e9c205f2cba18317f74af3bf2fdeefa34b5af160f10f0
    SHOW_PROGRESS)
  file(ARCHIVE_EXTRACT INPUT "${BLUR_DEPS_DIR}/${ORT_NAME}.tgz"
    DESTINATION "${BLUR_DEPS_DIR}")
endif()

add_library(blur_native SHARED blur_native.cpp)
target_compile_features(blur_native PRIVATE cxx_std_17)
target_compile_options(blur_native PRIVATE -Wall -Wextra -fvisibility=hidden)
target_include_directories(blur_native PRIVATE ${OpenCV_INCLUDE_DIRS}
  "${ORT_ROOT}/include")
target_link_libraries(blur_native PRIVATE ${OpenCV_LIBS}
  "${ORT_ROOT}/lib/libonnxruntime.so.${ORT_VERSION}")
# Bundled next to ONNX Runtime; the standalone build finds it in the cache.
set_target_properties(blur_native PROPERTIES INSTALL_RPATH "$ORIGIN")

# When built as part of the app, bundle ONNX Runtime beside the engine. It
# loads the two provider libraries from its own folder; the engine links it
# by its short (soname) file name.
if(DEFINED INSTALL_BUNDLE_LIB_DIR)
  install(FILES
    "${ORT_ROOT}/lib/libonnxruntime_providers_shared.so"
    "${ORT_ROOT}/lib/libonnxruntime_providers_cuda.so"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
  install(FILES "${ORT_ROOT}/lib/libonnxruntime.so.${ORT_VERSION}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" RENAME "libonnxruntime.so.1"
    COMPONENT Runtime)
endif()
