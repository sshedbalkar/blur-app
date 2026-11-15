cmake_minimum_required(VERSION 3.13)
project(blur_native LANGUAGES CXX)

find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs)

add_library(blur_native SHARED blur_native.cpp)
target_compile_features(blur_native PRIVATE cxx_std_17)
target_compile_options(blur_native PRIVATE -Wall -Wextra -fvisibility=hidden)
target_include_directories(blur_native PRIVATE ${OpenCV_INCLUDE_DIRS})
target_link_libraries(blur_native PRIVATE ${OpenCV_LIBS})
