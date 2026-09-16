#include "read_dex_file.h"
#include "DexFile.h"
#include "MemoryBuffer.h"
#include <unwindstack/DexFiles.h>

#include <cstring>

#include <fstream>
#include <iostream>
#include <iterator>
#include <vector>

// Match the pinned upstream read_dex_file smoke fixture, including its exact
// symbol offset and length. Exercise both entrypoints that used to be stubs.
int main(int argc, char** argv) {
  if (argc != 2) return 2;
  const auto check = [](auto read) {
    size_t count = 0;
    bool found = false;
    bool ok = read([&](simpleperf::DexFileSymbol* symbol) {
      ++count;
      if (symbol->addr == 0x6c77e && symbol->size == 0x16 &&
          symbol->name == "com.example.simpleperf.simpleperfexamplewithnative.MixActivity$1.run") {
        found = true;
      }
    });
    return ok && found && count == 12435;
  };
  if (!check([&](auto callback) {
        return simpleperf::ReadSymbolsFromDexFile(argv[1], {0x28}, callback);
      })) return 3;
  std::ifstream file(argv[1], std::ios::binary);
  std::vector<char> bytes((std::istreambuf_iterator<char>(file)), {});
  if (!check([&](auto callback) {
        return simpleperf::ReadSymbolsFromDexFileInMemory(
            bytes.data(), bytes.size(), argv[1], {0x28}, callback);
      })) return 4;
  auto buffer = std::make_shared<unwindstack::MemoryBuffer>(bytes.size());
  if (buffer->Size() != bytes.size()) return 7;
  std::memcpy(buffer->Data(), bytes.data(), bytes.size());
  auto dex = unwindstack::DexFile::Create(0x28, bytes.size() - 0x28, buffer.get(), nullptr);
  unwindstack::SharedString name;
  uint64_t offset = 0;
  if (!dex || !dex->GetFunctionName(0x6c780, &name, &offset) || offset != 2 ||
      name != "com.example.simpleperf.simpleperfexamplewithnative.MixActivity$1.run") return 8;
  std::shared_ptr<unwindstack::Memory> memory = buffer;
  if (!unwindstack::CreateDexFiles(unwindstack::ARCH_ARM64, memory)) return 9;
  size_t callbacks = 0;
  auto callback = [&](auto*) { ++callbacks; };
  if (simpleperf::ReadSymbolsFromDexFileInMemory(
          bytes.data(), 8, "truncated", {0}, callback) || callbacks) return 5;
  if (simpleperf::ReadSymbolsFromDexFileInMemory(
          bytes.data(), bytes.size(), "bad-offset", {bytes.size() + 1}, callback) || callbacks) return 6;
  std::cout << "simpleperf-dex-ok symbols=12435 file+memory+unwindstack+invalid-input\n";
}
