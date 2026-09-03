#include <string>

extern "C" int ndk_build_smoke() {
    return static_cast<int>(std::string("ndk-build").size());
}
