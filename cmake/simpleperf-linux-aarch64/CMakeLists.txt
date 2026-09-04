cmake_minimum_required(VERSION 3.16)
project(simpleperf_report_aarch64 LANGUAGES C CXX)

set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
set(CMAKE_C_STANDARD 17)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
add_compile_options(-ffunction-sections -fdata-sections -fvisibility=hidden)

if(NOT NDK_PROJECT_ROOT)
  message(FATAL_ERROR "NDK_PROJECT_ROOT is required")
endif()

set(ROOT "${NDK_PROJECT_ROOT}")
set(SIMPLEPERF "${ROOT}/sources/system-extras/simpleperf")
set(GENERATED "${ROOT}/build/simpleperf-generated")
set(DEPS "${ROOT}/out/host-deps-linux-aarch64")

set(FMT_DOC OFF CACHE BOOL "" FORCE)
set(FMT_TEST OFF CACHE BOOL "" FORCE)
set(FMT_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory("${ROOT}/sources/fmtlib" fmtlib EXCLUDE_FROM_ALL)

set(ZSTD_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(ZSTD_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(ZSTD_MULTITHREAD_SUPPORT OFF CACHE BOOL "" FORCE)
add_subdirectory("${ROOT}/sources/zstd/build/cmake" zstd EXCLUDE_FROM_ALL)

add_library(android_log_compat STATIC "${ROOT}/compat/android_log_stubs.cpp")
target_include_directories(android_log_compat PUBLIC
  "${ROOT}/sources/system-logging/liblog/include")

add_library(android_base STATIC
  "${ROOT}/sources/system-libbase/abi_compatibility.cpp"
  "${ROOT}/sources/system-libbase/chrono_utils.cpp"
  "${ROOT}/sources/system-libbase/cmsg.cpp"
  "${ROOT}/sources/system-libbase/errors_unix.cpp"
  "${ROOT}/sources/system-libbase/file.cpp"
  "${ROOT}/sources/system-libbase/hex.cpp"
  "${ROOT}/sources/system-libbase/logging.cpp"
  "${ROOT}/sources/system-libbase/mapped_file.cpp"
  "${ROOT}/sources/system-libbase/parsebool.cpp"
  "${ROOT}/sources/system-libbase/parsenetaddress.cpp"
  "${ROOT}/sources/system-libbase/posix_strerror_r.cpp"
  "${ROOT}/sources/system-libbase/process.cpp"
  "${ROOT}/sources/system-libbase/properties.cpp"
  "${ROOT}/sources/system-libbase/stringprintf.cpp"
  "${ROOT}/sources/system-libbase/strings.cpp"
  "${ROOT}/sources/system-libbase/threads.cpp")
target_include_directories(android_base PUBLIC "${ROOT}/sources/system-libbase/include")
target_link_libraries(android_base PUBLIC fmt::fmt android_log_compat)

add_library(procinfo STATIC "${ROOT}/sources/system-libprocinfo/process.cpp")
target_include_directories(procinfo PUBLIC "${ROOT}/sources/system-libprocinfo/include")
target_link_libraries(procinfo PUBLIC android_base)

file(GLOB LZMA_SOURCES "${ROOT}/sources/lzma/C/*.c")
list(FILTER LZMA_SOURCES EXCLUDE REGEX "/(Util|LzmaUtil|7zMain|Client7z|DllSecur|LzFindMt|Lzma2DecMt|MtCoder|MtDec|Threads|Bcj2Enc)\\.c$")
add_library(lzma_sdk STATIC ${LZMA_SOURCES})
target_compile_definitions(lzma_sdk PUBLIC _7ZIP_ST)
target_include_directories(lzma_sdk PUBLIC "${ROOT}/sources/lzma/C")

set(UNWINDSTACK_SOURCES
  AndroidUnwinder.cpp ArmExidx.cpp Demangle.cpp DexFiles.cpp DwarfCfa.cpp
  DwarfEhFrameWithHdr.cpp DwarfMemory.cpp DwarfOp.cpp DwarfSection.cpp Elf.cpp
  ElfInterface.cpp ElfInterfaceArm.cpp Global.cpp JitDebug.cpp MapInfo.cpp Maps.cpp
  Memory.cpp MemoryMte.cpp MemoryXz.cpp Regs.cpp RegsArm.cpp RegsArm64.cpp
  RegsX86.cpp RegsX86_64.cpp RegsRiscv64.cpp Symbols.cpp ThreadEntry.cpp
  ThreadUnwinder.cpp Unwinder.cpp LogStdout.cpp)
list(TRANSFORM UNWINDSTACK_SOURCES PREPEND "${ROOT}/sources/system-unwinding/libunwindstack/")
add_library(unwindstack STATIC ${UNWINDSTACK_SOURCES} "${ROOT}/compat/rustc_demangle.cpp")
target_include_directories(unwindstack PUBLIC
  "${ROOT}/sources/system-unwinding/libunwindstack/include"
  "${ROOT}/sources/system-unwinding/libunwindstack"
  "${ROOT}/sources/rustc-demangle-capi/include"
  "${ROOT}/sources/llvm-project/llvm/include"
  "${ROOT}/sources/zstd/lib")
target_link_libraries(unwindstack PUBLIC android_base procinfo lzma_sdk libzstd_static
  "${DEPS}/lib/libz.a")

add_library(ziparchive STATIC
  "${ROOT}/sources/system-libziparchive/zip_archive.cc"
  "${ROOT}/sources/system-libziparchive/zip_archive_stream_entry.cc"
  "${ROOT}/sources/system-libziparchive/zip_cd_entry_map.cc"
  "${ROOT}/sources/system-libziparchive/zip_error.cpp")
target_compile_definitions(ziparchive PUBLIC ZLIB_CONST INCFS_SUPPORT_DISABLED=1)
target_include_directories(ziparchive PUBLIC
  "${ROOT}/sources/system-libziparchive/include"
  "${ROOT}/sources/system-libziparchive/incfs_support/include"
  "${ROOT}/sources/system-core/libutils/include"
  "${ROOT}/sources/system-core/libutils/binder/include"
  "${DEPS}/include")
target_link_libraries(ziparchive PUBLIC android_base "${DEPS}/lib/libz.a")

add_library(protobuf_lite STATIC IMPORTED GLOBAL)
set_target_properties(protobuf_lite PROPERTIES
  IMPORTED_LOCATION "${ROOT}/out/simpleperf-deps-linux-aarch64/lib/libprotobuf-lite.a"
  INTERFACE_INCLUDE_DIRECTORIES "${ROOT}/sources/protobuf/src")

set(SIMPLEPERF_SOURCES
  JITDebugReader.cpp RecordFilter.cpp command.cpp dso.cpp event_attr.cpp
  event_type.cpp ETMRecorder.cpp record_file_reader.cpp report_utils.cpp thread_tree.cpp
  tracing.cpp utils.cpp read_apk.cpp read_elf.cpp read_symbol_map.cpp record.cpp perf_regs.cpp
  kallsyms.cpp environment.cpp OfflineUnwinder.cpp MapRecordReader.cpp RegEx.cpp)
list(TRANSFORM SIMPLEPERF_SOURCES PREPEND "${SIMPLEPERF}/")
add_library(simpleperf_core STATIC ${SIMPLEPERF_SOURCES}
  "${ROOT}/compat/simpleperf_dex_stubs.cpp"
  "${GENERATED}/event_table.cpp"
  "${GENERATED}/system/extras/simpleperf/record_file.pb.cc")
target_compile_definitions(simpleperf_core PUBLIC
  NO_LIBDEXFILE_SUPPORT USE_BIONIC_UAPI_HEADERS)
target_include_directories(simpleperf_core PUBLIC
  "${SIMPLEPERF}"
  "${ROOT}/compat/include"
  "${GENERATED}"
  "${ROOT}/sources/system-core/libcutils/include"
  "${ROOT}/sources/system-core/libutils/include"
  "${ROOT}/sources/system-core/libutils/binder/include"
  "${ROOT}/sources/bionic/libc/kernel"
  "${ROOT}/sources/rustc-demangle-capi/include"
  "${ROOT}/sources/llvm-project/llvm/include"
  "${ROOT}/build/llvm-linux-aarch64/include"
  "${DEPS}/include")
target_link_libraries(simpleperf_core PUBLIC android_base procinfo ziparchive unwindstack
  lzma_sdk protobuf_lite "${ROOT}/out/simpleperf-linux-aarch64/libsimpleperf_readelf.a")

add_library(simpleperf_report SHARED "${SIMPLEPERF}/report_lib_interface.cpp")
set_target_properties(simpleperf_report PROPERTIES OUTPUT_NAME simpleperf_report
  PREFIX "lib" LINK_FLAGS "-Wl,--gc-sections -Wl,--exclude-libs,ALL")
target_link_options(simpleperf_report PRIVATE -static-libstdc++ -static-libgcc)
target_link_libraries(simpleperf_report PRIVATE simpleperf_core dl m rt pthread)

add_executable(rust_demangle_smoke
  "${ROOT}/tests/rust_demangle_smoke.cpp"
  "${ROOT}/compat/rustc_demangle.cpp")
target_include_directories(rust_demangle_smoke PRIVATE
  "${ROOT}/sources/rustc-demangle-capi/include"
  "${ROOT}/sources/llvm-project/llvm/include")
target_link_options(rust_demangle_smoke PRIVATE -static-libstdc++ -static-libgcc)
target_link_libraries(rust_demangle_smoke PRIVATE
  "${ROOT}/out/simpleperf-linux-aarch64/libsimpleperf_readelf.a")
