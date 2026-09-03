set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

set(CMAKE_C_COMPILER clang)
set(CMAKE_CXX_COMPILER clang++)
set(CMAKE_ASM_COMPILER clang)
set(CMAKE_C_COMPILER_TARGET aarch64-linux-gnu)
set(CMAKE_CXX_COMPILER_TARGET aarch64-linux-gnu)
set(CMAKE_ASM_COMPILER_TARGET aarch64-linux-gnu)
set(CMAKE_C_COMPILER_EXTERNAL_TOOLCHAIN /usr)
set(CMAKE_CXX_COMPILER_EXTERNAL_TOOLCHAIN /usr)
set(CMAKE_AR aarch64-linux-gnu-ar)
set(CMAKE_NM aarch64-linux-gnu-nm)
set(CMAKE_OBJCOPY aarch64-linux-gnu-objcopy)
set(CMAKE_OBJDUMP aarch64-linux-gnu-objdump)
set(CMAKE_RANLIB aarch64-linux-gnu-ranlib)
set(CMAKE_READELF aarch64-linux-gnu-readelf)
set(CMAKE_STRIP aarch64-linux-gnu-strip)

# Debian/Ubuntu cross GCC uses /usr/aarch64-linux-gnu as its multiarch root,
# but reports / as its sysroot. Setting CMAKE_SYSROOT here would break the
# absolute paths used by the glibc linker scripts, so only constrain CMake's
# package/header/library search paths.
set(CMAKE_FIND_ROOT_PATH /usr/aarch64-linux-gnu)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

set(CMAKE_CROSSCOMPILING_EMULATOR
    /usr/bin/qemu-aarch64;-L;/usr/aarch64-linux-gnu)
