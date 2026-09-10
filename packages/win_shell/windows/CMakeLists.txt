cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "win_shell")
project(${PROJECT_NAME} LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(${PROJECT_NAME} SHARED
  "src/win_shell.cpp"
)

# DART_SHARED_LIB is defined by convention for every Dart FFI plugin.
target_compile_definitions(${PROJECT_NAME} PUBLIC DART_SHARED_LIB)

# _WIN32_WINNT=0x0601 == Windows 7. Pinning it guarantees that we cannot
# accidentally call an API that does not exist on the oldest OS we support.
target_compile_definitions(${PROJECT_NAME} PRIVATE
  WIN32
  _WINDOWS
  WIN32_LEAN_AND_MEAN
  NOMINMAX
  UNICODE
  _UNICODE
  _CRT_SECURE_NO_WARNINGS
  _WIN32_WINNT=0x0601
  NTDDI_VERSION=0x06010000
)

target_include_directories(${PROJECT_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")

target_link_libraries(${PROJECT_NAME} PRIVATE
  comctl32
  wininet
  shell32
  shlwapi
  ole32
  advapi32
  user32
  gdi32
  kernel32
)

if(MSVC)
  # The source contains UTF-8 (Persian) comments.
  target_compile_options(${PROJECT_NAME} PRIVATE /utf-8 /W3)
endif()

set_target_properties(${PROJECT_NAME} PROPERTIES LINKER_LANGUAGE CXX)
