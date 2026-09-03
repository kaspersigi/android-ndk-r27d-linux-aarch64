#include <string>

extern "C" int android_hello_cpp() {
    return static_cast<int>(std::string("ndk-r27d").size());
}
