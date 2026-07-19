cmake_minimum_required(VERSION 3.10)
project("rpcsx-ui-jni")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_POSITION_INDEPENDENT_CODE on)
option(RPCSX_BUILD_BUNDLED_CORE "Build the vendored RPCSX Android core into the APK" OFF)
option(RPCSX_THOR_WAIT_PROFILER "Instrument Android busy-wait sites for Thor diagnostics" OFF)
option(RPCSX_THOR_BUSY_WAIT_EXPERIMENT "Build the failed Android ARM64 busy-wait batching experiment" OFF)
option(RPCSX_THOR_SPU_REDUCED_LOOP_DIAGNOSTICS "Build Android SPU reduced-loop detect-only diagnostics" OFF)
option(RPCSX_THOR_RSX_AUDITOR "Instrument Android Vulkan work for Thor diagnostics" OFF)
option(RPCSX_THOR_RSX_EXPERIMENTS "Build experimental Android RSX fence, locality, and resolve behavior" OFF)
option(RPCSX_THOR_SYSCALL_STATS "Instrument Android PPU syscalls for Thor diagnostics" OFF)
option(RPCSX_THOR_SPURS_PROBE "Instrument Android SPURS waits for Thor diagnostics" OFF)
option(RPCSX_THOR_DRAW_STREAM_PROBE "Instrument Eternal Sonata draw-stream handoff diagnostics" OFF)
option(RPCSX_THOR_SEMA_SUPERPATH "Build the Eternal Sonata semaphore experiment on Android" OFF)
option(RPCSX_THOR_ES_SPU_EXPERIMENTS "Build Eternal Sonata SPU experiments on Android" OFF)
option(RPCSX_THOR_ES_PPU_EXPERIMENTS "Build Eternal Sonata PPU and PRX diagnostics on Android" OFF)
set(RPCSX_ANDROID_ARM_ARCH "armv8.2-a" CACHE STRING "AArch64 ISA baseline for Android native code")
set(RPCSX_ANDROID_ARM_TUNE "cortex-a715" CACHE STRING "AArch64 scheduling model for Android native code")

if (RPCSX_THOR_WAIT_PROFILER)
	add_compile_definitions(RPCSX_THOR_WAIT_PROFILER=1)
endif()

if (RPCSX_THOR_BUSY_WAIT_EXPERIMENT)
	add_compile_definitions(RPCSX_THOR_BUSY_WAIT_EXPERIMENT=1)
endif()

if (RPCSX_THOR_SPU_REDUCED_LOOP_DIAGNOSTICS)
	add_compile_definitions(RPCSX_THOR_SPU_REDUCED_LOOP_DIAGNOSTICS=1)
endif()

if (RPCSX_THOR_RSX_AUDITOR)
	add_compile_definitions(RPCSX_THOR_RSX_AUDITOR=1)
endif()

if (RPCSX_THOR_RSX_EXPERIMENTS)
	add_compile_definitions(RPCSX_THOR_RSX_EXPERIMENTS=1)
endif()

if (RPCSX_THOR_SYSCALL_STATS)
	add_compile_definitions(RPCSX_THOR_SYSCALL_STATS=1)
endif()

if (RPCSX_THOR_SPURS_PROBE)
	add_compile_definitions(RPCSX_THOR_SPURS_PROBE=1)
endif()

if (RPCSX_THOR_DRAW_STREAM_PROBE)
	add_compile_definitions(RPCSX_THOR_DRAW_STREAM_PROBE=1)
endif()

if (RPCSX_THOR_SEMA_SUPERPATH)
	add_compile_definitions(RPCSX_THOR_SEMA_SUPERPATH=1)
endif()

if (RPCSX_THOR_ES_SPU_EXPERIMENTS)
	add_compile_definitions(RPCSX_THOR_ES_SPU_EXPERIMENTS=1)
endif()

if (RPCSX_THOR_ES_PPU_EXPERIMENTS)
	add_compile_definitions(RPCSX_THOR_ES_PPU_EXPERIMENTS=1)
endif()

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
