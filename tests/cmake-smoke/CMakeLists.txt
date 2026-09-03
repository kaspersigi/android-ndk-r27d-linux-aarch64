cmake_minimum_required(VERSION 3.22)
project(ndk_arm64_cmake_smoke LANGUAGES C CXX)

add_library(ndk_arm64_cmake_smoke SHARED smoke.cpp)
target_compile_features(ndk_arm64_cmake_smoke PRIVATE cxx_std_17)
