cmake_minimum_required(VERSION 3.21)

set(LIBUSB_SRC "${LIBUSB_SRC_DIR}")
if(NOT EXISTS "${LIBUSB_SRC}/libusb/core.c")
    message(FATAL_ERROR "libusb sources missing at ${LIBUSB_SRC}")
endif()

add_library(usb-1.0 STATIC
    "${LIBUSB_SRC}/libusb/core.c"
    "${LIBUSB_SRC}/libusb/descriptor.c"
    "${LIBUSB_SRC}/libusb/hotplug.c"
    "${LIBUSB_SRC}/libusb/io.c"
    "${LIBUSB_SRC}/libusb/strerror.c"
    "${LIBUSB_SRC}/libusb/sync.c"
    "${LIBUSB_SRC}/libusb/os/events_windows.c"
    "${LIBUSB_SRC}/libusb/os/threads_windows.c"
    "${LIBUSB_SRC}/libusb/os/windows_common.c"
    "${LIBUSB_SRC}/libusb/os/windows_usbdk.c"
    "${LIBUSB_SRC}/libusb/os/windows_winusb.c"
)

target_include_directories(usb-1.0 PUBLIC "${LIBUSB_SRC}/libusb")
target_compile_definitions(usb-1.0 PRIVATE LIBUSB_STATIC)
target_include_directories(usb-1.0 PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(usb-1.0 PUBLIC setupapi ole32)
