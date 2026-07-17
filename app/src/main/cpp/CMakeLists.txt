cmake_minimum_required(VERSION 3.10)
project("rpcsx-ui-jni")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_POSITION_INDEPENDENT_CODE on)
option(RPCSX_BUILD_BUNDLED_CORE "Build the vendored RPCSX Android core into the APK" OFF)
set(RPCSX_ANDROID_ARM_ARCH "armv8.2-a" CACHE STRING "AArch64 ISA baseline for Android native code")
set(RPCSX_ANDROID_ARM_TUNE "cortex-a715" CACHE STRING "AArch64 scheduling model for Android native code")

if (CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
	include(CheckCXXCompilerFlag)

	if (RPCSX_ANDROID_ARM_ARCH)
		check_cxx_compiler_flag("-march=${RPCSX_ANDROID_ARM_ARCH}" RPCSX_ANDROID_ARM_ARCH_SUPPORTED)
		if (NOT RPCSX_ANDROID_ARM_ARCH_SUPPORTED)
			message(FATAL_ERROR "Unsupported RPCSX Android ARM architecture: ${RPCSX_ANDROID_ARM_ARCH}")
		endif()
		add_compile_options("-march=${RPCSX_ANDROID_ARM_ARCH}")
	endif()

	if (RPCSX_ANDROID_ARM_TUNE)
		check_cxx_compiler_flag("-mtune=${RPCSX_ANDROID_ARM_TUNE}" RPCSX_ANDROID_ARM_TUNE_SUPPORTED)
		if (NOT RPCSX_ANDROID_ARM_TUNE_SUPPORTED)
			message(FATAL_ERROR "Unsupported RPCSX Android ARM tuning model: ${RPCSX_ANDROID_ARM_TUNE}")
		endif()
		add_compile_options("-mtune=${RPCSX_ANDROID_ARM_TUNE}")
	endif()

	message(STATUS "RPCSX Android ARM tuning: -march=${RPCSX_ANDROID_ARM_ARCH} -mtune=${RPCSX_ANDROID_ARM_TUNE}")
endif()

if (CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
	add_subdirectory(libadrenotools)
else()
	add_library(adrenotools INTERFACE)
endif()

add_library(${CMAKE_PROJECT_NAME} SHARED native-lib.cpp)

target_link_libraries(${CMAKE_PROJECT_NAME}
    android
    log
    adrenotools
)

if (RPCSX_BUILD_BUNDLED_CORE)
	add_subdirectory(rpcsx/android rpcsx-bundled-core)
endif()
