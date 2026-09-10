# This file controls Flutter-level build steps. It should not be edited.
cmake_minimum_required(VERSION 3.14)

set(EPHEMERAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ephemeral")

# Configuration provided via flutter tool.
include(${EPHEMERAL_DIR}/generated_config.cmake)

# TODO: Move the rest of this into files in ephemeral. See
# https://github.com/flutter/flutter/issues/57146.
set(WRAPPER_ROOT "${EPHEMERAL_DIR}/cpp_client_wrapper")

# Set fallback configurations for older versions of the flutter tool.
if (NOT DEFINED FLUTTER_TARGET_PLATFORM)
  set(FLUTTER_TARGET_PLATFORM "windows-x64")
endif()

# === Flutter Library ===
set(FLUTTER_LIBRARY "${EPHEMERAL_DIR}/${FLUTTER_TARGET_PLATFORM}/flutter_windows.dll")

# Published to parent scope for install step.
set(FLUTTER_LIBRARY ${FLUTTER_LIBRARY} PARENT_SCOPE)
set(FLUTTER_ICU_DATA_FILE "${EPHEMERAL_DIR}/icudtl.dat" PARENT_SCOPE)
set(PROJECT_BUILD_DIR "${PROJECT_DIR}/build/" PARENT_SCOPE)
set(AOT_LIBRARY "${PROJECT_DIR}/build/windows/${FLUTTER_TARGET_PLATFORM}/app.so" PARENT_SCOPE)

list(APPEND FLUTTER_LIBRARY_HEADERS
  "flutter_export.h"
  "flutter_windows.h"
  "flutter_messenger.h"
  "flutter_plugin_registrar.h"
  "flutter_texture_registrar.h"
)
set(FLUTTER_LIBRARY_HEADERS ${FLUTTER_LIBRARY_HEADERS} PARENT_SCOPE)

add_library(flutter INTERFACE)
target_include_directories(flutter INTERFACE
  "${EPHEMERAL_DIR}"
)
target_link_libraries(flutter INTERFACE "${FLUTTER_LIBRARY}")

# === Wrapper ===
list(APPEND CPP_WRAPPER_SOURCES_CORE
  "core_implementations.cc"
  "standard_codec.cc"
  "plugin_registrar.cc"
  "engine_method_result.cc"
)
list(APPEND CPP_WRAPPER_SOURCES_PLUGIN
  "dart_plugin_registrant.cc"
  "plugin_registrar_windows.cc"
)
list(APPEND CPP_WRAPPER_SOURCES_APP
  "flutter_engine.cc"
  "flutter_view_controller.cc"
)
set(CPP_WRAPPER_SOURCES
  "${CPP_WRAPPER_SOURCES_CORE}"
  "${CPP_WRAPPER_SOURCES_PLUGIN}"
  "${CPP_WRAPPER_SOURCES_APP}"
)
foreach(SOURCE ${CPP_WRAPPER_SOURCES})
  list(APPEND CPP_WRAPPER_SOURCES_ABS "${WRAPPER_ROOT}/${SOURCE}")
endforeach(SOURCE)

add_library(flutter_wrapper_plugin STATIC
  ${CPP_WRAPPER_SOURCES_PLUGIN}
)
apply_standard_settings(flutter_wrapper_plugin)
set_target_properties(flutter_wrapper_plugin PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_link_libraries(flutter_wrapper_plugin PUBLIC flutter)
target_include_directories(flutter_wrapper_plugin PUBLIC
  "${WRAPPER_ROOT}/include"
)
add_library(flutter_wrapper_app STATIC
  ${CPP_WRAPPER_SOURCES_APP}
)
apply_standard_settings(flutter_wrapper_app)
set_target_properties(flutter_wrapper_app PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_link_libraries(flutter_wrapper_app PUBLIC flutter)
target_include_directories(flutter_wrapper_app PUBLIC
  "${WRAPPER_ROOT}/include"
)

# === Flutter tool backend ===
# _flutter_build_dll is now deprecated, but leaving it to not break the build for
# existing projects. See https://github.com/flutter/flutter/issues/121782.
add_custom_command(
  OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/_flutter_build_dll
  COMMAND ${CMAKE_COMMAND} -E echo "Dummy file to force re-build"
)
add_custom_target(flutter_assemble DEPENDS
  "${FLUTTER_LIBRARY}"
  ${CPP_WRAPPER_SOURCES_APP}
  ${CMAKE_CURRENT_BINARY_DIR}/_flutter_build_dll
)
