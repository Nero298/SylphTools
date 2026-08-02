cmake_minimum_required(VERSION 3.16)
project(sylph_luau)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)

set(LUAU_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_TESTS OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
  luau
  GIT_REPOSITORY https://github.com/luau-lang/luau.git
  GIT_TAG        0.727
  GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(luau)

add_library(sylph_luau SHARED
  luau_bridge.cpp
)

target_include_directories(sylph_luau PRIVATE
  ${luau_SOURCE_DIR}/VM/include
  ${luau_SOURCE_DIR}/Compiler/include
  ${luau_SOURCE_DIR}/Ast/include
  ${luau_SOURCE_DIR}/Common/include
)

target_link_libraries(sylph_luau PRIVATE
  Luau.VM
  Luau.Compiler
  Luau.Ast
)

if(ANDROID)
  target_link_libraries(sylph_luau PRIVATE log)
endif()

set_target_properties(sylph_luau PROPERTIES
  OUTPUT_NAME "sylph_luau"
)
