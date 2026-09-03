#include "read_dex_file.h"

namespace simpleperf {

bool ReadSymbolsFromDexFileInMemory(
    void*, uint64_t, const std::string&, const std::vector<uint64_t>&,
    const std::function<void(DexFileSymbol*)>&) {
  return false;
}

bool ReadSymbolsFromDexFile(const std::string&, const std::vector<uint64_t>&,
                            const std::function<void(DexFileSymbol*)>&) {
  return false;
}

}  // namespace simpleperf
