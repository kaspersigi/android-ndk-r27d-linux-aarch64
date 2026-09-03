#include <cxxabi.h>

#include <cstdlib>
#include <cstring>

extern "C" char* rustc_demangle(const char* mangled, char* output, size_t* length, int* status) {
  // Legacy Rust symbols use the Itanium encoding. New v0 symbols return the
  // same failure code as rustc-demangle when this compatibility fallback
  // cannot decode them.
  char* result = abi::__cxa_demangle(mangled, nullptr, nullptr, status);
  if (result == nullptr || output == nullptr || length == nullptr) return result;
  size_t needed = strlen(result) + 1;
  if (*length < needed) {
    free(output);
    output = static_cast<char*>(malloc(needed));
    if (output == nullptr) {
      free(result);
      if (status != nullptr) *status = -1;
      return nullptr;
    }
    *length = needed;
  }
  memcpy(output, result, needed);
  free(result);
  return output;
}
