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
option(RPCSX_THOR_ADPF_RSX_HINT "Build the experimental Android RSX performance-hint session" OFF)
option(RPCSX_THOR_THERMAL_HEADROOM_PROBE "Build the diagnostic Android PPU thermal-headroom probe" OFF)
# Armv8.4-A is the lowest baseline that architecturally guarantees FEAT_LSE2,
# which is what makes an aligned 16-byte LDP/STP single-copy atomic. Thor's
# cores (Cortex-X3/A715/A510) are Armv9.0, so this is well within the silicon.
#
# Deliberately not armv9-a: Armv9 mandates SVE2, and this device's HWCAP does
# not advertise SVE at all. See the JIT's sanitize_android_arm64_llvm_cpu, which
# exists to keep LLVM away from SVE for the same reason.
set(RPCSX_ANDROID_ARM_ARCH "armv8.4-a" CACHE STRING "AArch64 ISA baseline for Android native code")
set(RPCSX_ANDROID_ARM_TUNE "cortex-a715" CACHE STRING "AArch64 scheduling model for Android native code")

# There is no compiler-predefined macro for FEAT_LSE2, and the __ARM_ARCH_8_4__
# style probe in rx/types.hpp never fires on clang/AArch64, so the 16-byte
# atomic fast paths in util/atomic.hpp were unreachable at every -march. Without
# them, load/store/release on atomic_t<u128> all fall back to an LDAXP/STLXP
# retry loop: a pure read takes the cache line exclusive and invalidates every
# other core's copy, which is the worst possible behaviour for vm::g_reservations.
# Define it from the build, where the ISA baseline is actually known.
option(RPCSX_ANDROID_ARM_LSE2 "Assume FEAT_LSE2 (requires an Armv8.4-A or newer baseline)" ON)

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

if (RPCSX_THOR_ADPF_RSX_HINT)
	add_compile_definitions(RPCSX_THOR_ADPF_RSX_HINT=1)
endif()

if (RPCSX_THOR_THERMAL_HEADROOM_PROBE)
	add_compile_definitions(RPCSX_THOR_THERMAL_HEADROOM_PROBE=1)
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

	if (RPCSX_ANDROID_ARM_LSE2)
		# Refuse to assume LSE2 on a baseline that does not guarantee it. An
		# aligned LDP is only single-copy atomic with FEAT_LSE2; below Armv8.4
		# this would silently turn the 16-byte atomics into a data race rather
		# than a slow path, which is far worse than the LDAXP/STLXP loop.
		if (NOT RPCSX_ANDROID_ARM_ARCH MATCHES "^armv(8\\.[4-9]|9)")
			message(FATAL_ERROR
				"RPCSX_ANDROID_ARM_LSE2 requires an Armv8.4-A or newer baseline, got '${RPCSX_ANDROID_ARM_ARCH}'. "
				"Raise RPCSX_ANDROID_ARM_ARCH or set RPCSX_ANDROID_ARM_LSE2=OFF.")
		endif()
		add_compile_definitions(ARM_FEATURE_LSE2=1)
	endif()

	message(STATUS "RPCSX Android ARM tuning: -march=${RPCSX_ANDROID_ARM_ARCH} -mtune=${RPCSX_ANDROID_ARM_TUNE} lse2=${RPCSX_ANDROID_ARM_LSE2}")
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

if (CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
    # For linkernsbypass_load_status(), used to report why a custom GPU driver
    # failed to load instead of leaving it as an unexplained null.
    target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE libadrenotools/lib/linkernsbypass)
endif()

if (RPCSX_BUILD_BUNDLED_CORE)
	add_subdirectory(rpcsx/android rpcsx-bundled-core)
endif()
