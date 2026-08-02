cmake_minimum_required(VERSION 3.16)
project(sylph_luau)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Fetch Luau source at configure time ──────────────────────────
# Pinned to a specific release tag for build reproducibility — bump
# this manually when you want to pick up newer Luau language features.
include(FetchContent)

# Luau's CMakeLists.txt builds CLI tools (Repl, Analyze, Compile, Reduce...)
# by default, which pull in extra dependencies (e.g. isocline for the REPL)
# that we don't need and that can fail to build in restricted CI
# environments. We only need the VM + Compiler libraries.
option(LUAU_BUILD_CLI "" OFF)
option(LUAU_BUILD_TESTS "" OFF)

# CRITICAL: Luau builds as a pure C++ library by default — LUA_API/LUACODE_API
# expand to ordinary (mangled) C++ linkage unless this is set. Our bridge
# (luau_bridge.cpp) includes lua.h/lualib.h/luacode.h wrapped in extern "C",
# which tells the compiler to treat those declarations as C linkage. If Luau
# itself is NOT built with LUAU_EXTERN_C, the *definitions* inside Luau.VM end
# up mangled (e.g. _Z13lua_pushstringP9lua_StatePKc) while our call site looks
# for the plain C symbol (lua_pushstring) — a mismatch, not a missing-symbol/
# strip problem. --whole-archive cannot fix this because the object files ARE
# in the archive; the *names* just don't match. Setting this ON makes Luau.VM
# export lua_pushstring, lua_error, lua_resume, etc. as real C symbols, which
# aligns with how the bridge includes the headers.
option(LUAU_EXTERN_C "" ON)

FetchContent_Declare(
  luau
  GIT_REPOSITORY https://github.com/luau-lang/luau.git
  GIT_TAG        0.727
  GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(luau)

# ── Generate the embedded GUI bootstrap header ────────────────────
# sylph_gui_bootstrap.lua is the single source of truth for the mock
# Roblox Instance/GUI API. We turn it into a C++ raw-string header at
# configure time so luau_bridge.cpp can #include it directly, without
# needing Android asset-manager plumbing to read a .lua file off disk
# at runtime. See sylph_gui_bootstrap_embedded.h.in for the template.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/sylph_gui_bootstrap.lua" SYLPH_GUI_BOOTSTRAP_LUA_CONTENT)
configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/sylph_gui_bootstrap_embedded.h.in"
  "${CMAKE_CURRENT_BINARY_DIR}/generated/sylph_gui_bootstrap_embedded.h"
  @ONLY
)

# ── Our thin extern "C" wrapper ───────────────────────────────────
add_library(sylph_luau SHARED
  luau_bridge.cpp
)

target_include_directories(sylph_luau PRIVATE
  "${CMAKE_CURRENT_BINARY_DIR}/generated"
  ${luau_SOURCE_DIR}/VM/include
  ${luau_SOURCE_DIR}/Compiler/include
  ${luau_SOURCE_DIR}/Ast/include
  ${luau_SOURCE_DIR}/Common/include
)

# Luau ships its libraries as static (.a) archives by default. When those
# get linked into our SHARED library, symbols that aren't referenced from
# outside the archive at link time can be silently dropped by the linker
# unless we force the whole archive in. This is the most common cause of
# "undefined symbol: lua_xxx" even though Luau.VM built successfully.
if(ANDROID OR UNIX)
  target_link_libraries(sylph_luau PRIVATE
    -Wl,--whole-archive
    Luau.VM
    Luau.Compiler
    Luau.Ast
    -Wl,--no-whole-archive
  )
else()
  target_link_libraries(sylph_luau PRIVATE
    Luau.VM
    Luau.Compiler
    Luau.Ast
  )
endif()

# Android NDK sets this; on other platforms this is a no-op.
if(ANDROID)
  target_link_libraries(sylph_luau PRIVATE log)
endif()

set_target_properties(sylph_luau PROPERTIES
  OUTPUT_NAME "sylph_luau"
)
