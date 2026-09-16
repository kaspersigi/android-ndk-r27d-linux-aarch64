# The host NDK embeds ART's external DEX API statically, as simpleperf_ndk does.
# Keep its parser and verifier from the matching Simpleperf repo.prop revision.
set(ART "${ROOT}/sources/art")
set(DEX_SOURCES
  compact_dex_file.cc compact_offset_table.cc
  descriptors_names.cc dex_file.cc dex_file_exception_helpers.cc dex_file_layout.cc
  dex_file_loader.cc dex_file_tracking_registrar.cc dex_file_verifier.cc
  dex_instruction.cc modifiers.cc primitive.cc signature.cc standard_dex_file.cc
  type_lookup_table.cc utf.cc)
list(TRANSFORM DEX_SOURCES PREPEND "${ART}/libdexfile/dex/")
# Only libartbase facilities used by libdexfile are needed; no ART runtime.
set(ART_BASE_SOURCES
  allocator.cc enums.cc file_magic.cc globals_unix.cc hex_dump.cc
  logging.cc mem_map.cc mem_map_unix.cc os_linux.cc unix_file/fd_file.cc
  utils.cc zip_archive.cc)
list(TRANSFORM ART_BASE_SOURCES PREPEND "${ART}/libartbase/base/")
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(DEX_ENUM_SOURCES)
foreach(header dex_file dex_file_layout dex_instruction dex_instruction_utils invoke_type)
  set(output "${GENERATED}/dex-${header}-operator.cc")
  execute_process(COMMAND "${Python3_EXECUTABLE}" "${ART}/tools/generate_operator_out.py"
    "${ART}/libdexfile" "${ART}/libdexfile/dex/${header}.h"
    OUTPUT_FILE "${output}" RESULT_VARIABLE generate_result)
  if(NOT generate_result EQUAL 0)
    message(FATAL_ERROR "ART enum generation failed for ${header}: ${generate_result}")
  endif()
  list(APPEND DEX_ENUM_SOURCES "${output}")
endforeach()
add_library(dexfile STATIC ${DEX_SOURCES} ${ART_BASE_SOURCES} ${DEX_ENUM_SOURCES}
  "${ART}/libartpalette/system/palette_fake.cc"
  "${ART}/libdexfile/external/dex_file_ext.cc"
  "${ART}/libdexfile/external/dex_file_supp.cc")
# This ART revision still uses allocator members removed in C++20.
set_target_properties(dexfile PROPERTIES CXX_STANDARD 17)
target_compile_definitions(dexfile PRIVATE STATIC_LIB ART_STATIC_LIBARTBASE
  ART_BASE_ADDRESS=0x60000000)
# Clang nullability annotations are source metadata, not part of the C ABI.
if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
  target_compile_definitions(dexfile PUBLIC _Nonnull= _Nullable= _Null_unspecified=)
endif()
target_include_directories(dexfile PUBLIC "${ART}/libdexfile/external/include"
  PRIVATE "${ART}/libdexfile" "${ART}/libartbase" "${ART}/libartpalette/include"
  "${ROOT}/sources/libnativehelper/include_jni")
target_link_libraries(dexfile PUBLIC android_base ziparchive)
