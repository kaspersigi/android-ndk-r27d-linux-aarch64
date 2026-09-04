// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

#include "llvm/Demangle/Demangle.h"

#include <cstdlib>
#include <cstring>

extern "C" char* rustc_demangle(const char* mangled, char* output, size_t* length, int* status) {
  if (mangled == nullptr || (output != nullptr && (length == nullptr || *length == 0))) {
    if (status != nullptr) *status = -3;
    return nullptr;
  }

  char* demangled = llvm::rustDemangle(mangled);
  if (demangled == nullptr) {
    // Rust's legacy mangling is based on the Itanium C++ ABI (`_ZN...E`).
    demangled = llvm::itaniumDemangle(mangled);
  }
  if (demangled == nullptr) {
    if (status != nullptr) *status = -2;
    return nullptr;
  }

  const size_t needed = std::strlen(demangled) + 1;
  if (output == nullptr) {
    if (length != nullptr) *length = needed;
    if (status != nullptr) *status = 0;
    return demangled;
  }

  if (*length < needed) {
    char* resized = static_cast<char*>(std::realloc(output, needed));
    if (resized == nullptr) {
      std::free(demangled);
      if (status != nullptr) *status = -1;
      return nullptr;
    }
    output = resized;
    *length = needed;
  }
  std::memcpy(output, demangled, needed);
  std::free(demangled);
  if (status != nullptr) *status = 0;
  return output;
}
