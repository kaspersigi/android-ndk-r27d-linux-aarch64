#include <string>

extern "C" int cmake_smoke() {
    return static_cast<int>(std::string("cmake").size());
}
