// SPDX-License-Identifier: Apache-2.0

#include "rustc_demangle.h"

#include <cstdlib>
#include <cstring>
#include <iostream>

namespace {

void fail(const char* message) {
  std::cerr << "rust-demangle-smoke: " << message << '\n';
  std::exit(1);
}

}  // namespace

int main() {
  int status = 123;
  size_t size = 0;
  char* demangled = rustc_demangle("_RNvC3foo3bar", nullptr, &size, &status);
  if (demangled == nullptr || status != 0 || std::strcmp(demangled, "foo::bar") != 0) {
    std::free(demangled);
    fail("Rust v0 symbol did not demangle to foo::bar");
  }
  if (size != std::strlen("foo::bar") + 1) {
    std::free(demangled);
    fail("allocated buffer size was not reported correctly");
  }
  std::free(demangled);

  size = 2;
  char* supplied = static_cast<char*>(std::malloc(size));
  if (supplied == nullptr) fail("failed to allocate test buffer");
  demangled = rustc_demangle("_RNvC1a4main", supplied, &size, &status);
  if (demangled == nullptr || status != 0 || std::strcmp(demangled, "a::main") != 0) {
    std::free(demangled == nullptr ? supplied : demangled);
    fail("caller-provided buffer was not resized correctly");
  }
  std::free(demangled);

  size = 0;
  demangled = rustc_demangle("_ZN4testE", nullptr, &size, &status);
  if (demangled == nullptr || status != 0 || std::strcmp(demangled, "test") != 0) {
    std::free(demangled);
    fail("legacy Rust symbol did not demangle to test");
  }
  if (size != std::strlen("test") + 1) {
    std::free(demangled);
    fail("legacy Rust symbol buffer size was not reported correctly");
  }
  std::free(demangled);

  demangled = rustc_demangle("not-a-rust-symbol", nullptr, nullptr, &status);
  if (demangled != nullptr || status != -2) {
    std::free(demangled);
    fail("invalid Rust symbol did not return demangle failure");
  }

  std::cout << "rust-demangle-legacy-v0-ok\n";
  return 0;
}
