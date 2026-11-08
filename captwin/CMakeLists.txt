cmake_minimum_required(VERSION 3.21)
project(captwin VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(LIBCAPT_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LIBCAPT_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LIBCAPT_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../libcapt" libcapt_build)

set(LIBUSB_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/libusb-src")
if(NOT EXISTS "${LIBUSB_SRC_DIR}/libusb/core.c")
    message(FATAL_ERROR "Missing libusb at ${LIBUSB_SRC_DIR}. Run: py -3 scripts/fetch_libusb.py")
endif()
add_subdirectory(third_party/libusb)

set(CAPTBACKEND_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../captppd/captbackend")

add_library(captusb STATIC
    "${CAPTBACKEND_DIR}/UsbBackend/UsbBackend.cpp"
    "${CAPTBACKEND_DIR}/UsbBackend/UsbPrinter.cpp"
    "${CAPTBACKEND_DIR}/UsbBackend/UsbStreambuf.cpp"
    "${CAPTBACKEND_DIR}/Core/PrinterInfo.cpp"
    "${CAPTBACKEND_DIR}/Core/Log.cpp"
)
target_include_directories(captusb PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include" "${CAPTBACKEND_DIR}")
target_include_directories(captusb SYSTEM PUBLIC "${LIBUSB_SRC_DIR}/libusb")
target_compile_definitions(captusb PUBLIC CAPTBACKEND_NAME=\"captwin\")
target_link_libraries(captusb PUBLIC libcapt::libcapt usb-1.0)
if(WIN32)
    target_link_libraries(captusb PUBLIC setupapi)
endif()

add_executable(captwin
    src/main.cpp
    src/print_job.cpp
    src/print_server.cpp
    src/ghostscript_util.cpp
)
target_link_libraries(captwin PRIVATE captusb ws2_32)

if(MINGW)
    target_link_options(captwin PRIVATE -static-libgcc -static-libstdc++)
endif()
