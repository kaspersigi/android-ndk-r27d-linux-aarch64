LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := ndk_build_smoke
LOCAL_SRC_FILES := smoke.cpp
LOCAL_CPP_FEATURES := exceptions
include $(BUILD_SHARED_LIBRARY)
