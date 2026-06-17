cmake_minimum_required(VERSION 3.10)

project(go2_sport_helper LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(UNITREE_SDK2_ROOT
    "/home/unitree/unitree_sdk/src/04Aug2025_unitree_sdk2"
    CACHE PATH "Unitree SDK2 C++ root")

set(UNITREE_SDK2_INCLUDE_DIR "${UNITREE_SDK2_ROOT}/include")
set(UNITREE_SDK2_THIRDPARTY_INCLUDE_DIR "${UNITREE_SDK2_ROOT}/thirdparty/include")
set(UNITREE_SDK2_DDSCXX_INCLUDE_DIR "${UNITREE_SDK2_ROOT}/thirdparty/include/ddscxx")

set(UNITREE_SDK2_LIBRARY_DIR "${UNITREE_SDK2_ROOT}/lib/aarch64")
set(UNITREE_SDK2_THIRDPARTY_LIBRARY_DIR "${UNITREE_SDK2_ROOT}/thirdparty/lib/aarch64")
set(UNITREE_SDK2_STATIC_LIBRARY "${UNITREE_SDK2_LIBRARY_DIR}/libunitree_sdk2.a")

link_directories(
    "${UNITREE_SDK2_LIBRARY_DIR}"
    "${UNITREE_SDK2_THIRDPARTY_LIBRARY_DIR}"
)

find_library(
    UNITREE_SDK2_LIBRARY
    NAMES unitree_sdk2
    PATHS
        "${UNITREE_SDK2_LIBRARY_DIR}"
        "${UNITREE_SDK2_ROOT}/lib"
        "${UNITREE_SDK2_ROOT}/build/lib"
        "${UNITREE_SDK2_ROOT}/lib/${CMAKE_SYSTEM_PROCESSOR}"
    NO_DEFAULT_PATH
)

if(EXISTS "${UNITREE_SDK2_STATIC_LIBRARY}")
    set(UNITREE_SDK2_LINK_LIBRARY "${UNITREE_SDK2_STATIC_LIBRARY}")
elseif(UNITREE_SDK2_LIBRARY)
    set(UNITREE_SDK2_LINK_LIBRARY "${UNITREE_SDK2_LIBRARY}")
else()
    message(WARNING "Unitree SDK2 library was not found by path; trying linker name unitree_sdk2")
    set(UNITREE_SDK2_LINK_LIBRARY unitree_sdk2)
endif()

message(STATUS "Using Unitree SDK2 library: ${UNITREE_SDK2_LINK_LIBRARY}")

add_executable(go2_sport_helper go2_sport_helper.cpp)

target_include_directories(
    go2_sport_helper
    PRIVATE
        "${UNITREE_SDK2_INCLUDE_DIR}"
        "${UNITREE_SDK2_DDSCXX_INCLUDE_DIR}"
        "${UNITREE_SDK2_THIRDPARTY_INCLUDE_DIR}"
)

target_link_libraries(
    go2_sport_helper
    PRIVATE
        "${UNITREE_SDK2_LINK_LIBRARY}"
        ddscxx
        ddsc
        pthread
        dl
        rt
)

set_target_properties(
    go2_sport_helper
    PROPERTIES
        BUILD_RPATH "${UNITREE_SDK2_LIBRARY_DIR};${UNITREE_SDK2_THIRDPARTY_LIBRARY_DIR}"
        INSTALL_RPATH "${UNITREE_SDK2_LIBRARY_DIR};${UNITREE_SDK2_THIRDPARTY_LIBRARY_DIR}"
)
