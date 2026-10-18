cmake_minimum_required(VERSION 3.16)
project(cpp-signer LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

set(SOURCES
    src/zsign_bridge.cpp
)

add_library(zsign_static STATIC ${SOURCES})

target_include_directories(zsign_static PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

# Compilation flags suited for embedded Apple tvOS runtime
if(APPLE)
    target_compile_options(zsign_static PRIVATE -fembed-bitcode-marker -fPIC)
endif()

