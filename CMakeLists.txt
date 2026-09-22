cmake_minimum_required(VERSION 3.16)

project(scripter)

if(APPLE)
    enable_language(OBJCXX)
endif()

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/bin")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/bin")

# =============
# == OPTIONS ==
# =============
option(OFS_PROFILE OFF)
option(OFS_AVX OFF)

if(APPLE)
    option(OFS_BUNDLE_MACOS_LIBMPV
        "Bundle libmpv and its non-system dylib dependencies into the macOS app"
        ON)
    option(OFS_MACOS_ADHOC_SIGN
        "Ad-hoc sign the macOS app and bundled dylibs after bundling"
        ON)
endif()

if(WIN32)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    if(OFS_AVX) 
        message("OFS AVX ENABLED")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /arch:AVX")
    endif()
endif()

# ====================
# === DEPENDENCIES ===
# ====================
add_subdirectory("lib/")

# =====================
# ==== BUILD-TOOLS ====
# =====================
add_subdirectory("localization/")

# ==============
# ==== SRC ====
# ==============
add_subdirectory("OFS-lib/")
add_subdirectory("src/")
