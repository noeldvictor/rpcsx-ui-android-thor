#include "Crypto/unpkg.h"
#include "Crypto/unself.h"
#include "Emu/CPU/Backends/AArch64/AArch64Common.h"
#include "Emu/Audio/Cubeb/CubebBackend.h"
#include "Emu/Audio/Null/NullAudioBackend.h"
#include "Emu/Cell/PPUAnalyser.h"
#include "Emu/Cell/SPURecompiler.h"
#include "Emu/IdManager.h"
#include "Emu/thor_playback_probe.h"
#include "Emu/thor_device_stats.h"
#include "Emu/Cell/thor_spu_selfloop_park.h"
#include "Emu/Cell/thor_spu_trap_stop.h"
#include "Emu/RSX/thor_rsx_fifo_park.h"
#include "Emu/system_progress.hpp"
#include "cellos/sys_spu.h"
#include "Emu/Io/KeyboardHandler.h"
#include "Emu/Io/Null/NullKeyboardHandler.h"
#include "Emu/Io/Null/NullMouseHandler.h"
#include "Emu/Io/Null/NullPadHandler.h"
#include "Emu/Io/Null/null_camera_handler.h"
#include "Emu/Io/Null/null_music_handler.h"
#include "Emu/Io/pad_config_types.h"
#include "Emu/RSX/Null/NullGSRender.h"
#include "Emu/RSX/Overlays/overlay_manager.h"
#include "Emu/RSX/Overlays/overlay_save_dialog.h"
#include "Emu/RSX/Overlays/overlay_trophy_notification.h"
#include "Emu/RSX/RSXThread.h"
#include "Emu/RSX/VK/VKGSRender.h"
#include "Emu/localized_string_id.h"
#include "Emu/savestate_utils.hpp"
#include "Emu/system_config.h"
#include "Emu/system_config_types.h"
#include "Emu/system_progress.hpp"
#include "Emu/system_utils.hpp"
#include "Emu/vfs_config.h"
#include "Input/ds3_pad_handler.h"
#include "Input/ds4_pad_handler.h"
#include "Input/dualsense_pad_handler.h"
#include "Input/hid_pad_handler.h"
#include "Input/pad_thread.h"
#include "Input/virtual_pad_handler.h"
#include "Loader/PSF.h"
#include "Loader/PUP.h"
#include "Loader/TAR.h"
#include "cellos/sys_sync.h"
#include "dev/block_dev.hpp"
#include "dev/iso.hpp"
#include "hidapi_libusb.h"
#include "libusb.h"
#include "rpcs3_version.h"
#include "rpcsx/fw/ps3/cellMsgDialog.h"
#include "rpcsx/fw/ps3/cellSysutil.h"
#include "rx/asm.hpp"
#include "rx/debug.hpp"
#include "util/File.h"
#include "util/JIT.h"
#include "util/StrFmt.h"
#include "util/StrUtil.h"
#include "util/Thread.h"
#include "util/console.h"
#include "util/fixed_typemap.hpp"
#include "util/logs.hpp"
#include "util/serialization.hpp"
#include "util/sysinfo.hpp"
#include <Emu/Io/pad_config.h>
#include <Emu/RSX/GSFrameBase.h>
#include <Emu/System.h>
#include <nlohmann/json.hpp>
#include <rpcsx/fw/ps3/cellSaveData.h>
#include <rpcsx/fw/ps3/sceNpTrophy.h>
#include <rx/Version.hpp>

#include <algorithm>
#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <filesystem>
#include <functional>
#include <iterator>
#include <jni.h>
#include <optional>
#include <span>
#include <string>
#include <sys/resource.h>
#include <sys/system_properties.h>
#include <thread>
#include <vector>

#if defined(__ANDROID__) && defined(__aarch64__)
#include <asm/hwcap.h>
#include <sys/auxv.h>
#endif

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wreturn-type-c-linkage"

struct AtExit {
  std::function<void()> cb;
  ~AtExit() { cb(); }
};

static bool g_initialized;
static std::atomic<ANativeWindow *> g_native_window;
static std::atomic<bool> g_thor_fast_forward_enabled{false};
static std::atomic<int> g_thor_fast_forward_previous_clocks_scale{100};
static std::atomic<bool> g_home_menu_exit_game_selected{false};
static std::atomic<bool> g_thor_start_paused_ready{false};
static constexpr int k_thor_fast_forward_clocks_scale = 200;

extern std::string g_android_executable_dir;
extern std::string g_android_config_dir;
extern std::string g_android_cache_dir;

static void append_feature(std::vector<const char *> &features, unsigned long caps,
                           unsigned long flag, const char *name) {
  if ((caps & flag) != 0) {
    features.push_back(name);
  }
}

static std::string join_features(const std::vector<const char *> &features) {
  std::string result;

  for (std::size_t i = 0; i < features.size(); i++) {
    if (i != 0) {
      result += ", ";
    }

    result += features[i];
  }

  return result.empty() ? "none reported" : result;
}

#if defined(__aarch64__)
static std::string arm64_jit_target_attributes() {
  std::vector<const char *> attributes;

  attributes.push_back(utils::has_sha3() ? "+sha3" : "-sha3");
  attributes.push_back(utils::has_dotprod() ? "+dotprod" : "-dotprod");
  attributes.push_back(utils::has_i8mm() ? "+i8mm" : "-i8mm");
  attributes.push_back(utils::has_sve() ? "+sve" : "-sve");
  attributes.push_back(utils::has_sve2() ? "+sve2" : "-sve2");

  return join_features(attributes);
}
#endif

static void append_thor_feature_doctor(std::string &result) {
  const std::string configured_cpu = g_cfg.core.llvm_cpu;
  const char *detected_cpu = fallback_cpu_detection();

  fmt::append(result,
              "Thor Feature Doctor:\nConfigured LLVM CPU: %s\nDetected LLVM "
              "fallback CPU: %s\n",
              configured_cpu.empty() ? "(generic/auto)" : configured_cpu,
              detected_cpu);

#if defined(__aarch64__)
  fmt::append(result, "AArch64 core topology:\n");

  const auto thread_count = std::thread::hardware_concurrency();
  if (thread_count == 0) {
    fmt::append(result, "- unknown\n");
  } else {
    for (u32 cpu = 0; cpu < thread_count; cpu++) {
      const char *name = aarch64::get_cpu_name(static_cast<int>(cpu));
      fmt::append(result, "- CPU%u: %s\n", cpu, name ? name : "unknown");
    }
  }

#if defined(__ANDROID__)
  const unsigned long hwcap = getauxval(AT_HWCAP);
  const unsigned long hwcap2 = getauxval(AT_HWCAP2);
  std::vector<const char *> hwcap_features;
  std::vector<const char *> hwcap2_features;

#ifdef HWCAP_FP
  append_feature(hwcap_features, hwcap, HWCAP_FP, "FP");
#endif
#ifdef HWCAP_ASIMD
  append_feature(hwcap_features, hwcap, HWCAP_ASIMD, "ASIMD/NEON");
#endif
#ifdef HWCAP_AES
  append_feature(hwcap_features, hwcap, HWCAP_AES, "AES");
#endif
#ifdef HWCAP_PMULL
  append_feature(hwcap_features, hwcap, HWCAP_PMULL, "PMULL");
#endif
#ifdef HWCAP_SHA1
  append_feature(hwcap_features, hwcap, HWCAP_SHA1, "SHA1");
#endif
#ifdef HWCAP_SHA2
  append_feature(hwcap_features, hwcap, HWCAP_SHA2, "SHA2");
#endif
#ifdef HWCAP_CRC32
  append_feature(hwcap_features, hwcap, HWCAP_CRC32, "CRC32");
#endif
#ifdef HWCAP_ATOMICS
  append_feature(hwcap_features, hwcap, HWCAP_ATOMICS, "ATOMICS");
#endif
#ifdef HWCAP_FPHP
  append_feature(hwcap_features, hwcap, HWCAP_FPHP, "FPHP");
#endif
#ifdef HWCAP_ASIMDHP
  append_feature(hwcap_features, hwcap, HWCAP_ASIMDHP, "ASIMDHP");
#endif
#ifdef HWCAP_ASIMDRDM
  append_feature(hwcap_features, hwcap, HWCAP_ASIMDRDM, "ASIMDRDM");
#endif
#ifdef HWCAP_ASIMDDP
  append_feature(hwcap_features, hwcap, HWCAP_ASIMDDP, "ASIMDDP/dotprod");
#endif
#ifdef HWCAP_ASIMDFHM
  append_feature(hwcap_features, hwcap, HWCAP_ASIMDFHM, "ASIMDFHM");
#endif
#ifdef HWCAP_SVE
  append_feature(hwcap_features, hwcap, HWCAP_SVE, "SVE");
#endif

#ifdef HWCAP2_DCPODP
  append_feature(hwcap2_features, hwcap2, HWCAP2_DCPODP, "DCPODP");
#endif
#ifdef HWCAP2_SVE2
  append_feature(hwcap2_features, hwcap2, HWCAP2_SVE2, "SVE2");
#endif
#ifdef HWCAP2_SVEI8MM
  append_feature(hwcap2_features, hwcap2, HWCAP2_SVEI8MM, "SVEI8MM");
#endif
#ifdef HWCAP2_SVEBF16
  append_feature(hwcap2_features, hwcap2, HWCAP2_SVEBF16, "SVEBF16");
#endif
#ifdef HWCAP2_I8MM
  append_feature(hwcap2_features, hwcap2, HWCAP2_I8MM, "I8MM");
#endif
#ifdef HWCAP2_BF16
  append_feature(hwcap2_features, hwcap2, HWCAP2_BF16, "BF16");
#endif
#ifdef HWCAP2_RNG
  append_feature(hwcap2_features, hwcap2, HWCAP2_RNG, "RNG");
#endif
#ifdef HWCAP2_BTI
  append_feature(hwcap2_features, hwcap2, HWCAP2_BTI, "BTI");
#endif
#ifdef HWCAP2_MTE
  append_feature(hwcap2_features, hwcap2, HWCAP2_MTE, "MTE");
#endif

  fmt::append(result, "HWCAP: 0x%llx (%s)\n",
              static_cast<unsigned long long>(hwcap),
              join_features(hwcap_features));
  fmt::append(result, "HWCAP2: 0x%llx (%s)\n",
              static_cast<unsigned long long>(hwcap2),
              join_features(hwcap2_features));
  fmt::append(result,
              "Core ARM64 gates: NEON=%s SHA3=%s DOTPROD=%s SVE=%s SVE2=%s\n",
              utils::has_neon() ? "yes" : "no",
              utils::has_sha3() ? "yes" : "no",
              utils::has_dotprod() ? "yes" : "no",
              utils::has_sve() ? "yes" : "no",
              utils::has_sve2() ? "yes" : "no");
  fmt::append(result, "LLVM ARM64 target attrs: %s\n",
              arm64_jit_target_attributes());
  fmt::append(result,
              "Native scheduler: %s PPU=0x%llx SPU=0x%llx RSX=0x%llx\n",
              g_cfg.core.thread_scheduler.get(),
              static_cast<unsigned long long>(
                  thread_ctrl::get_affinity_mask(thread_class::ppu)),
              static_cast<unsigned long long>(
                  thread_ctrl::get_affinity_mask(thread_class::spu)),
              static_cast<unsigned long long>(
                  thread_ctrl::get_affinity_mask(thread_class::rsx)));
  fmt::append(result,
              "SPU reservation busy-wait: %s percentage=%u\n",
              g_cfg.core.spu_reservation_busy_waiting_enabled ? "enabled"
                                                              : "disabled",
              static_cast<u32>(
                  g_cfg.core.spu_reservation_busy_waiting_percentage));
#endif
#else
  fmt::append(result, "AArch64 core topology: unavailable on this build\n");
#endif

  fmt::append(result, "\n");
}

static std::mutex g_virtual_pad_mutex;
static std::shared_ptr<Pad> g_virtual_pad;

std::string g_input_config_override;
cfg_input_configurations g_cfg_input_configs;

LOG_CHANNEL(rpcsx_android, "ANDROID");

static bool android_property_enabled(const char* name, bool fallback) noexcept {
  char value[PROP_VALUE_MAX]{};
  const int length = __system_property_get(name, value);

  if (length <= 0) {
    return fallback;
  }

  switch (value[0]) {
  case '1':
  case 't':
  case 'T':
  case 'y':
  case 'Y':
    return true;
  case '0':
  case 'f':
  case 'F':
  case 'n':
  case 'N':
    return false;
  default:
    return fallback;
  }
}

static int android_property_log_priority(const char* name, int fallback) noexcept {
  char value[PROP_VALUE_MAX]{};
  const int length = __system_property_get(name, value);

  if (length <= 0) {
    return fallback;
  }

  switch (value[0]) {
  case 'V':
  case 'v':
    return ANDROID_LOG_VERBOSE;
  case 'D':
  case 'd':
    return ANDROID_LOG_DEBUG;
  case 'I':
  case 'i':
    return ANDROID_LOG_INFO;
  case 'W':
  case 'w':
    return ANDROID_LOG_WARN;
  case 'E':
  case 'e':
    return ANDROID_LOG_ERROR;
  case 'F':
  case 'f':
  case 'A':
  case 'a':
    return ANDROID_LOG_FATAL;
  case 'S':
  case 's':
    return ANDROID_LOG_SILENT;
  default:
    return fallback;
  }
}

static bool android_logcat_allows(int prio) noexcept {
  constexpr u32 enabled_bit = 1u << 31;
  constexpr u32 priority_mask = 0xff;
  static std::atomic<u32> observed_property_serial{~u32{0}};
  static std::atomic<u32> packed_config{
      enabled_bit | static_cast<u32>(ANDROID_LOG_WARN)};

  // The property-area serial is a cheap change detector. Refreshing from it
  // preserves live logging controls without reading the clock on every log.
  const u32 area_serial = __system_property_area_serial();
  if (observed_property_serial.load(std::memory_order_acquire) != area_serial) {
    const bool enabled =
        android_property_enabled("debug.rpcsx.thor.logcat", true);
    const int min_priority =
        android_property_log_priority("log.tag.RPCS3", ANDROID_LOG_WARN);
    const u32 next_config = (enabled ? enabled_bit : 0u) |
                            (static_cast<u32>(min_priority) & priority_mask);

    packed_config.store(next_config, std::memory_order_relaxed);
    observed_property_serial.store(area_serial, std::memory_order_release);
  }

  const u32 config = packed_config.load(std::memory_order_relaxed);
  if (!(config & enabled_bit)) {
    return false;
  }

  const int threshold = static_cast<int>(config & priority_mask);
  return threshold < ANDROID_LOG_SILENT && prio >= threshold;
}

struct LogListener : logs::listener {
  LogListener() { logs::listener::add(this); }

  void log(u64 stamp, const logs::message &msg, const std::string &prefix,
           const std::string &text) override {
    int prio = 0;
    switch (static_cast<logs::level>(msg)) {
    case logs::level::always:
      prio = ANDROID_LOG_INFO;
      break;
    case logs::level::fatal:
      prio = ANDROID_LOG_FATAL;
      break;
    case logs::level::error:
      prio = ANDROID_LOG_ERROR;
      break;
    case logs::level::todo:
      prio = ANDROID_LOG_WARN;
      break;
    case logs::level::success:
      prio = ANDROID_LOG_INFO;
      break;
    case logs::level::warning:
      prio = ANDROID_LOG_WARN;
      break;
    case logs::level::notice:
      prio = ANDROID_LOG_DEBUG;
      break;
    case logs::level::trace:
      prio = ANDROID_LOG_VERBOSE;
      break;
    }

    if (!android_logcat_allows(prio)) {
      return;
    }

    __android_log_write(prio, "RPCS3", text.c_str());
  }
} static g_androidLogListener;

struct GraphicsFrame : GSFrameBase {
  mutable ANativeWindow *activeNativeWindow = nullptr;
  mutable int width = 0;
  mutable int height = 0;

  ~GraphicsFrame() {
    if (activeNativeWindow != nullptr) {
      ANativeWindow_release(activeNativeWindow);
    }
  }

  ANativeWindow *getNativeWindow() const {
    ANativeWindow *result;

    // Waiting here for a moment at boot is normal: the RSX thread usually starts
    // before the SurfaceView has been laid out. Waiting here FOREVER is not, and
    // it used to be completely silent.
    //
    // SurfaceHolder.Callback::surfaceChanged is a ONE-SHOT. Android delivers it
    // when the surface is created or resized and never repeats it, so a single
    // missed delivery parks this loop for the whole session. The symptom is a
    // black game area at ~0% CPU, with the emulator log stopping dead just after
    // Vulkan device creation and nothing at all to say why - which is what makes
    // it expensive to diagnose rather than merely broken. Rotating the device
    // appears to fix it only because a configuration change forces a fresh
    // surfaceChanged.
    //
    // Say so, rather than hanging quietly. From ARMSX3 614bf8b71.
    u32 waited_ms = 0;

    while ((result = g_native_window.load()) == nullptr) [[unlikely]] {
      if (Emu.IsStopped()) {
        return activeNativeWindow;
      }

      std::this_thread::sleep_for(std::chrono::milliseconds(100));
      waited_ms += 100;

      if (waited_ms % 3000 == 0) {
        rpcsx_android.error("Still waiting for a Surface after %u ms -- the renderer "
                            "cannot start until surfaceChanged reaches native.",
                            waited_ms);
      }
    }

    if (result != activeNativeWindow) [[unlikely]] {
      ANativeWindow_acquire(result);

      if (activeNativeWindow != nullptr) {
        ANativeWindow_release(activeNativeWindow);
      }

      activeNativeWindow = result;

      width = ANativeWindow_getWidth(result);
      height = ANativeWindow_getHeight(result);
    }

    return result;
  }

  void close() override {}
  void reset() override {}
  bool shown() override { return true; }
  void hide() override {}
  void show() override {}
  void toggle_fullscreen() override {}

  void delete_context(draw_context_t ctx) override {}
  draw_context_t make_context() override { return nullptr; }
  void set_current(draw_context_t ctx) override {}
  void flip(draw_context_t ctx, bool skip_frame = false) override {}
  int client_width() override { return width; }
  int client_height() override { return height; }
  f64 client_display_rate() override { return 30.f; }
  bool has_alpha() override {
    return ANativeWindow_getFormat(getNativeWindow()) ==
           WINDOW_FORMAT_RGBA_8888;
  }

  display_handle_t handle() const override { return getNativeWindow(); }

  bool can_consume_frame() const override { return false; }

  void present_frame(std::vector<u8> &data, u32 pitch, u32 width, u32 height,
                     bool is_bgra) const override {}
  void take_screenshot(std::vector<u8> &&sshot_data, u32 sshot_width,
                       u32 sshot_height, bool is_bgra) override {}
};

void jit_announce(uptr, usz, std::string_view);

[[noreturn]] void report_fatal_error(std::string_view _text,
                                     bool is_html = false,
                                     bool include_help_text = true) {
  std::string buf;

  buf = std::string(_text);

  // Check if thread id is in string
  if (_text.find("\nThread id = "sv) == umax && !thread_ctrl::is_main()) {
    // Append thread id if it isn't already, except on main thread
    fmt::append(buf, "\n\nThread id = %u.", thread_ctrl::get_tid());
  }

  if (!g_tls_serialize_name.empty()) {
    fmt::append(buf, "\nSerialized Object: %s", g_tls_serialize_name);
  }

  const system_state state = Emu.GetStatus(false);

  if (state == system_state::stopped) {
    fmt::append(buf, "\nEmulation is stopped");
  } else {
    const std::string &name = Emu.GetTitleAndTitleID();
    fmt::append(buf, "\nTitle: \"%s\" (emulation is %s)",
                name.empty() ? "N/A" : name.data(),
                state == system_state::stopping ? "stopping" : "running");
  }

  fmt::append(buf, "\nBuild: \"%s\"", rpcs3::get_verbose_version());
  fmt::append(buf, "\nDate: \"%s\"", std::chrono::system_clock::now());

  const auto [total_ram, used_ram] = utils::get_memory_usage();
  if (total_ram) {
    fmt::append(buf, "\nRAM Usage: %lluMB/%lluMB (%lluMB free)",
                used_ram / (1024 * 1024), total_ram / (1024 * 1024),
                total_ram > used_ram ? (total_ram - used_ram) / (1024 * 1024)
                                     : 0);
  }

  __android_log_write(ANDROID_LOG_FATAL, "RPCS3", buf.c_str());

  jit_announce(0, 0, "");
  rx::breakpoint();
  std::abort();
  std::terminate();
}

void qt_events_aware_op(int repeat_duration_ms,
                        std::function<bool()> wrapped_op) {
  // Repeat the operation until it reports completion.
  //
  // THIS WAS AN EMPTY STUB, AND THE EMPTY STUB IS WHY LOADING A SAVESTATE CRASHED.
  //
  // Emulator::GracefulShutdown() calls this to WAIT for m_state to reach
  // system_state::stopped before it returns. With no body there was no wait, so
  // boot_last_savestate() went straight on to Emu.BootGame() while the Emulation
  // Join Thread was still inside Kill() tearing the fixed typemap down. Boot then
  // ran Emulator::Init() -> g_fxo->reset() -> clear() on the main thread at the
  // same time as the join thread ran its own g_fxo->reset() -> clear(). Two
  // threads destroying one typemap.
  //
  // MEASURED 2026-08-22, from load state broadcasts on Eternal Sonata (BLUS30161).
  // One race, surfacing in four different places as each earlier one was fixed:
  //
  //   Scudo ERROR: invalid chunk state ... llvm::Module::~Module()
  //   Segfault reading 0x8               ... fixed_typemap.hpp:360, info == nullptr
  //   Segfault reading 0x40              ... fixed_typemap.hpp:398, info == nullptr
  //     and there BOTH the main thread and the Emulation Join Thread faulted
  //     inside clear(), which is what named the race
  //   Segfault reading 00cccccccccccccc  ... the 0xCC trap pattern reset() writes
  //
  // The Qt build loops here while it pumps the event queue. Android has no queue
  // to pump, so this only sleeps for the interval the caller asked for.
  //
  // Bounded, because the callers include the UI thread and an unbounded wait there
  // is an ANR. On timeout it gives up and returns, which is what the stub did on
  // every call, so a timeout can be no worse than the old behaviour.
  if (!wrapped_op) {
    return;
  }

  constexpr auto timeout = std::chrono::seconds(10);
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  const auto interval =
      std::chrono::milliseconds(std::max(1, repeat_duration_ms));

  while (!wrapped_op()) {
    if (std::chrono::steady_clock::now() >= deadline) {
      rpcsx_android.error("qt_events_aware_op: gave up waiting after %d seconds",
                          static_cast<int>(timeout.count()));
      return;
    }

    std::this_thread::sleep_for(interval);
  }
}

static std::string unwrap(JNIEnv *env, jstring string) {
  auto resultBuffer = env->GetStringUTFChars(string, nullptr);
  std::string result(resultBuffer);
  env->ReleaseStringUTFChars(string, resultBuffer);
  return result;
}
static jstring wrap(JNIEnv *env, const std::string &string) {
  return env->NewStringUTF(string.c_str());
}
static jstring wrap(JNIEnv *env, const char *string) {
  return env->NewStringUTF(string);
}

static std::string fix_dir_path(std::string string) {
  if (!string.empty() && !string.ends_with('/')) {
    string += '/';
  }

  return string;
}

enum class FileType {
  Unknown,
  Pup,
  Pkg,
  Edat,
  Rap,
  Iso,
};

static FileType getFileType(const fs::file &file) {
  file.seek(0);
  if (PUPHeader pupHeader; file.read(pupHeader)) {
    if (pupHeader.magic == "SCEUF\0\0\0"_u64) {
      return FileType::Pup;
    }
  }

  file.seek(0);
  if (PKGHeader pkgHeader; file.read(pkgHeader)) {
    if (pkgHeader.pkg_magic == std::bit_cast<le_t<u32>>("\x7FPKG"_u32)) {
      return FileType::Pkg;
    }
  }

  file.seek(0);
  if (NPD_HEADER npdHeader; file.read(npdHeader)) {
    if (npdHeader.magic == "NPD\0"_u32) {
      return FileType::Edat;
    }
  }

  if (file.size() == 16) {
    return FileType::Rap;
  }

  if (iso_dev::open(std::make_unique<file_view_block_dev>(file))) {
    return FileType::Iso;
  }

  return FileType::Unknown;
}

#define MAKE_STRING(id, x) [int(localized_string_id::id)] = {x, U##x}

static std::pair<std::string, std::u32string> g_strings[] = {
    MAKE_STRING(RSX_OVERLAYS_COMPILING_SHADERS, "Compiling shaders"),
    MAKE_STRING(RSX_OVERLAYS_COMPILING_PPU_MODULES, "Compiling PPU Modules"),
    MAKE_STRING(RSX_OVERLAYS_MSG_DIALOG_YES, "Yes"),
    MAKE_STRING(RSX_OVERLAYS_MSG_DIALOG_NO, "No"),
    MAKE_STRING(RSX_OVERLAYS_MSG_DIALOG_CANCEL, "Back"),
    MAKE_STRING(RSX_OVERLAYS_MSG_DIALOG_OK, "OK"),
    MAKE_STRING(RSX_OVERLAYS_SAVE_DIALOG_TITLE, "Save Dialog"),
    MAKE_STRING(RSX_OVERLAYS_SAVE_DIALOG_DELETE, "Delete Save"),
    MAKE_STRING(RSX_OVERLAYS_SAVE_DIALOG_LOAD, "Load Save"),
    MAKE_STRING(RSX_OVERLAYS_SAVE_DIALOG_SAVE, "Save"),
    MAKE_STRING(RSX_OVERLAYS_OSK_DIALOG_ACCEPT, "Enter"),
    MAKE_STRING(RSX_OVERLAYS_OSK_DIALOG_CANCEL, "Back"),
    MAKE_STRING(RSX_OVERLAYS_OSK_DIALOG_SPACE, "Space"),
    MAKE_STRING(RSX_OVERLAYS_OSK_DIALOG_BACKSPACE, "Backspace"),
    MAKE_STRING(RSX_OVERLAYS_OSK_DIALOG_SHIFT, "Shift"),
    MAKE_STRING(RSX_OVERLAYS_OSK_DIALOG_ENTER_TEXT, "[Enter Text]"),
    MAKE_STRING(RSX_OVERLAYS_OSK_DIALOG_ENTER_PASSWORD, "[Enter Password]"),
    MAKE_STRING(RSX_OVERLAYS_MEDIA_DIALOG_TITLE, "Select media"),
    MAKE_STRING(RSX_OVERLAYS_MEDIA_DIALOG_TITLE_PHOTO_IMPORT,
                "Select photo to import"),
    MAKE_STRING(RSX_OVERLAYS_MEDIA_DIALOG_EMPTY, "No media found."),
    MAKE_STRING(RSX_OVERLAYS_LIST_SELECT, "Enter"),
    MAKE_STRING(RSX_OVERLAYS_LIST_CANCEL, "Back"),
    MAKE_STRING(RSX_OVERLAYS_LIST_DENY, "Deny"),
    MAKE_STRING(CELL_OSK_DIALOG_TITLE, "On Screen Keyboard"),
    MAKE_STRING(
        CELL_OSK_DIALOG_BUSY,
        "The Home Menu can't be opened while the On Screen Keyboard is busy!"),
    MAKE_STRING(CELL_SAVEDATA_CB_BROKEN, "Error - Save data corrupted"),
    MAKE_STRING(CELL_SAVEDATA_CB_FAILURE, "Error - Failed to save or load"),
    MAKE_STRING(CELL_SAVEDATA_CB_NO_DATA, "Error - Save data cannot be found"),
    MAKE_STRING(CELL_SAVEDATA_NO_DATA, "There is no saved data."),
    MAKE_STRING(CELL_SAVEDATA_NEW_SAVED_DATA_TITLE, "New Saved Data"),
    MAKE_STRING(CELL_SAVEDATA_NEW_SAVED_DATA_SUB_TITLE,
                "Select to create a new entry"),
    MAKE_STRING(CELL_SAVEDATA_SAVE_CONFIRMATION,
                "Do you want to save this data?"),
    MAKE_STRING(CELL_SAVEDATA_AUTOSAVE, "Saving..."),
    MAKE_STRING(CELL_SAVEDATA_AUTOLOAD, "Loading..."),
    MAKE_STRING(
        CELL_CROSS_CONTROLLER_FW_MSG,
        "If your system software version on the PS Vita system is earlier than "
        "1.80, you must update the system software to the latest version."),
    MAKE_STRING(CELL_NP_RECVMESSAGE_DIALOG_TITLE, "Select Message"),
    MAKE_STRING(CELL_NP_RECVMESSAGE_DIALOG_TITLE_INVITE, "Select Invite"),
    MAKE_STRING(CELL_NP_RECVMESSAGE_DIALOG_TITLE_ADD_FRIEND, "Add Friend"),
    MAKE_STRING(CELL_NP_RECVMESSAGE_DIALOG_FROM, "From:"),
    MAKE_STRING(CELL_NP_RECVMESSAGE_DIALOG_SUBJECT, "Subject:"),
    MAKE_STRING(CELL_NP_SENDMESSAGE_DIALOG_TITLE, "Select Message To Send"),
    MAKE_STRING(CELL_NP_SENDMESSAGE_DIALOG_TITLE_INVITE, "Send Invite"),
    MAKE_STRING(CELL_NP_SENDMESSAGE_DIALOG_TITLE_ADD_FRIEND, "Add Friend"),
    MAKE_STRING(RECORDING_ABORTED, "Recording aborted!"),
    MAKE_STRING(RPCN_NO_ERROR, "RPCN: No Error"),
    MAKE_STRING(RPCN_ERROR_INVALID_INPUT,
                "RPCN: Invalid Input (Wrong Host/Port)"),
    MAKE_STRING(RPCN_ERROR_WOLFSSL, "RPCN Connection Error: WolfSSL Error"),
    MAKE_STRING(RPCN_ERROR_RESOLVE, "RPCN Connection Error: Resolve Error"),
    MAKE_STRING(RPCN_ERROR_CONNECT, "RPCN Connection Error"),
    MAKE_STRING(RPCN_ERROR_LOGIN_ERROR,
                "RPCN Login Error: Identification Error"),
    MAKE_STRING(RPCN_ERROR_ALREADY_LOGGED,
                "RPCN Login Error: User Already Logged In"),
    MAKE_STRING(RPCN_ERROR_INVALID_LOGIN, "RPCN Login Error: Invalid Username"),
    MAKE_STRING(RPCN_ERROR_INVALID_PASSWORD,
                "RPCN Login Error: Invalid Password"),
    MAKE_STRING(RPCN_ERROR_INVALID_TOKEN, "RPCN Login Error: Invalid Token"),
    MAKE_STRING(RPCN_ERROR_INVALID_PROTOCOL_VERSION,
                "RPCN Misc Error: Protocol Version Error (outdated RPCS3?)"),
    MAKE_STRING(RPCN_ERROR_UNKNOWN, "RPCN: Unknown Error"),
    MAKE_STRING(RPCN_SUCCESS_LOGGED_ON, "Successfully logged on RPCN!"),
    MAKE_STRING(HOME_MENU_TITLE, "Home Menu"),
    MAKE_STRING(HOME_MENU_EXIT_GAME, "Exit Game"),
    MAKE_STRING(HOME_MENU_RESUME, "Resume Game"),
    MAKE_STRING(HOME_MENU_CHEATS, "Cheats"),
    MAKE_STRING(HOME_MENU_FAST_FORWARD_2X, "Fast Forward 2x"),
    MAKE_STRING(HOME_MENU_SHOW_FPS, "Show FPS"),
    MAKE_STRING(HOME_MENU_NO_CHEATS, "No cheats for this game"),
    MAKE_STRING(HOME_MENU_CHEAT_RESTART_REQUIRED,
                "Restart the game to apply cheat changes."),
    MAKE_STRING(HOME_MENU_FRIENDS, "Friends"),
    MAKE_STRING(HOME_MENU_FRIENDS_REQUESTS, "Pending Friend Requests"),
    MAKE_STRING(HOME_MENU_FRIENDS_BLOCKED, "Blocked Users"),
    MAKE_STRING(HOME_MENU_FRIENDS_STATUS_ONLINE, "Online"),
    MAKE_STRING(HOME_MENU_FRIENDS_STATUS_OFFLINE, "Offline"),
    MAKE_STRING(HOME_MENU_FRIENDS_STATUS_BLOCKED, "Blocked"),
    MAKE_STRING(HOME_MENU_FRIENDS_REQUEST_SENT, "You sent a friend request"),
    MAKE_STRING(HOME_MENU_FRIENDS_REQUEST_RECEIVED,
                "Sent you a friend request"),
    MAKE_STRING(HOME_MENU_FRIENDS_REJECT_REQUEST, "Reject Request"),
    MAKE_STRING(HOME_MENU_FRIENDS_NEXT_LIST, "Next list"),
    MAKE_STRING(HOME_MENU_RESTART, "Restart Game"),
    MAKE_STRING(HOME_MENU_SETTINGS, "Settings"),
    MAKE_STRING(HOME_MENU_SETTINGS_SAVE, "Save custom configuration?"),
    MAKE_STRING(HOME_MENU_SETTINGS_SAVE_BUTTON, "Save"),
    MAKE_STRING(HOME_MENU_SETTINGS_DISCARD,
                "Discard the current settings' changes?"),
    MAKE_STRING(HOME_MENU_SETTINGS_DISCARD_BUTTON, "Discard"),
    MAKE_STRING(HOME_MENU_SETTINGS_AUDIO, "Audio"),
    MAKE_STRING(HOME_MENU_SETTINGS_AUDIO_MASTER_VOLUME, "Master Volume"),
    MAKE_STRING(HOME_MENU_SETTINGS_AUDIO_BACKEND, "Audio Backend"),
    MAKE_STRING(HOME_MENU_SETTINGS_AUDIO_BUFFERING, "Enable Buffering"),
    MAKE_STRING(HOME_MENU_SETTINGS_AUDIO_BUFFER_DURATION,
                "Desired Audio Buffer Duration"),
    MAKE_STRING(HOME_MENU_SETTINGS_AUDIO_TIME_STRETCHING,
                "Enable Time Stretching"),
    MAKE_STRING(HOME_MENU_SETTINGS_AUDIO_TIME_STRETCHING_THRESHOLD,
                "Time Stretching Threshold"),
    MAKE_STRING(HOME_MENU_SETTINGS_VIDEO, "Video"),
    MAKE_STRING(HOME_MENU_SETTINGS_VIDEO_FRAME_LIMIT, "Frame Limit"),
    MAKE_STRING(HOME_MENU_SETTINGS_VIDEO_ANISOTROPIC_OVERRIDE,
                "Anisotropic Filter Override"),
    MAKE_STRING(HOME_MENU_SETTINGS_VIDEO_OUTPUT_SCALING, "Output Scaling"),
    MAKE_STRING(HOME_MENU_SETTINGS_VIDEO_RCAS_SHARPENING,
                "FidelityFX CAS Sharpening Intensity"),
    MAKE_STRING(HOME_MENU_SETTINGS_VIDEO_STRETCH_TO_DISPLAY,
                "Stretch To Display Area"),
    MAKE_STRING(HOME_MENU_SETTINGS_INPUT, "Input"),
    MAKE_STRING(HOME_MENU_SETTINGS_INPUT_BACKGROUND_INPUT,
                "Background Input Enabled"),
    MAKE_STRING(HOME_MENU_SETTINGS_INPUT_KEEP_PADS_CONNECTED,
                "Keep Pads Connected"),
    MAKE_STRING(HOME_MENU_SETTINGS_INPUT_SHOW_PS_MOVE_CURSOR,
                "Show PS Move Cursor"),
    MAKE_STRING(HOME_MENU_SETTINGS_INPUT_CAMERA_FLIP, "Camera Flip"),
    MAKE_STRING(HOME_MENU_SETTINGS_INPUT_PAD_MODE, "Pad Handler Mode"),
    MAKE_STRING(HOME_MENU_SETTINGS_INPUT_PAD_SLEEP, "Pad Handler Sleep"),
    MAKE_STRING(HOME_MENU_SETTINGS_INPUT_FAKE_MOVE_ROTATION_CONE_H,
                "Fake PS Move Rotation Cone (Horizontal)"),
    MAKE_STRING(HOME_MENU_SETTINGS_INPUT_FAKE_MOVE_ROTATION_CONE_V,
                "Fake PS Move Rotation Cone (Vertical)"),
    MAKE_STRING(HOME_MENU_SETTINGS_ADVANCED, "Advanced"),
    MAKE_STRING(HOME_MENU_SETTINGS_ADVANCED_PREFERRED_SPU_THREADS,
                "Preferred SPU Threads"),
    MAKE_STRING(HOME_MENU_SETTINGS_ADVANCED_MAX_CPU_PREEMPTIONS,
                "Max Power Saving CPU-Preemptions"),
    MAKE_STRING(HOME_MENU_SETTINGS_ADVANCED_ACCURATE_RSX_RESERVATION_ACCESS,
                "Accurate RSX reservation access"),
    MAKE_STRING(HOME_MENU_SETTINGS_ADVANCED_SLEEP_TIMERS_ACCURACY,
                "Sleep Timers Accuracy"),
    MAKE_STRING(HOME_MENU_SETTINGS_ADVANCED_MAX_SPURS_THREADS,
                "Max SPURS Threads"),
    MAKE_STRING(HOME_MENU_SETTINGS_ADVANCED_DRIVER_WAKE_UP_DELAY,
                "Driver Wake-Up Delay"),
    MAKE_STRING(HOME_MENU_SETTINGS_ADVANCED_VBLANK_FREQUENCY,
                "VBlank Frequency"),
    MAKE_STRING(HOME_MENU_SETTINGS_ADVANCED_VBLANK_NTSC, "VBlank NTSC Fixup"),
    MAKE_STRING(HOME_MENU_SETTINGS_OVERLAYS, "Overlays"),
    MAKE_STRING(HOME_MENU_SETTINGS_OVERLAYS_SHOW_TROPHY_POPUPS,
                "Show Trophy Popups"),
    MAKE_STRING(HOME_MENU_SETTINGS_OVERLAYS_SHOW_RPCN_POPUPS,
                "Show RPCN Popups"),
    MAKE_STRING(HOME_MENU_SETTINGS_OVERLAYS_SHOW_SHADER_COMPILATION_HINT,
                "Show Shader Compilation Hint"),
    MAKE_STRING(HOME_MENU_SETTINGS_OVERLAYS_SHOW_PPU_COMPILATION_HINT,
                "Show PPU Compilation Hint"),
    MAKE_STRING(HOME_MENU_SETTINGS_OVERLAYS_SHOW_AUTO_SAVE_LOAD_HINT,
                "Show Autosave/Autoload Hint"),
    MAKE_STRING(HOME_MENU_SETTINGS_OVERLAYS_SHOW_PRESSURE_INTENSITY_TOGGLE_HINT,
                "Show Pressure Intensity Toggle Hint"),
    MAKE_STRING(HOME_MENU_SETTINGS_OVERLAYS_SHOW_ANALOG_LIMITER_TOGGLE_HINT,
                "Show Analog Limiter Toggle Hint"),
    MAKE_STRING(HOME_MENU_SETTINGS_OVERLAYS_SHOW_MOUSE_AND_KB_TOGGLE_HINT,
                "Show Mouse And Keyboard Toggle Hint"),
    MAKE_STRING(HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY, "Performance Overlay"),
    MAKE_STRING(HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY_ENABLE,
                "Enable Performance Overlay"),
    MAKE_STRING(HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY_ENABLE_FRAMERATE_GRAPH,
                "Enable Framerate Graph"),
    MAKE_STRING(HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY_ENABLE_FRAMETIME_GRAPH,
                "Enable Frametime Graph"),
    MAKE_STRING(HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY_DETAIL_LEVEL,
                "Detail level"),
    MAKE_STRING(HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY_FRAMERATE_DETAIL_LEVEL,
                "Framerate Graph Detail Level"),
    MAKE_STRING(HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY_FRAMETIME_DETAIL_LEVEL,
                "Frametime Graph Detail Level"),
    MAKE_STRING(
        HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY_FRAMERATE_DATAPOINT_COUNT,
        "Framerate Datapoints"),
    MAKE_STRING(
        HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY_FRAMETIME_DATAPOINT_COUNT,
        "Frametime Datapoints"),
    MAKE_STRING(HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY_UPDATE_INTERVAL,
                "Metrics Update Interval"),
    MAKE_STRING(HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY_POSITION, "Position"),
    MAKE_STRING(HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY_CENTER_X,
                "Center Horizontally"),
    MAKE_STRING(HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY_CENTER_Y,
                "Center Vertically"),
    MAKE_STRING(HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY_MARGIN_X,
                "Horizontal Margin"),
    MAKE_STRING(HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY_MARGIN_Y,
                "Vertical Margin"),
    MAKE_STRING(HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY_FONT_SIZE, "Font Size"),
    MAKE_STRING(HOME_MENU_SETTINGS_PERFORMANCE_OVERLAY_OPACITY, "Opacity"),
    MAKE_STRING(HOME_MENU_SETTINGS_DEBUG, "Debug"),
    MAKE_STRING(HOME_MENU_SETTINGS_DEBUG_OVERLAY, "Debug Overlay"),
    MAKE_STRING(HOME_MENU_SETTINGS_DEBUG_INPUT_OVERLAY, "Input Debug Overlay"),
    MAKE_STRING(HOME_MENU_SETTINGS_DEBUG_DISABLE_VIDEO_OUTPUT,
                "Disable Video Output"),
    MAKE_STRING(HOME_MENU_SETTINGS_DEBUG_TEXTURE_LOD_BIAS,
                "Texture LOD Bias Addend"),
    MAKE_STRING(HOME_MENU_SCREENSHOT, "Take Screenshot"),
    MAKE_STRING(HOME_MENU_SAVESTATE, "SaveState"),
    MAKE_STRING(HOME_MENU_SAVESTATE_SAVE, "Save Emulation State"),
    MAKE_STRING(HOME_MENU_SAVESTATE_AND_EXIT, "Save Emulation State And Exit"),
    MAKE_STRING(HOME_MENU_RELOAD_SAVESTATE, "Reload Last Emulation State"),
    MAKE_STRING(HOME_MENU_NO_SAVESTATE, "No savestate for this game"),
    MAKE_STRING(HOME_MENU_RECORDING, "Start/Stop Recording"),
    MAKE_STRING(HOME_MENU_TROPHIES, "Trophies"),
    MAKE_STRING(HOME_MENU_TROPHY_HIDDEN_TITLE, "Hidden trophy"),
    MAKE_STRING(HOME_MENU_TROPHY_HIDDEN_DESCRIPTION, "This trophy is hidden"),
    MAKE_STRING(HOME_MENU_TROPHY_PLATINUM_RELEVANT, "Platinum relevant"),
    MAKE_STRING(HOME_MENU_TROPHY_GRADE_BRONZE, "Bronze"),
    MAKE_STRING(HOME_MENU_TROPHY_GRADE_SILVER, "Silver"),
    MAKE_STRING(HOME_MENU_TROPHY_GRADE_GOLD, "Gold"),
    MAKE_STRING(HOME_MENU_TROPHY_GRADE_PLATINUM, "Platinum"),
    MAKE_STRING(AUDIO_MUTED, "Audio muted"),
    MAKE_STRING(AUDIO_UNMUTED, "Audio unmuted"),
    MAKE_STRING(PROGRESS_DIALOG_PROGRESS, "Progress:"),
    MAKE_STRING(PROGRESS_DIALOG_PROGRESS_ANALYZING, "Progress: analyzing..."),
    MAKE_STRING(PROGRESS_DIALOG_REMAINING, "remaining"),
    MAKE_STRING(PROGRESS_DIALOG_DONE, "done"),
    MAKE_STRING(PROGRESS_DIALOG_FILE, "file"),
    MAKE_STRING(PROGRESS_DIALOG_MODULE, "module"),
    MAKE_STRING(PROGRESS_DIALOG_OF, "of"),
    MAKE_STRING(PROGRESS_DIALOG_PLEASE_WAIT, "Please wait"),
    MAKE_STRING(PROGRESS_DIALOG_STOPPING_PLEASE_WAIT,
                "Stopping. Please wait..."),
    MAKE_STRING(PROGRESS_DIALOG_SAVESTATE_PLEASE_WAIT,
                "Creating savestate. Please wait..."),
    MAKE_STRING(PROGRESS_DIALOG_SCANNING_PPU_EXECUTABLE,
                "Scanning PPU Executable..."),
    MAKE_STRING(PROGRESS_DIALOG_ANALYZING_PPU_EXECUTABLE,
                "Analyzing PPU Executable..."),
    MAKE_STRING(PROGRESS_DIALOG_SCANNING_PPU_MODULES,
                "Scanning PPU Modules..."),
    MAKE_STRING(PROGRESS_DIALOG_LOADING_PPU_MODULES, "Loading PPU Modules..."),
    MAKE_STRING(PROGRESS_DIALOG_COMPILING_PPU_MODULES,
                "Compiling PPU Modules..."),
    MAKE_STRING(PROGRESS_DIALOG_LINKING_PPU_MODULES, "Linking PPU Modules..."),
    MAKE_STRING(PROGRESS_DIALOG_APPLYING_PPU_CODE, "Applying PPU Code..."),
    MAKE_STRING(PROGRESS_DIALOG_BUILDING_SPU_CACHE, "Building SPU Cache..."),
    MAKE_STRING(EMULATION_PAUSED_RESUME_WITH_START,
                "Press and hold the START button to resume"),
    MAKE_STRING(EMULATION_RESUMING, "Resuming...!"),
    MAKE_STRING(EMULATION_FROZEN,
                "The PS3 application has likely crashed, you can close it."),
    MAKE_STRING(
        SAVESTATE_FAILED_DUE_TO_SAVEDATA,
        "SaveState failed: Game saving is in progress, wait until finished."),
    MAKE_STRING(SAVESTATE_FAILED_DUE_TO_VDEC,
                "SaveState failed: VDEC-base video/cutscenes are in order, "
                "wait for them to end or enable libvdec.sprx."),
    MAKE_STRING(SAVESTATE_FAILED_DUE_TO_MISSING_SPU_SETTING,
                "SaveState failed: Failed to lock SPU state, enabling "
                "SPU-Compatible mode may fix it."),
    MAKE_STRING(SAVESTATE_FAILED_DUE_TO_SPU,
                "SaveState failed: Failed to lock SPU state, using SPU ASMJIT "
                "will fix it."),
    MAKE_STRING(INVALID, "Invalid"),
};

enum GameFlags {
  kGameFlagLocked = 1 << 0,
  kGameFlagTrial = 1 << 1,
};

struct GameInfo {
  std::string path;
  std::string name;
  std::string iconPath;
  int flags = 0;
};

class Progress {
  JNIEnv *env;
  jlong progressId;
  jclass progressRepositoryClass;
  jmethodID onProgressEventMethodId;

public:
  Progress(JNIEnv *env, jlong progressId) : env(env), progressId(progressId) {
    progressRepositoryClass =
        ensure(env->FindClass("net/rpcsx/ProgressRepository"));
    onProgressEventMethodId = env->GetStaticMethodID(
        progressRepositoryClass, "onProgressEvent", "(JJJLjava/lang/String;)Z");
  }

  bool report(jlong value, jlong max, const std::string &message = {}) {
    return env->CallStaticBooleanMethod(
        progressRepositoryClass, onProgressEventMethodId, progressId, value,
        max, message.empty() ? nullptr : wrap(env, message));
  }

  void failure(const std::string &message = {}) { report(-1, 0, message); }

  void success(jlong value, const std::string &message = {}) {
    value = std::max<jlong>(value, 1);
    report(value, value, message);
  }

  jlong getProgressId() const { return progressId; }
};

static void sendFirmwareInstalled(JNIEnv *env, const std::string &version) {
  auto fwRepositoryClass =
      ensure(env->FindClass("net/rpcsx/FirmwareRepository"));
  auto methodId = ensure(env->GetStaticMethodID(
      fwRepositoryClass, "onFirmwareInstalled", "(Ljava/lang/String;)V"));

  env->CallStaticVoidMethod(fwRepositoryClass, methodId, wrap(env, version));
}

static void sendFirmwareCompiled(JNIEnv *env, const std::string &version) {
  auto fwRepositoryClass =
      ensure(env->FindClass("net/rpcsx/FirmwareRepository"));
  auto methodId = ensure(env->GetStaticMethodID(
      fwRepositoryClass, "onFirmwareCompiled", "(Ljava/lang/String;)V"));

  env->CallStaticVoidMethod(fwRepositoryClass, methodId, wrap(env, version));
}

static void sendGameInfo(JNIEnv *env, jlong progressId,
                         std::span<const GameInfo> infos) {
  auto gameRepositoryClass = ensure(env->FindClass("net/rpcsx/GameRepository"));
  auto addMethodId = ensure(env->GetStaticMethodID(
      gameRepositoryClass, "add", "([Lnet/rpcsx/GameInfo;J)V"));
  auto gameClass = ensure(env->FindClass("net/rpcsx/GameInfo"));

  jmethodID gameConstructor = ensure(env->GetMethodID(
      gameClass, "<init>",
      "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;I)V"));

  std::vector<jobject> objects;
  objects.reserve(infos.size());

  for (const auto &info : infos) {
    auto path = Emu.GetCallbacks().resolve_path(info.path);
    if (path.ends_with('/')) {
      path.resize(path.size() - 1);
    }

    objects.push_back(env->NewObject(
        gameClass, gameConstructor, wrap(env, path), wrap(env, info.name),
        wrap(env, Emu.GetCallbacks().resolve_path(info.iconPath)),
        jint(info.flags)));
  }

  auto result = env->NewObjectArray(objects.size(), gameClass, nullptr);

  for (std::size_t i = 0; i < objects.size(); ++i) {
    env->SetObjectArrayElement(result, i, objects[i]);
  }

  env->CallStaticVoidMethod(gameRepositoryClass, addMethodId, result,
                            progressId);
}

static void sendVshBootable(JNIEnv *env, jlong progressId) {
  auto dev_flash = g_cfg_vfs.get_dev_flash();

  sendGameInfo(
      env, progressId,
      {{GameInfo{
          .path = dev_flash + "/vsh/module/vsh.self",
          .name = "VSH",
          .iconPath = dev_flash + "vsh/resource/explore/icon/icon_home.png",
      }}});
}

static bool tryUnlockGame(const psf::registry &psf) {
  auto contentId = psf::get_string(psf, "CONTENT_ID");

  if (contentId.empty()) {
    return true;
  }

  const auto licenseDir = fmt::format(
      "%shome/%s/exdata/", rpcs3::utils::get_hdd0_dir(), Emu.GetUsr());

  const auto licenseFile = fmt::format("%s%s", licenseDir, contentId);
  if (std::filesystem::is_regular_file(licenseFile + ".rap")) {
    return true;
  }

  if (std::filesystem::is_regular_file(licenseFile + ".edat")) {
    return true;
  }

  return false;
}

static void collectGamePaths(std::vector<std::string> &paths,
                             const std::string &rootDir) {
  std::error_code ec;
  std::vector<std::filesystem::path> workList;
  workList.reserve(32);
  if (!std::filesystem::is_directory(rootDir)) {
    auto rootPath = std::filesystem::path(rootDir).parent_path();
    if (rootPath.filename() == "USRDIR") {
      rootPath = rootPath.parent_path();
    }
    if (rootPath.filename() == "PS3_GAME") {
      rootPath = rootPath.parent_path();
    }

    workList.push_back(rootPath);
  } else {
    workList.push_back(rootDir);
  }

  while (!workList.empty()) {
    auto dir = std::move(workList.back());
    workList.pop_back();

    for (auto &entry : std::filesystem::directory_iterator(dir, ec)) {
      if (entry.is_directory()) {
        if (entry.path().filename() != "C00") {
          workList.push_back(entry.path());
        }

        continue;
      }

      if (entry.is_regular_file() && entry.path().filename() == "PARAM.SFO") {
        paths.push_back(entry.path().parent_path().string());
        continue;
      }
    }
  }
}

static std::string locateEbootPath(std::string_view root) {
  if (std::filesystem::is_regular_file(root)) {
    return std::string(root);
  }

  for (auto suffix : {
           "/EBOOT.BIN",
           "/USRDIR/EBOOT.BIN",
           "/USRDIR/ISO.BIN.EDAT",
           "/PS3_GAME/USRDIR/EBOOT.BIN",
       }) {
    auto tryPath = std::string(root);
    tryPath += suffix;

    if (std::filesystem::is_regular_file(tryPath)) {
      return tryPath;
    }
  }

  return {};
}

static std::string locateParamSfoPath(std::string_view root) {
  if (std::filesystem::is_regular_file(root)) {
    return std::string(root);
  }

  for (auto suffix : {
           "/PARAM.SFO",
           "/PS3_GAME/PARAM.SFO",
       }) {
    auto tryPath = std::string(root);
    tryPath += suffix;

    if (std::filesystem::is_regular_file(tryPath)) {
      return tryPath;
    }
  }

  return {};
}

static std::optional<GameInfo>
fetchGameInfo(const psf::registry &psf,
              std::filesystem::path psfRootPath = {}) {
  auto titleId = std::string(psf::get_string(psf, "TITLE_ID"));
  auto name = std::string(psf::get_string(psf, "TITLE"));
  auto bootable = psf::get_integer(psf, "BOOTABLE", 0);
  auto category = psf::get_string(psf, "CATEGORY");

  if (!bootable || titleId.empty()) {
    return {};
  }

  bool isDiscGame = category == "DG";

  std::string path;

  if (!isDiscGame) {
    path = rpcs3::utils::get_hdd0_dir() + "game/" + titleId + "/";
  } else {
    if (psfRootPath.empty()) {
      path = fs::get_config_dir() + "games/" + titleId + "/";
    } else {
      // Locate game root path
      if (psfRootPath.filename() == "USRDIR") {
        psfRootPath = psfRootPath.parent_path();
      }

      if (psfRootPath.filename() == "PS3_GAME") {
        psfRootPath = psfRootPath.parent_path();
      }

      path = psfRootPath;
      if (!path.ends_with('/')) {
        path += '/';
      }
    }
  }

  auto dataPath = isDiscGame ? path + "PS3_GAME/" : path;
  auto iconPath = dataPath + "ICON0.PNG";
  auto moviePath = dataPath + "ICON1.PAM";

  int flags = 0;

  if (!isDiscGame) {
    auto ebootPath = locateEbootPath(path);

    bool isLocked = false;

    if (!ebootPath.empty()) {
      if (fs::file eboot{ebootPath};
          eboot && eboot.size() >= 4 && eboot.read<u32>() == "SCE\0"_u32) {
        isLocked = !decrypt_self(eboot);
      }
    }

    if (isLocked) {
      flags |= kGameFlagLocked;
      rpcsx_android.warning("game %s is locked", path);
    }

    auto c00Path = path + "/C00";

    bool isTrial = std::filesystem::is_directory(c00Path);

    if (isTrial) {
      if (!tryUnlockGame(psf)) {
        flags |= kGameFlagTrial;
        rpcsx_android.warning("game %s is trial", path);
      } else {
        auto c00IconPath = c00Path + "/ICON0.PNG";
        if (std::filesystem::is_regular_file(c00IconPath)) {
          iconPath = c00IconPath;
        }

        auto c00SfoPath = c00Path + "/PARAM.SFO";

        if (std::filesystem::is_regular_file(c00IconPath)) {
          auto c00Sfo = psf::load_object(c00SfoPath);
          titleId = psf::get_string(c00Sfo, "TITLE_ID", titleId);
          name = psf::get_string(c00Sfo, "TITLE", name);
        }
      }
    }
  }

  return GameInfo{
      .path = std::move(path),
      .name = std::move(name),
      .iconPath = std::move(iconPath),
      .flags = flags,
  };
}

static void collectGameInfo(JNIEnv *env, jlong progressId,
                            const std::vector<std::string> &rootDirs) {
  std::vector<std::string> paths;
  for (auto &&rootDir : rootDirs) {
    collectGamePaths(paths, rootDir);

    rpcsx_android.notice("collectGameInfo: processed %s", rootDir);
  }

  rpcsx_android.notice("collectGameInfo: found %d paths", paths.size());

  Progress progress(env, progressId);
  progress.report(0, paths.size());

  std::vector<GameInfo> gameInfos;
  gameInfos.reserve(10);
  std::size_t processed = 0;

  auto submit = [&] {
    if (gameInfos.empty()) {
      return;
    }

    sendGameInfo(env, progressId, gameInfos);
    progress.report(processed, paths.size());
    gameInfos.clear();
  };

  for (auto &&path : paths) {
    processed++;

    if (!std::filesystem::is_regular_file(path + "/PARAM.SFO")) {
      continue;
    }

    const auto psf = psf::load_object(path + "/PARAM.SFO");

    rpcsx_android.notice("collectGameInfo: sfo at %s", path);

    if (auto gameInfo = fetchGameInfo(psf, path)) {
      gameInfos.push_back(std::move(*gameInfo));

      if (gameInfos.size() >= 10) {
        submit();
      }
    }
  }

  submit();

  progress.success(processed);
}

class MainThreadProcessor {
  std::mutex mutex;
  std::condition_variable cv;
  std::deque<std::pair<std::function<void(JNIEnv *)>, atomic_t<u32> *>> queue;

public:
  void push(std::function<void(JNIEnv *)> cb, atomic_t<u32> *wakeUp = nullptr) {
    std::lock_guard lock(mutex);
    queue.push_back({std::move(cb), wakeUp});
    cv.notify_one();
  }

  void push(std::function<void()> cb, atomic_t<u32> *wakeUp = nullptr) {
    push([cb = std::move(cb)](JNIEnv *) { cb(); }, wakeUp);
  }

  void process(JNIEnv *env) {
    while (true) {
      std::function<void(JNIEnv *)> cb;
      atomic_t<u32> *wakeUp = nullptr;

      {
        std::unique_lock lock(mutex);
        if (queue.empty()) {
          cv.wait(lock);
          continue;
        }

        auto item = std::move(queue.front());
        queue.pop_front();

        cb = std::move(item.first);
        wakeUp = item.second;
      }

      cb(env);
      if (wakeUp) {
        *wakeUp = true;
        wakeUp->notify_all();
      }
    }
  }
} static g_mainThreadProcessor;

static void invokeAsync(std::function<void(JNIEnv *)> cb) {
  g_mainThreadProcessor.push(std::move(cb));
}

static void invokeSync(std::function<void(JNIEnv *)> cb) {
  atomic_t<u32> wakeup{false};
  g_mainThreadProcessor.push(std::move(cb), &wakeup);

  while (wakeup.load() == false) {
    wakeup.wait(false);
  }
}

struct ProgressMessageDialog : MsgDialogBase {
  jlong progressId;
  jlong value = 0;
  jlong max = 0;

  ProgressMessageDialog(jlong progressId) : progressId(progressId) {}

  void Create(const std::string &msg, const std::string &title) override {
    rpcsx_android.warning("ProgressMessageDialog::Create(%s, %s)", msg, title);
    max = 100;
    invokeSync([this, &msg](JNIEnv *env) {
      Progress progress(env, progressId);
      progress.report(0, 0, msg);
    });
  }

  jlong getValue() const {
    return value == max && max != 0 ? value - 1 : value;
  }

  void Close(bool success) override {
    rpcsx_android.warning("ProgressMessageDialog::Close(%s)", success);
    invokeSync([this](JNIEnv *env) {
      Progress progress(env, progressId);
      progress.report(0, 0);
    });

    //   Progress progress(env, progressId);
    //   if (success) {
    //     progress.success(0);
    //   } else {
    //     progress.failure();
    //   }
    // });
  }

  void SetMsg(const std::string &msg) override {
    rpcsx_android.warning("ProgressMessageDialog::SetMsg(%s)", msg);
    invokeSync([this, msg](JNIEnv *env) {
      Progress(env, progressId).report(getValue(), max, msg);
    });
  }

  void ProgressBarSetMsg(u32 progressBarIndex,
                         const std::string &msg) override {
    rpcsx_android.warning("ProgressMessageDialog::ProgressBarSetMsg(%d, %s)",
                          progressBarIndex, msg);
    if (progressBarIndex != 0) {
      report_fatal_error("Unexpected progress index in progress dialog");
    }

    invokeSync([this, msg](JNIEnv *env) {
      Progress(env, progressId).report(getValue(), max, msg);
    });
  }

  void ProgressBarReset(u32 progressBarIndex) override {
    rpcsx_android.warning("ProgressMessageDialog::ProgressBarReset(%d)",
                          progressBarIndex);

    if (progressBarIndex != 0) {
      report_fatal_error("Unexpected progress index in progress dialog");
    }

    value = 0;
    invokeSync(
        [this](JNIEnv *env) { Progress(env, progressId).report(value, max); });
  }

  void ProgressBarInc(u32 progressBarIndex, u32 delta) override {
    rpcsx_android.warning("ProgressMessageDialog::ProgressBarInc(%d, %d)",
                          progressBarIndex, delta);

    if (progressBarIndex != 0) {
      report_fatal_error("Unexpected progress index in progress dialog");
    }

    value += delta;

    invokeSync([this](JNIEnv *env) {
      Progress(env, progressId).report(getValue(), max);
    });
  }

  void ProgressBarSetValue(u32 progressBarIndex, u32 value) override {
    rpcsx_android.warning("ProgressMessageDialog::ProgressBarSetValue(%d, %d)",
                          progressBarIndex, value);

    if (progressBarIndex != 0) {
      report_fatal_error("Unexpected progress index in progress dialog");
    }

    this->value = value;

    invokeSync([this](JNIEnv *env) {
      Progress(env, progressId).report(getValue(), max);
    });
  }
  void ProgressBarSetLimit(u32 index, u32 limit) override {
    rpcsx_android.warning("ProgressMessageDialog::ProgressBarSetLimit(%d, %d)",
                          index, limit);

    if (index != 0) {
      report_fatal_error("Unexpected progress index in progress dialog");
    }

    max = limit;

    invokeSync([this](JNIEnv *env) {
      Progress(env, progressId).report(getValue(), max);
    });
  }
};

struct UiMessageDialog : MsgDialogBase {
  // FIXME: implement

  void Create(const std::string &msg, const std::string &title) override {}
  void Close(bool success) override {}
  void SetMsg(const std::string &msg) override {}
  void ProgressBarSetMsg(u32 progressBarIndex,
                         const std::string &msg) override {}
  void ProgressBarReset(u32 progressBarIndex) override {}
  void ProgressBarInc(u32 progressBarIndex, u32 delta) override {}
  void ProgressBarSetValue(u32 progressBarIndex, u32 value) override {}
  void ProgressBarSetLimit(u32 index, u32 limit) override {}
};

struct MessageDialog : MsgDialogBase {
  std::unique_ptr<MsgDialogBase> impl = nullptr;

  void Create(const std::string &msg, const std::string &title) override {
    auto progressId = s_pendingProgressId.load();

    rpcsx_android.warning("MessageDialog::Create(%s, %s): source %s, id %d",
                          msg, title, source, progressId);

    if (progressId != -1) {
      impl = std::make_unique<ProgressMessageDialog>(progressId);
    } else {
      impl = std::make_unique<UiMessageDialog>();
    }

    impl->type = type;
    impl->source = source;
    impl->Create(msg, title);
  }

  void Close(bool success) override { impl->Close(success); }

  void SetMsg(const std::string &msg) override { impl->SetMsg(msg); }

  void ProgressBarSetMsg(u32 progressBarIndex,
                         const std::string &msg) override {
    impl->ProgressBarSetMsg(progressBarIndex, msg);
  }

  void ProgressBarReset(u32 progressBarIndex) override {
    impl->ProgressBarReset(progressBarIndex);
  }

  void ProgressBarInc(u32 progressBarIndex, u32 delta) override {
    impl->ProgressBarInc(progressBarIndex, delta);
  }

  void ProgressBarSetValue(u32 progressBarIndex, u32 value) override {
    impl->ProgressBarSetValue(progressBarIndex, value);
  }

  void ProgressBarSetLimit(u32 index, u32 limit) override {
    impl->ProgressBarSetLimit(index, limit);
  }

  static void pushPendingProgressId(jlong id) {
    jlong value = -1;

    while (!s_pendingProgressId.compare_exchange_weak(value, id)) {
      s_pendingProgressId.wait(value);
      value = -1;
    }
  }

  static bool popPendingProgressId(jlong id) {
    return s_pendingProgressId.compare_exchange_strong(id, -1);
  }

private:
  static std::atomic<jlong> s_pendingProgressId;
};

struct OverlaySaveDialog : SaveDialogBase {
  s32 ShowSaveDataList(const std::string &base_dir,
                       std::vector<SaveDataEntry> &save_entries, s32 focused,
                       u32 op, vm::ptr<CellSaveDataListSet> listSet,
                       bool enable_overlay) override {
    rpcsx_android.notice("ShowSaveDataList(save_entries=%d, focused=%d, "
                         "op=0x%x, listSet=*0x%x, enable_overlay=%d)",
                         save_entries.size(), focused, op, listSet,
                         enable_overlay);

    bool use_end = sysutil_send_system_cmd(CELL_SYSUTIL_DRAWING_BEGIN, 0) >= 0;

    auto atExit = AtExit([&] {
      if (use_end) {
        sysutil_send_system_cmd(CELL_SYSUTIL_DRAWING_END, 0);
      }
    });

    if (!use_end) {
      rpcsx_android.error(
          "ShowSaveDataList(): Not able to notify DRAWING_BEGIN callback "
          "because one has already been sent!");
    }

    if (auto manager = g_fxo->try_get<rsx::overlays::display_manager>()) {
      rpcsx_android.notice("ShowSaveDataList: Showing native UI dialog");

      s32 result = manager->create<rsx::overlays::save_dialog>()->show(
          base_dir, save_entries, focused, op, listSet, enable_overlay);

      if (result != rsx::overlays::user_interface::selection_code::error) {
        rpcsx_android.notice(
            "ShowSaveDataList: Native UI dialog returned with selection %d",
            result);

        return result;
      }

      rpcsx_android.error("ShowSaveDataList: Native UI dialog returned error");
    }

    return -2;
  }
};

class OverlayTrophyNotification : public TrophyNotificationBase {
public:
  s32 ShowTrophyNotification(
      const SceNpTrophyDetails &trophy,
      const std::vector<uchar> &trophy_icon_buffer) override {
    if (auto manager = g_fxo->try_get<rsx::overlays::display_manager>()) {
      auto popup = std::make_shared<rsx::overlays::trophy_notification>();
      return manager->add(popup, false)->show(trophy, trophy_icon_buffer);
    }

    return 0;
  }
};

std::atomic<jlong> MessageDialog::s_pendingProgressId = -1;

struct CompilationWorkload {
  jlong progressId;
  std::string path;
  std::string scanRoot;
  std::string paramSfoPath;
  std::string titleId;
  bool precompileFirmwareModules = false;
};

extern bool ppu_load_exec(const ppu_exec_object &, bool virtual_load,
                          const std::string &, utils::serial * = nullptr);
extern void spu_load_exec(const spu_exec_object &);
extern void spu_load_rel_exec(const spu_rel_object &);
extern void ppu_precompile(std::vector<std::string> &dir_queue,
                           std::vector<ppu_module<lv2_obj> *> *loaded_prx);
extern bool ppu_initialize(const ppu_module<lv2_obj> &, bool check_only = false,
                           u64 file_size = 0);
extern void ppu_finalize(const ppu_module<lv2_obj> &);
extern bool ppu_load_rel_exec(const ppu_rel_object &);

static bool isCachePreparationExecutable(std::string_view path) {
  fs::file file{std::string(path)};
  if (!file || file.size() < sizeof(u32)) {
    return false;
  }

  file.seek(0);
  u32 magic{};
  return file.read(magic) &&
         (magic == "SCE\0"_u32 || magic == "\177ELF"_u32);
}

class CompilationQueue {
  std::atomic<std::uint64_t> nextWorkTag{0};
  std::uint64_t lastProcessedTag = 0;
  std::mutex queueMutex;
  std::deque<CompilationWorkload> queue;

public:
  void push(CompilationWorkload workload) {
    {
      std::lock_guard lock(queueMutex);
      queue.push_back(std::move(workload));
    }

    nextWorkTag.fetch_add(1);
  }

  void push(Progress &progress, std::string path) {
    progress.report(0, 0);

    push({
        .progressId = progress.getProgressId(),
        .path = std::move(path),
    });
  }

  void process(JNIEnv *env) {
    while (true) {
      auto nextWorkTagValue = nextWorkTag.load();

      if (nextWorkTagValue == lastProcessedTag) {
        nextWorkTag.wait(lastProcessedTag);
      }

      if (nextWorkTagValue == lastProcessedTag || queue.empty()) {
        continue;
      }

      CompilationWorkload workload;

      {
        std::lock_guard lock(queueMutex);

        if (queue.empty()) {
          continue;
        }

        workload = std::move(queue.front());
        queue.pop_front();
      }

      compile(env, std::move(workload));
      lastProcessedTag++;
    }
  }

  bool prepare(JNIEnv *env, std::string path, std::string titleId,
               jlong progressId) {
    Progress progress(env, progressId);
    progress.report(0, 0, "Preparing PPU cache");

    const system_state state = Emu.GetStatus(false);
    if (state != system_state::stopped && state != system_state::ready) {
      progress.failure("Stop the current game before preparing cache.");
      return false;
    }

    std::string ebootPath;
    std::string scanRoot;
    std::string paramSfoPath;
    std::string sourceKind = "directory";
    shared_ptr<fs::device_base> isoDevice;
    std::string isoPrefix;
    bool isoRegistered = false;
    AtExit isoRestore{[&] {
      if (!isoRegistered) {
        return;
      }

      const auto removed = fs::set_virtual_device(isoPrefix, {});
      if (removed != isoDevice) {
        rpcsx_android.fatal(
            "Failed to remove cache-preparation ISO virtual device: %s",
            isoPrefix);
      }
    }};

    if (fs::is_file(path)) {
      fs::file source{path};
      if (getFileType(source) == FileType::Iso) {
        auto openedIso = iso_dev::open(
            std::make_unique<file_block_dev>(std::move(source)));
        if (!openedIso) {
          progress.failure("The selected cache-preparation ISO is invalid.");
          return false;
        }

        isoDevice = stx::make_shared<iso_dev>(std::move(*openedIso));
        isoPrefix = isoDevice->fs_prefix;
        if (fs::set_virtual_device(isoPrefix, isoDevice) != isoDevice) {
          progress.failure(
              "The selected ISO could not be mounted for cache preparation.");
          return false;
        }
        isoRegistered = true;
        sourceKind = "iso";
        scanRoot = isoPrefix + "/PS3_GAME";
        paramSfoPath = scanRoot + "/PARAM.SFO";
        ebootPath = scanRoot + "/USRDIR/EBOOT.BIN";
      } else {
        sourceKind = "executable";
        ebootPath = path;
      }
    } else if (fs::is_dir(path)) {
      ebootPath = locateEbootPath(path);
    }

    if (ebootPath.empty() || !fs::is_file(ebootPath) ||
        !isCachePreparationExecutable(ebootPath)) {
      progress.failure("No bootable EBOOT.BIN found for cache preparation.");
      return false;
    }

    if (scanRoot.empty()) {
      auto rootPath = std::filesystem::path(ebootPath).parent_path();
      if (rootPath.filename() == "USRDIR") {
        rootPath = rootPath.parent_path();
      }
      scanRoot = rootPath.string();
      paramSfoPath = scanRoot + "/PARAM.SFO";
    }

    if (!fs::is_dir(scanRoot)) {
      progress.failure(
          "The selected game root is invalid for cache preparation.");
      return false;
    }

    if (fs::is_file(paramSfoPath)) {
      const auto psf = psf::load_object(paramSfoPath);
      const std::string sourceTitleId =
          std::string(psf::get_string(psf, "TITLE_ID"));
      if (sourceTitleId.empty()) {
        progress.failure(
            "The selected game has no title ID for cache preparation.");
        return false;
      }
      if (!titleId.empty() && sourceTitleId != titleId) {
        progress.failure(
            "The selected game does not match the requested title ID.");
        return false;
      }
      titleId = sourceTitleId;
    } else if (!titleId.empty()) {
      progress.failure(
          "The selected game has no PARAM.SFO for cache preparation.");
      return false;
    }

    const bool precompileFirmwareModules = titleId == "BLUS30161";
    if (precompileFirmwareModules) {
      rpcsx_android.always()(
          "Thor PPU cache source resolved: title=%s, source=%s, "
          "scan-root=%s, eboot=%s",
          titleId, sourceKind, scanRoot, ebootPath);
    }
    std::string previousConfig;
    std::string previousConfigName;
    bool restoreConfig = false;
    AtExit configRestore{[&] {
      if (!restoreConfig) {
        return;
      }

      if (!g_cfg.from_string(previousConfig)) {
        rpcsx_android.fatal("Failed to restore global configuration after PPU "
                            "cache preparation");
      }
      g_cfg.name = previousConfigName;
    }};

    if (precompileFirmwareModules) {
      const std::string titleConfigPath =
          rpcs3::utils::get_custom_config_path(titleId);
      fs::file titleConfig{titleConfigPath};
      if (!titleConfig) {
        progress.failure(
            "Apply the managed Eternal Sonata Thor profile before preparing "
            "cache.");
        return false;
      }

      const std::string titleConfigText = titleConfig.to_string();
      if (!titleConfigText.starts_with("# RPCSX_THOR_AUTO_SETTINGS") ||
          titleConfigText.find("# Title ID: BLUS30161") == std::string::npos) {
        progress.failure(
            "Eternal Sonata cache preparation requires the managed Thor "
            "profile; custom settings were left untouched.");
        return false;
      }

      previousConfig = g_cfg.to_string();
      previousConfigName = g_cfg.name;
      restoreConfig = true;
      if (!g_cfg.from_string(titleConfigText)) {
        progress.failure(
            "The managed Eternal Sonata Thor profile could not be loaded.");
        return false;
      }
      g_cfg.name = titleConfigPath;

      // Boot applies the same LLVM compatibility fixups before forming PPU
      // cache identities. Mirror them here so prepared objects are reusable.
      g_cfg.core.ppu_use_nj_bit.set(false);
      g_cfg.core.ppu_set_vnan.set(false);
      g_cfg.core.ppu_set_fpcc.set(false);

      if (g_cfg.core.ppu_decoder != ppu_decoder_type::llvm_legacy ||
          g_cfg.core.spu_decoder != spu_decoder_type::llvm ||
          !g_cfg.core.set_daz_and_ftz || g_cfg.core.llvm_threads != 2) {
        progress.failure(
            "The Eternal Sonata Thor profile is not the expected PPU/SPU "
            "LLVM/FTZ cache variant.");
        return false;
      }

      const std::string firmwareRoot =
          g_cfg_vfs.get_dev_flash() + "sys/external/";
      if (!fs::is_dir(firmwareRoot)) {
        progress.failure(
            "PS3 firmware modules are missing; install firmware before "
            "preparing Eternal Sonata cache.");
        return false;
      }

      rpcsx_android.always()(
          "Thor PPU cache preparation activated: title=%s, "
          "managed-config=%s, firmware-root=%s, llvm-threads=%u, ftz=true",
          titleId, titleConfigPath, firmwareRoot,
          static_cast<u32>(g_cfg.core.llvm_threads.get()));
    }

    if (!titleId.empty()) {
      Emu.SetTitleID(titleId);
    }

    return compile(env,
                   {
                       .progressId = progressId,
                       .path = std::move(ebootPath),
                       .scanRoot = std::move(scanRoot),
                       .paramSfoPath = std::move(paramSfoPath),
                       .titleId = titleId,
                       .precompileFirmwareModules = precompileFirmwareModules,
                   });
  }

private:
  bool compile(JNIEnv *env, CompilationWorkload workload) {
    if (workload.path.empty()) {
      Progress(env, workload.progressId).success(0);
      return true;
    }

    rpcsx_android.error("Creating cache initiated, state %d",
                        (int)Emu.GetStatus(false));

    while (true) {
      auto state = Emu.GetStatus(false);

      if (state == system_state::stopped || state == system_state::ready) {
        break;
      }

      rpcsx_android.error("Creating cache wait, state %d", (int)state);
      std::this_thread::sleep_for(std::chrono::seconds(1));
    }

    bool is_vsh = workload.path.ends_with("/vsh.self");

    Emu.SetState(system_state::running);

    MessageDialog::pushPendingProgressId(workload.progressId);

    // Cache preparation is already an explicit stopped-emulator operation.
    // Use it to migrate only validated live PPU objects out of legacy gzip so
    // ordinary Android boot never pays a directory-wide conversion cost.
    jit_compiler::set_raw_cache_materialization(true);
    AtExit rawCacheMaterializationGuard{
        [] { jit_compiler::set_raw_cache_materialization(false); }};

    g_fxo->init<named_thread<progress_dialog_server>>();
    g_fxo->init<main_ppu_module<lv2_obj>>();
    g_fxo->init(false, nullptr);
    auto rootPath = std::filesystem::path(
        workload.scanRoot.empty() ? workload.path : workload.scanRoot);

    if (is_vsh) {
      rootPath = g_cfg_vfs.get_dev_flash() + "sys/external/";
    } else if (workload.scanRoot.empty()) {
      if (!std::filesystem::is_directory(rootPath)) {
        rootPath = rootPath.parent_path();
        if (rootPath.filename() == "USRDIR") {
          rootPath = rootPath.parent_path();
        }
      }
    }

    auto &_main = *ensure(g_fxo->try_get<main_ppu_module<lv2_obj>>());

    if (fs::is_file(workload.path)) {
      if (!is_vsh) {
        auto sfoPath = workload.paramSfoPath.empty()
                           ? locateParamSfoPath(std::string(rootPath))
                           : workload.paramSfoPath;

        if (!sfoPath.empty() && fs::is_file(sfoPath)) {
          const auto psf = psf::load_object(sfoPath);
          rpcsx_android.warning("title id is %s",
                                psf::get_string(psf, "TITLE_ID"));

          Emu.SetTitleID(std::string(psf::get_string(psf, "TITLE_ID")));
        } else {
          rpcsx_android.warning("param.sfo not found");
        }
      }

      // Compile binary first
      rpcsx_android.notice("Trying to load binary: %s", workload.path);

      fs::file src{workload.path};
      src = decrypt_self(src);

      const ppu_exec_object obj = src;

      if (obj == elf_error::ok && ppu_load_exec(obj, true, workload.path)) {
        _main.path = workload.path;
      } else {
        rpcsx_android.error("Failed to load binary '%s' (%s)", workload.path,
                            obj.get_error());
      }
    }

    std::vector<std::string> dir_queue;
    dir_queue.push_back(rootPath.string());

    // ppu_precompile already discovers subdirectories recursively. Supplying
    // each child here made the explicit preparation path scan them twice.
    if (workload.precompileFirmwareModules) {
      dir_queue.push_back(g_cfg_vfs.get_dev_flash() + "sys/external/");
    }

    std::vector<ppu_module<lv2_obj> *> mod_list;
    rpcsx_android.error("Going to analyze executable");

    // FIXME: split states
    if (!is_vsh) {
      if (_main.analyse(0, _main.elf_entry, _main.seg0_code_end,
                        _main.applied_patches, std::vector<u32>{})) {
        Emu.ConfigurePPUCache();
        Emu.SetTestMode();
        rpcsx_android.error("Going to precompile main PPU module");
        ppu_initialize(_main);
        mod_list.emplace_back(&_main);
      }
    }

    ppu_precompile(dir_queue, mod_list.empty() ? nullptr : &mod_list);

    if (workload.precompileFirmwareModules) {
      rpcsx_android.always()("Thor PPU cache preparation completed: title=%s",
                             workload.titleId);
      if (spu_native_object_cache_enabled() &&
          g_cfg.core.spu_decoder == spu_decoder_type::llvm) {
        rpcsx_android.always()(
            "Thor SPU native-object cache preparation activated: title=%s",
            workload.titleId);
        spu_cache::initialize();
        if (!Emu.IsStopped()) {
          rpcsx_android.always()(
              "Thor SPU native-object cache preparation completed: title=%s",
              workload.titleId);
        }
      }
    }

    rpcsx_android.error("Finalization");
    g_fxo->reset();
    Emu.SetState(system_state::stopped);

    MessageDialog::popPendingProgressId(workload.progressId);

    Progress(env, workload.progressId).success(0);
    return true;
  }
} static g_compilationQueue;

static void setupCallbacks() {
  Emu.SetCallbacks({
      .call_from_main_thread =
          [](std::function<void()> cb, atomic_t<u32> *wake_up) {
            cb();
            if (wake_up) {
              *wake_up = true;
            }
          },
      .on_run = [](auto...) {},
      .on_pause = [](auto...) {},
      .on_resume = [](auto...) {},
      .on_stop = [](auto...) {},
      .on_ready = [](auto...) {},
      .on_missing_fw = [](auto...) {},
      .on_emulation_stop_no_response = [](auto...) {},
      .on_save_state_progress = [](auto...) {},
      .enable_disc_eject = [](auto...) {},
      .enable_disc_insert = [](auto...) {},
      .handle_taskbar_progress = [](auto...) {},
      .init_kb_handler =
          [](auto...) {
            ensure(g_fxo->init<KeyboardHandlerBase, NullKeyboardHandler>(
                Emu.DeserialManager()));
          },
      .init_mouse_handler =
          [](auto...) {
            ensure(g_fxo->init<MouseHandlerBase, NullMouseHandler>(
                Emu.DeserialManager()));
          },
      .init_pad_handler =
          [](auto...) {
            ensure(g_fxo->init<named_thread<pad_thread>>(nullptr, nullptr, ""));
          },
      .update_emu_settings = [](auto...) {},
      .save_emu_settings =
          [](auto...) {
            Emulator::SaveSettings(g_cfg.to_string(), Emu.GetTitleID());
          },
      .close_gs_frame = [](auto...) {},
      .get_gs_frame = [] { return std::make_unique<GraphicsFrame>(); },
      .get_camera_handler =
          [](auto...) { return std::make_shared<null_camera_handler>(); },
      .get_music_handler =
          [](auto...) { return std::make_shared<null_music_handler>(); },
      .create_pad_handler = [](pad_handler type, void *thread, void *window)
          -> std::shared_ptr<PadHandlerBase> {
        switch (type) {
        case pad_handler::keyboard:
        case pad_handler::null:
          break;
        case pad_handler::ds3:
          return std::make_shared<ds3_pad_handler>();
        case pad_handler::ds4:
          return std::make_shared<ds4_pad_handler>();
        case pad_handler::dualsense:
          return std::make_shared<dualsense_pad_handler>();
        case pad_handler::skateboard:
          //   return std::make_shared<skateboard_pad_handler>();
          break;
        case pad_handler::move:
          // return std::make_shared<ps_move_handler>();
          break;
#ifdef _WIN32
        case pad_handler::xinput:
          return std::make_shared<xinput_pad_handler>();
        case pad_handler::mm:
          return std::make_shared<mm_joystick_handler>();
#endif
#ifdef HAVE_SDL3
        case pad_handler::sdl:
          return std::make_shared<sdl_pad_handler>();
#endif
#ifdef HAVE_LIBEVDEV
        case pad_handler::evdev:
          return std::make_shared<evdev_joystick_handler>();
#endif
        case pad_handler::virtual_pad:
          return std::make_shared<virtual_pad_handler>();
        }

        return std::make_shared<NullPadHandler>();
      },
      .init_gs_render =
          [](utils::serial *ar) {
            switch (g_cfg.video.renderer.get()) {
            case video_renderer::null:
              g_fxo->init<rsx::thread, named_thread<NullGSRender>>(ar);
              break;
            case video_renderer::vulkan:
              g_fxo->init<rsx::thread, named_thread<VKGSRender>>(ar);
              break;

            default:
              break;
            }
          },
      .get_audio =
          [](auto...) {
            std::shared_ptr<AudioBackend> result;

            switch (g_cfg.audio.renderer.get()) {
            case audio_renderer::null:
              result = std::make_shared<NullAudioBackend>();
              break;

            case audio_renderer::cubeb:
            default:
              result = std::make_shared<CubebBackend>();
              break;
            }

            if (!result->Initialized()) {
              rpcsx_android.error(
                  "Audio renderer %s could not be initialized, using a Null "
                  "renderer instead. Make sure that no other application is "
                  "running that might block audio access (e.g. Netflix).",
                  result->GetName());
              result = std::make_shared<NullAudioBackend>();
            }
            return result;
          },
      .get_audio_enumerator = [](auto...) { return nullptr; },
      .get_msg_dialog = [] { return std::make_shared<MessageDialog>(); },
      .get_osk_dialog = [](auto...) { return nullptr; },
      .get_save_dialog =
          [](auto...) { return std::make_unique<OverlaySaveDialog>(); },
      .get_sendmessage_dialog = [](auto...) { return nullptr; },
      .get_recvmessage_dialog = [](auto...) { return nullptr; },
      .get_trophy_notification_dialog =
          [](auto...) { return std::make_unique<OverlayTrophyNotification>(); },
      .get_localized_string = [](localized_string_id id,
                                 const char *) -> std::string {
        if (std::size_t(id) < std::size(g_strings)) {
          return g_strings[int(id)].first;
        }
        return "";
      },
      .get_localized_u32string = [](localized_string_id id,
                                    const char *) -> std::u32string {
        if (std::size_t(id) < std::size(g_strings)) {
          return g_strings[int(id)].second;
        }
        return U"";
      },
      .get_localized_setting = [](auto...) { return ""; },
      .play_sound = [](auto...) {},
      .get_image_info = [](auto...) { return false; },
      .get_scaled_image = [](auto...) { return false; },
      .resolve_path =
          [](std::string_view arg) {
            std::error_code ec;
            auto result =
                std::filesystem::weakly_canonical(
                    std::filesystem::path(fmt::replace_all(arg, "\\", "/")), ec)
                    .string();
            return ec ? std::string(arg) : result;
          },
      .get_font_dirs = [](auto...) { return std::vector<std::string>(); },
      .on_install_pkgs =
          [](const std::vector<std::string> &pkgs) {
            for (const std::string &pkg : pkgs) {
              if (!rpcs3::utils::install_pkg(pkg)) {
                rpcsx_android.error("cd install pkgs: failed to install %s",
                                    pkg);
                return false;
              }
            }
            return true;
          },
      .add_breakpoint = [](auto...) {},
      .display_sleep_control_supported = [](auto...) { return false; },
      .enable_display_sleep = [](auto...) {},
      .check_microphone_permissions = [](auto...) {},
  });
}

static bool initVirtualPad(const std::shared_ptr<Pad> &pad) {
  u32 pclass_profile = 0;
  pad->Init(CELL_PAD_STATUS_CONNECTED,
            CELL_PAD_CAPABILITY_PS3_CONFORMITY |
                CELL_PAD_CAPABILITY_PRESS_MODE |
                CELL_PAD_CAPABILITY_HP_ANALOG_STICK |
                CELL_PAD_CAPABILITY_ACTUATOR //| CELL_PAD_CAPABILITY_SENSOR_MODE
            ,
            CELL_PAD_DEV_TYPE_STANDARD, CELL_PAD_PCLASS_TYPE_STANDARD,
            pclass_profile, 0, 0, 50);

  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL1, std::set<u32>{},
                              CELL_PAD_CTRL_UP);
  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL1, std::set<u32>{},
                              CELL_PAD_CTRL_DOWN);
  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL1, std::set<u32>{},
                              CELL_PAD_CTRL_LEFT);
  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL1, std::set<u32>{},
                              CELL_PAD_CTRL_RIGHT);
  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL2, std::set<u32>{},
                              CELL_PAD_CTRL_CROSS);
  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL2, std::set<u32>{},
                              CELL_PAD_CTRL_SQUARE);
  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL2, std::set<u32>{},
                              CELL_PAD_CTRL_CIRCLE);
  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL2, std::set<u32>{},
                              CELL_PAD_CTRL_TRIANGLE);
  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL2, std::set<u32>{},
                              CELL_PAD_CTRL_L1);
  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL2, std::set<u32>{},
                              CELL_PAD_CTRL_L2);
  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL1, std::set<u32>{},
                              CELL_PAD_CTRL_L3);
  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL2, std::set<u32>{},
                              CELL_PAD_CTRL_R1);
  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL2, std::set<u32>{},
                              CELL_PAD_CTRL_R2);
  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL1, std::set<u32>{},
                              CELL_PAD_CTRL_R3);
  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL1, std::set<u32>{},
                              CELL_PAD_CTRL_START);
  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL1, std::set<u32>{},
                              CELL_PAD_CTRL_SELECT);
  pad->m_buttons.emplace_back(CELL_PAD_BTN_OFFSET_DIGITAL1, std::set<u32>{},
                              CELL_PAD_CTRL_PS);

  pad->m_sticks[0] = AnalogStick(CELL_PAD_BTN_OFFSET_ANALOG_LEFT_X, {}, {});
  pad->m_sticks[1] = AnalogStick(CELL_PAD_BTN_OFFSET_ANALOG_LEFT_Y, {}, {});
  pad->m_sticks[2] = AnalogStick(CELL_PAD_BTN_OFFSET_ANALOG_RIGHT_X, {}, {});
  pad->m_sticks[3] = AnalogStick(CELL_PAD_BTN_OFFSET_ANALOG_RIGHT_Y, {}, {});

  pad->m_sensors[0] =
      AnalogSensor(CELL_PAD_BTN_OFFSET_SENSOR_X, 0, 0, 0, DEFAULT_MOTION_X);
  pad->m_sensors[1] =
      AnalogSensor(CELL_PAD_BTN_OFFSET_SENSOR_Y, 0, 0, 0, DEFAULT_MOTION_Y);
  pad->m_sensors[2] =
      AnalogSensor(CELL_PAD_BTN_OFFSET_SENSOR_Z, 0, 0, 0, DEFAULT_MOTION_Z);
  pad->m_sensors[3] =
      AnalogSensor(CELL_PAD_BTN_OFFSET_SENSOR_G, 0, 0, 0, DEFAULT_MOTION_G);

  pad->m_vibrateMotors[0] = VibrateMotor(true, 0);
  pad->m_vibrateMotors[1] = VibrateMotor(false, 0);

  if (pad->m_player_id == 0) {
    std::lock_guard lock(g_virtual_pad_mutex);
    g_virtual_pad = pad;
  }
  return true;
}

extern "C" bool _rpcsx_overlayPadData(int digital1, int digital2,
                                      int leftStickX, int leftStickY,
                                      int rightStickX, int rightStickY) {

  auto pad = [] {
    std::shared_ptr<Pad> result;
    std::lock_guard lock(g_virtual_pad_mutex);
    result = g_virtual_pad;
    return result;
  }();

  if (pad == nullptr) {
    return false;
  }

  for (auto &btn : pad->m_buttons) {
    if (btn.m_offset == CELL_PAD_BTN_OFFSET_DIGITAL1) {
      btn.m_pressed = (digital1 & btn.m_outKeyCode) != 0;

      if (btn.m_outKeyCode == CELL_PAD_CTRL_PS && btn.m_pressed) {
        if (auto padThread = pad::get_pad_thread(true)) {
          padThread->open_home_menu();
        }
      }

    } else if (btn.m_offset == CELL_PAD_BTN_OFFSET_DIGITAL2) {
      btn.m_pressed = (digital2 & btn.m_outKeyCode) != 0;
    }

    btn.m_value = btn.m_pressed ? 255 : 0;
  }

  {
    static std::atomic<u64> s_last{0};
    char v[PROP_VALUE_MAX]{};
    if (__system_property_get("debug.rpcsx.thor.pad_probe", v) > 0 && v[0] && v[0] != '0') {
      const u64 now = get_system_time();
      u64 last = s_last.load();
      if (now - last > 1000000 && s_last.compare_exchange_strong(last, now)) {
        rpcsx_android.error("Thor pad probe WRITE: pad=%p d1=0x%04x d2=0x%04x player=%u",
          static_cast<const void*>(pad.get()), digital1, digital2, pad->m_player_id);
      }
    }
  }

  pad->m_sticks[0].m_value = leftStickX;
  pad->m_sticks[1].m_value = leftStickY;
  pad->m_sticks[2].m_value = rightStickX;
  pad->m_sticks[3].m_value = rightStickY;
  return true;
}

extern "C" bool _rpcsx_initialize(std::string_view rootDir,
                                  std::string_view user) {
  auto rootDirStr = fix_dir_path(std::string(rootDir));

  if (g_android_executable_dir != rootDirStr) {
    g_android_executable_dir = rootDirStr;
    g_android_config_dir = rootDirStr + "config/";
    g_android_cache_dir = rootDirStr + "cache/";

    std::filesystem::create_directories(g_android_config_dir);
    std::error_code ec;
    // std::filesystem::remove_all(g_android_cache_dir, ec);
    std::filesystem::create_directories(g_android_cache_dir);
  }

  if (g_initialized) {
    return true;
  }

  g_initialized = true;

#ifdef ARCH_ARM64
  // Records this device's generic-timer frequency for diagnostics. busy_wait
  // deliberately does NOT apply the scale on this fork; see the note in
  // rx/asm.hpp for why.
  rx::init_arm_timer_scale();
#endif

  if (int r = libusb_set_option(nullptr, LIBUSB_OPTION_NO_DEVICE_DISCOVERY,
                                nullptr);
      r != 0) {
    rpcsx_android.warning(
        "libusb_set_option(LIBUSB_OPTION_NO_DEVICE_DISCOVERY) -> %d", r);
  }

  // Initialize thread pool finalizer // ???
  static_cast<void>(named_thread("", [](int) {}));

  static std::unique_ptr<logs::listener> log_file;
  {
    // Check free space
    fs::device_stat stats{};
    if (!fs::statfs(fs::get_cache_dir(), stats) ||
        stats.avail_free < 128 * 1024 * 1024) {
      std::fprintf(stderr, "Not enough free space for logs (%f KB)",
                   stats.avail_free / 1000000.);
    }

    // preserve old log file
    if (std::filesystem::exists(fs::get_log_dir() + "RPCSX.log")) {
      std::error_code ec;
      std::filesystem::remove(fs::get_log_dir() + "RPCSX.old.log", ec);
      std::filesystem::rename(fs::get_log_dir() + "RPCSX.log",
                              fs::get_log_dir() + "RPCSX.old.log", ec);
    }

    // Limit log size to ~25% of free space
    log_file = logs::make_file_listener(fs::get_log_dir() + "RPCSX.log",
                                        stats.avail_free / 4);
  }

  logs::stored_message ver{rpcsx_android.always()};
  ver.text = fmt::format("RPCSX-ps3-android v%s", rx::getVersion().toString());

  // Write System information
  logs::stored_message sys{rpcsx_android.always()};
  sys.text = utils::get_system_info();

  // Write OS version
  logs::stored_message os{rpcsx_android.always()};
  os.text = utils::get_OS_version_string();

  // Write current time
  logs::stored_message time{rpcsx_android.always()};
  time.text = fmt::format("Current Time: %s", std::chrono::system_clock::now());

  logs::set_init(
      {std::move(ver), std::move(sys), std::move(os), std::move(time)});

  auto set_rlim = [](int resource, std::uint64_t limit) {
    rlimit64 rlim{};
    if (getrlimit64(resource, &rlim) != 0) {
      rpcsx_android.error("failed to get rlimit for %d", resource);
      return;
    }

    rlim.rlim_cur = std::min<std::size_t>(rlim.rlim_max, limit);
    rpcsx_android.error("rlimit[%d] = %u (requested %u, max %u)", resource,
                        rlim.rlim_cur, limit, rlim.rlim_max);

    if (setrlimit64(resource, &rlim) != 0) {
      rpcsx_android.error("failed to set rlimit for %d", resource);
      return;
    }
  };

  set_rlim(RLIMIT_MEMLOCK, RLIM_INFINITY);
  set_rlim(RLIMIT_NOFILE, RLIM_INFINITY);
  set_rlim(RLIMIT_STACK, 128 * 1024 * 1024);
  set_rlim(RLIMIT_AS, RLIM_INFINITY);

  virtual_pad_handler::set_on_connect_cb(initVirtualPad);
  setupCallbacks();
  Emu.SetHasGui(false);
  Emu.SetUsr(std::string(user));
  Emu.Init();

  g_cfg_input.player1.handler.set(pad_handler::virtual_pad);
  g_cfg_input.player1.device.from_string("Virtual");
  g_cfg_input.save("", g_cfg_input_configs.default_config);

  Emulator::SaveSettings(g_cfg.to_string(), Emu.GetTitleID());
  return true;
}

extern "C" bool _rpcsx_processCompilationQueue(JNIEnv *env) {
  g_compilationQueue.process(env);
  return true;
}

extern "C" bool _rpcsx_preparePpuCache(JNIEnv *env, std::string_view path,
                                       std::string_view titleId,
                                       long progressId) {
  return g_compilationQueue.prepare(env, std::string(path),
                                    std::string(titleId), progressId);
}

extern "C" bool _rpcsx_startMainThreadProcessor(JNIEnv *env) {
  g_mainThreadProcessor.process(env);
  return true;
}

extern "C" u64 _rpcsx_syncLogs() {
  static std::atomic<u64> sequence{0};
  const u64 checkpoint = sequence.fetch_add(1, std::memory_order_relaxed) + 1;
  rpcsx_android.always()("Thor debug log sync checkpoint: %u.", checkpoint);
  logs::listener::sync_all();
  return checkpoint;
}

extern "C" bool _rpcsx_collectGameInfo(JNIEnv *env, std::string_view rootDir,
                                       long progressId) {

  if (std::filesystem::is_regular_file(g_cfg_vfs.get_dev_flash() +
                                       "/vsh/module/vsh.self")) {
    sendVshBootable(env, progressId);
  }

  collectGameInfo(env, progressId, {std::string(rootDir)});
  return true;
}

extern "C" void _rpcsx_shutdown() {
  g_thor_start_paused_ready.store(false, std::memory_order_release);
  Emu.Kill();
}

extern "C" int _rpcsx_boot(std::string_view path_) {
  g_thor_start_paused_ready.store(false, std::memory_order_release);
  const bool startPaused = android_property_enabled(
      "debug.rpcsx.thor.start_paused", false);

  Emu.SetForceBoot(!startPaused);
  Emu.SetPreventAutostart(startPaused);

  std::string path = std::string(path_);
  while (path.ends_with('/')) {
    path.pop_back();
  }

  const auto result = Emu.BootGame(path, "", false, cfg_mode::custom);
  if (startPaused) {
    if (result == game_boot_result::no_errors && Emu.IsReady()) {
      g_thor_start_paused_ready.store(true, std::memory_order_release);
      rpcsx_android.always()("Thor start-paused gate is ready.");
    }
  }

  return static_cast<int>(result);
}

extern "C" int _rpcsx_getState() {
  return static_cast<int>(Emu.GetStatus(false));
}
extern "C" void _rpcsx_noteHomeMenuExitGameSelected() {
  g_home_menu_exit_game_selected.store(true, std::memory_order_release);
}
extern "C" bool _rpcsx_consumeHomeMenuExitGameSelected() {
  return g_home_menu_exit_game_selected.exchange(false,
                                                 std::memory_order_acq_rel);
}
extern "C" void _rpcsx_kill() {
  g_thor_start_paused_ready.store(false, std::memory_order_release);
  Emu.Kill();
}
extern "C" void _rpcsx_resume() {
  if (g_thor_start_paused_ready.exchange(false,
                                         std::memory_order_acq_rel) &&
      Emu.IsReady()) {
    rpcsx_android.always()("Thor start-paused gate released.");
    Emu.Run(true);
    return;
  }

  Emu.Resume();
}

extern "C" void _rpcsx_openHomeMenu() {
  // Named so a log can tell this apart from the other two ways the menu opens:
  // the PS button in the pad data, and a surface-destroy event. The third is the
  // only one that used to leave a trace.
  rpcsx_android.warning("home menu requested over JNI");
  if (auto padThread = pad::get_pad_thread(true)) {
    padThread->open_home_menu();
  }
}

static bool rpcsx_set_fast_forward_enabled(bool enabled) {
  if (enabled) {
    const bool wasEnabled = g_thor_fast_forward_enabled.exchange(true);
    if (!wasEnabled) {
      const int previousScale = g_cfg.core.clocks_scale.get();
      g_thor_fast_forward_previous_clocks_scale.store(previousScale);
      rpcsx_android.notice("Thor fast forward speedhack enabled: Clocks scale %d -> %d",
                           previousScale, k_thor_fast_forward_clocks_scale);
    }

    g_cfg.core.clocks_scale.set(k_thor_fast_forward_clocks_scale);
  } else {
    const bool wasEnabled = g_thor_fast_forward_enabled.exchange(false);
    if (wasEnabled) {
      const int previousScale = g_thor_fast_forward_previous_clocks_scale.load();
      g_cfg.core.clocks_scale.set(previousScale);
      rpcsx_android.notice("Thor fast forward speedhack disabled: Clocks scale restored to %d",
                           previousScale);
    }
  }

  return g_thor_fast_forward_enabled.load();
}

extern "C" bool _rpcsx_isFastForwardEnabled() {
  return g_thor_fast_forward_enabled.load();
}

extern "C" bool _rpcsx_setFastForwardEnabled(bool enabled) {
  return rpcsx_set_fast_forward_enabled(enabled);
}

extern "C" bool _rpcsx_toggleFastForward() {
  return rpcsx_set_fast_forward_enabled(!g_thor_fast_forward_enabled.load());
}

static bool rpcsx_can_use_savestate_hotkey() {
  return !Emu.GetTitleID().empty() &&
         (Emu.IsRunning() || Emu.GetStatus(false) == system_state::paused);
}

extern "C" bool _rpcsx_saveState() {
  if (!rpcsx_can_use_savestate_hotkey()) {
    rpcsx_android.warning("Thor hotkey save state ignored: emulator is not running a title");
    return false;
  }

  rpcsx_android.notice("Thor hotkey save state requested");
  Emu.CallFromMainThread([]() {
    if (g_cfg.savestate.suspend_emu.get()) {
      rpcsx_android.notice("Thor hotkey save state: forcing continuous savestate mode");
      g_cfg.savestate.suspend_emu.set(false);
    }

    Emu.after_kill_callback = []() { Emu.Restart(); };
    Emu.SetContinuousMode(true);
    Emu.Kill(false, true);
  });

  return true;
}

extern "C" bool _rpcsx_loadState() {
  if (!boot_last_savestate(true)) {
    rpcsx_android.warning("Thor hotkey load state ignored: no compatible savestate");
    return false;
  }

  rpcsx_android.notice("Thor hotkey load state requested");
  Emu.CallFromMainThread([]() { boot_last_savestate(false); });
  return true;
}

extern "C" std::string _rpcsx_getTitleId() { return Emu.GetTitleID(); }

// Tell a caller whether the guest is playing a movie. See
// Emu/thor_playback_probe.h for what this does and does not detect.
// Everything a tool needs to run an experiment here: heat, throttling,
// power, speed, and the REACH counters for the levers this fork ships.
//
// The counters matter as much as the speed. A lever with no reach and a lever
// with no effect produce the same number, and this project wrote off the SPU
// self-loop park twice on a scene where its counter reads entries=0. Reading
// reach directly beats grepping a log for it.
// Compile progress, the config ACTUALLY in effect, and live SPURS state.
//
// Each answers a question that has cost this project real time.
//
// PROGRESS ends fixed sleeps. "A fixed sleep is not a deterministic workload":
// boot time varies by tens of seconds, a cold PPU precompile can take ten
// minutes, and an arm that samples into a compile measures the compile.
//
// CONFIG ends an arm that never applied its lever. A harness here fed a spec
// into `printf | while read`, which drops the only line, so EVERY arm ran unset
// and the two arms agreed perfectly. Read the lever back before believing it.
//
// SPURS is the open bug. The limiter's state was only ever read after a fault.
// The EFFECTIVE value, not the config value. Defined in Emu/Cell/SPUThread.cpp.
// /diag used to print the config here, which reported "true" through runs that
// were running with the debug.rpcsx.thor override set to 0.
bool thor_spu_accurate_reservations_effective() noexcept;

extern "C" std::string _rpcsx_diagInfo() {
  std::string spurs = "[]";
  {
    std::string items;
    idm::select<named_thread<spu_thread>>([&](u32, named_thread<spu_thread> &spu) {
      const auto group = spu.group;
      if (group == nullptr || spu.spurs_addr == 0) {
        return;
      }
      if (!items.empty()) {
        items += ",";
      }
      fmt::append(items,
                  R"({"index":%u,"pc":"0x%05x","spursAddr":"0x%08x","group":"%s",)"
                  R"("maxNum":%u,"maxRun":%u,"spursRunning":%u,"waited":%s,"enteredWait":%s})",
                  spu.index, spu.pc, spu.spurs_addr, group->name, group->max_num,
                  group->max_run, +group->spurs_running,
                  spu.spurs_waited ? "true" : "false",
                  spu.spurs_entered_wait ? "true" : "false");
    });
    if (!items.empty()) {
      spurs = "[" + items + "]";
    }
  }

  // progress_dialog_string_t converts to std::string; it has no load().
  std::string text = static_cast<std::string>(g_progr_text);
  // It goes into JSON, and it is emulator text rather than a literal.
  for (char &c : text) {
    if (c == '"' || c == 0x5c) { // 0x5c is a backslash
      c = ' ';
    }
  }

  return fmt::format(
      R"({"progress":{"filesDone":%u,"filesTotal":%u,"modulesDone":%u,"modulesTotal":%u,"text":"%s"},)"
      R"("config":{"rsxFifoAccuracy":"%s","accurateSpuReservations":"%s","spuBlockSize":"%s",)"
      R"("spuDecoder":"%s","frameLimit":"%s","shaderMode":"%s","driverWakeUpDelay":"%s"},)"
      R"("spurs":%s})",
      +g_progr_fdone, +g_progr_ftotal, +g_progr_pdone, +g_progr_ptotal,
      text,
      g_cfg.core.rsx_fifo_accuracy.to_string(),
      thor_spu_accurate_reservations_effective() ? "true" : "false",
      g_cfg.core.spu_block_size.to_string(),
      g_cfg.core.spu_decoder.to_string(),
      g_cfg.video.frame_limit.to_string(),
      g_cfg.video.shadermode.to_string(),
      g_cfg.video.driver_wakeup_delay.to_string(),
      spurs);
}

extern "C" std::string _rpcsx_deviceInfo() {
  const u64 park_in = thor::g_spu_selfloop_park.entries.load();
  const u64 park_out = thor::g_spu_selfloop_park.exits.load();

  return fmt::format(
      "{\"device\":%s,"
      "\"spuSelfLoopPark\":{\"entries\":%llu,\"exits\":%llu,\"parkedNow\":%llu,\"lastPc\":\"0x%05x\"},"
      "\"rsxFifo\":{\"idlePolls\":%llu,\"parks\":%llu},"
      "\"spuTrap\":{\"lastAddr\":\"0x%08x\",\"tripped\":%s}}",
      thor::device_stats::to_json(), park_in, park_out, park_in - park_out,
      thor::g_spu_selfloop_park.last_pc.load(),
      thor::rsx_fifo::g_idle_polls.load(), thor::rsx_fifo::g_parks.load(),
      thor::g_spu_trap_addr.load(),
      thor::g_spu_trap_addr.load() ? "true" : "false");
}

// Pause and resume, so an experiment can STOP THE WORLD while it decides.
//
// Without this every screenshot races the scene: the picture is taken, the game
// keeps running, and by the time a button is pressed the screen has moved on.
// That is a contamination source, not a convenience. Pause, look, decide,
// resume, press.
extern "C" bool _rpcsx_pause() {
  if (g_thor_start_paused_ready.load(std::memory_order_acquire) &&
      Emu.IsReady()) {
    return true;
  }

  return Emu.Pause();
}
extern "C" bool _rpcsx_isPaused() {
  return (g_thor_start_paused_ready.load(std::memory_order_acquire) &&
          Emu.IsReady()) ||
         Emu.IsPaused();
}

extern "C" std::string _rpcsx_sceneInfo() {
  const u64 age = thor::vdec_age_us();
  const u32 open_files = thor::g_video_files_open.load();
  const auto name = thor::g_video_name.load();

  // Say WHICH source saw it. "movie" beside "vdecUnits: 0" looks like a
  // contradiction until you know the container is what was seen.
  const char *source = age < 500000 ? "cellVdec"
                       : open_files ? "open-video-file"
                                    : "none";

  return fmt::format(
      "{\"videoDecoding\":%s,\"source\":\"%s\",\"videoFilesOpen\":%u,"
      "\"videoFile\":\"%s\",\"vdecUnits\":%llu,\"vdecAgeMs\":%lld}",
      thor::video_playing() ? "true" : "false", source, open_files,
      name ? *name : std::string(),
      thor::g_vdec_units.load(),
      age == umax ? -1LL : static_cast<s64>(age / 1000));
}

extern "C" bool _rpcsx_surfaceEvent(JNIEnv *env, jobject surface, jint event) {
  rpcsx_android.warning("surface event %p, %d", surface, event);

  if (event == 2) {
    auto prevWindow = g_native_window.exchange(nullptr);
    if (prevWindow != nullptr) {
      ANativeWindow_release(prevWindow);
    }

    const system_state state = Emu.GetStatus(false);
    if (state != system_state::stopped && state != system_state::stopping) {
      if (auto padThread = pad::get_pad_thread(true)) {
        padThread->open_home_menu();
      }

      Emu.Pause();
    }
  } else {
    auto newWindow = ANativeWindow_fromSurface(env, surface);

    if (newWindow == nullptr) {
      rpcsx_android.fatal("returned native window is null, surface %p",
                          surface);
      return false;
    }

    // ANativeWindow_fromSurface returns a reference WE OWN and must release.
    // g_native_window keeps exactly one reference to whatever it holds:
    //
    //   same window -> it already owns one, so drop the one we were just handed.
    //   new window  -> hand ours over, and drop the reference to the old one.
    //
    // The previous code treated the fromSurface reference as borrowed and acquired
    // a SECOND one on top of it. A changed window therefore leaked one reference,
    // and an identical window skipped the block entirely and leaked the fromSurface
    // reference outright. Bounded before, because the surface rarely changed - and
    // the exact reason re-delivering it was unsafe, since re-delivery is by
    // definition the identical-window path and would have leaked once per delivery.
    //
    // getNativeWindow() keeps its own separate reference for activeNativeWindow and
    // is already balanced, so the window survives this release either way.
    auto prevWindow = g_native_window.exchange(newWindow);

    if (newWindow == prevWindow) {
      ANativeWindow_release(newWindow);
    } else if (prevWindow != nullptr) {
      ANativeWindow_release(prevWindow);
    }

    if (event == 0 && Emu.IsPaused()) {
      Emu.Resume();
    }
  }

  return true;
}

extern "C" bool _rpcsx_usbDeviceEvent(int fd, int vendorId, int productId,
                                      int event) {
  rpcsx_android.warning(
      "usb device event %d fd: %d, vendorId: %d, productId: %d", event, fd,
      vendorId, productId);

  {
    std::lock_guard lock(g_android_usb_devices_mutex);

    if (event == 0) {
      g_android_usb_devices.push_back({
          .fd = int(fd),
          .vendorId = u16(vendorId),
          .productId = u16(productId),
      });
    } else {
      auto filter = [fd](auto device) { return device.fd == fd; };
      if (auto it = std::ranges::find_if(g_android_usb_devices, filter);
          it != g_android_usb_devices.end()) {
        g_android_usb_devices.erase(it);
      }
    }
  }

  {
    auto selectedHandler = g_cfg_input.player1.handler.get();
    std::string selectedDevice;

    std::map<pad_handler, std::pair<std::unique_ptr<PadHandlerBase>,
                                    std::vector<std::string>>>
        handlerToDevices;

    auto collectDevices = [&]<typename T>(T handler) {
      handler->Init();

      std::vector<std::string> devices;
      for (const auto &device : handler->list_connected_devices()) {
        devices.push_back(device.name);
      }

      auto type = handler->m_type;

      handlerToDevices[type] = std::pair{
          std::move(handler),
          std::move(devices),
      };
    };

    collectDevices(std::make_unique<dualsense_pad_handler>());
    collectDevices(std::make_unique<ds4_pad_handler>());
    collectDevices(std::make_unique<ds3_pad_handler>());

    if (handlerToDevices[selectedHandler].second.empty()) {
      selectedHandler = pad_handler::null;
    }

    if (!handlerToDevices[pad_handler::dualsense].second.empty()) {
      selectedHandler = pad_handler::dualsense;
    } else if (!handlerToDevices[pad_handler::ds4].second.empty()) {
      selectedHandler = pad_handler::ds4;
    } else if (!handlerToDevices[pad_handler::ds3].second.empty()) {
      selectedHandler = pad_handler::ds3;
    }

    if (selectedHandler == pad_handler::null) {
      selectedHandler = pad_handler::virtual_pad;
    }

    if (selectedHandler != g_cfg_input.player1.handler.get()) {
      rpcsx_android.warning("install %s pad handler", selectedHandler);

      g_cfg_input.player1.handler.set(selectedHandler);

      if (selectedHandler == pad_handler::null) {
        g_cfg_input.player1.device.from_default();
      } else if (selectedHandler == pad_handler::virtual_pad) {
        g_cfg_input.player1.handler.set(pad_handler::virtual_pad);
        g_cfg_input.player1.device.from_string("Virtual");
      } else {
        g_cfg_input.player1.device.from_string(
            handlerToDevices[selectedHandler].second.front());
        handlerToDevices[selectedHandler].first->init_config(
            &g_cfg_input.player1.config);
        if (selectedHandler != pad_handler::virtual_pad) {
          std::lock_guard lock(g_virtual_pad_mutex);
          g_virtual_pad = nullptr;
        }
      }

      g_cfg_input.save("", g_cfg_input_configs.default_config);

      if (!Emu.IsStopped()) {
        pad::reset(Emu.GetTitleID());
      }
    }
  }

  return true;
}

static bool installPup(JNIEnv *env, fs::file &&pup_f, jlong progressId) {
  Progress progress(env, progressId);

  pup_object pup(std::move(pup_f));
  AtExit atExit{[&] { pup.file().release_handle(); }};

  if (static_cast<pup_error>(pup) == pup_error::hash_mismatch) {
    rpcsx_android.fatal("installFw: invalid PUP");
    progress.failure("Selected file is not firmware update file");
    return false;
  }

  if (static_cast<pup_error>(pup) != pup_error::ok) {
    rpcsx_android.fatal("installFw: invalid PUP");
    progress.failure("Firmware update file is broken");
    return false;
  }

  fs::file update_files_f = pup.get_file(0x300);

  const usz update_files_size = update_files_f ? update_files_f.size() : 0;

  if (!update_files_size) {
    rpcsx_android.fatal("installFw: invalid PUP");
    progress.failure("Firmware update file is broken");
    return false;
  }

  tar_object update_files(update_files_f);

  auto update_filenames = update_files.get_filenames();
  update_filenames.erase(std::remove_if(update_filenames.begin(),
                                        update_filenames.end(),
                                        [](const std::string &s) {
                                          return !s.starts_with("dev_flash_");
                                        }),
                         update_filenames.end());

  if (update_filenames.empty()) {
    rpcsx_android.fatal("installFw: invalid PUP");
    progress.failure("Firmware update file is broken");
    return false;
  }

  std::string version_string;

  if (fs::file version = pup.get_file(0x100)) {
    version_string = version.to_string();
  }

  if (const usz version_pos = version_string.find('\n');
      version_pos != std::string::npos) {
    version_string.erase(version_pos);
  }

  if (version_string.empty()) {
    rpcsx_android.fatal("installFw: invalid PUP");
    progress.failure("Firmware update file is broken");
    return false;
  }

  sendVshBootable(env, progressId);

  jlong processed = 0;
  for (const auto &update_filename : update_filenames) {
    auto update_file_stream = update_files.get_file(update_filename);

    if (update_file_stream->m_file_handler) {
      // Forcefully read all the data
      update_file_stream->m_file_handler->handle_file_op(
          *update_file_stream, 0, update_file_stream->get_size(umax), nullptr);
    }

    fs::file update_file = fs::make_stream(std::move(update_file_stream->data));

    SCEDecrypter self_dec(update_file);
    self_dec.LoadHeaders();
    self_dec.LoadMetadata(SCEPKG_ERK, SCEPKG_RIV);
    self_dec.DecryptData();

    auto dev_flash_tar_f = self_dec.MakeFile();

    if (dev_flash_tar_f.size() < 3) {
      rpcsx_android.error(
          "Firmware installation failed: Firmware could not be decompressed");

      progress.failure("Firmware update file could not be decompressed");
      return false;
    }

    tar_object dev_flash_tar(dev_flash_tar_f[2]);

    if (!dev_flash_tar.extract()) {

      rpcsx_android.error("Error while installing firmware: TAR contents are "
                          "invalid. (package=%s)",
                          update_filename);

      progress.failure(fmt::format("TAR contents are invalid (package=%s)",
                                   update_filename));
      return false;
    }

    if (!progress.report(processed++, update_filenames.size())) {
      // Installation was cancelled
      return false;
    }
  }

  sendFirmwareInstalled(env, utils::get_firmware_version());

  g_compilationQueue.push(progress,
                          g_cfg_vfs.get_dev_flash() + "/vsh/module/vsh.self");
  return true;
}

static bool installPkg(JNIEnv *env, fs::file &&file, jlong progressId) {
  Progress progress(env, progressId);

  std::deque<package_reader> readers;
  std::deque<std::string> bootable_paths;
  readers.emplace_back("dummy.pkg", std::move(file));

  AtExit atExit{[&] {
    for (auto &reader : readers) {
      reader.file().release_handle();
    }
  }};

  package_install_result result = {};
  named_thread worker("PKG Installer", [&readers, &result, &bootable_paths] {
    result = package_reader::extract_data(readers, bootable_paths);
    return result.error == package_install_result::error_type::no_error;
  });

  for (auto &reader : readers) {
    if (auto gameInfo = fetchGameInfo(reader.get_psf())) {
      sendGameInfo(env, progressId, {{*gameInfo}});
    }
  }

  const jlong maxProgress = 10000;

  while (true) {
    std::uint64_t totalProgress = 0;
    for (auto &reader : readers) {
      if (result.error != package_install_result::error_type::no_error) {
        progress.failure("Installation failed");
        for (package_reader &reader : readers) {
          reader.abort_extract();
        }
        return false;
      }

      totalProgress += reader.get_progress(maxProgress);
    }

    if (totalProgress == maxProgress * readers.size()) {
      break;
    }

    totalProgress /= readers.size();

    if (!progress.report(totalProgress, maxProgress)) {
      for (package_reader &reader : readers) {
        reader.abort_extract();
      }

      return false;
    }

    std::this_thread::sleep_for(std::chrono::seconds(2));
  }

  if (worker()) {
    auto paths = std::vector(bootable_paths.begin(), bootable_paths.end());
    collectGameInfo(env, -1, paths);

    for (auto &path : paths) {
      g_compilationQueue.push(progress, std::move(path));
    }
  }

  return true;
}

static bool installEdat(JNIEnv *env, fs::file &&file, jlong progressId,
                        std::string_view rootPath = {}) {
  Progress progress(env, progressId);

  NPD_HEADER npdHeader;
  if (!file.read(npdHeader)) {
    progress.failure("Invalid EDAT file");
    return false;
  }

  if (!rootPath.empty()) {
    auto ebootPath = locateEbootPath(rootPath);
    auto sfoPath = locateParamSfoPath(rootPath);

    if (sfoPath.empty()) {
      progress.failure("Game is broken: PARAM.SFO not found");
      return false;
    }

    auto psf = psf::load_object(sfoPath);
    auto contentId = psf::get_string(psf, "CONTENT_ID");

    if (contentId != npdHeader.content_id) {
      progress.failure(fmt::format("File cannot be used for this game. EDAT "
                                   "content ID missmatch %s vs %s",
                                   contentId, npdHeader.content_id));
      return false;
    }
  }

  const auto licenseFile =
      fmt::format("%shome/%s/exdata/%s.edat", rpcs3::utils::get_hdd0_dir(),
                  Emu.GetUsr(), npdHeader.content_id);

  file.seek(0);

  std::vector<std::uint8_t> bytes(file.size());
  if (!file.read(bytes)) {
    progress.failure("Failed to read key");
    return false;
  }

  if (!fs::write_file(licenseFile, fs::open_mode::create + fs::open_mode::trunc,
                      bytes)) {
    progress.failure(fmt::format("Failed to write EDAT to %s", licenseFile));
    return false;
  }

  auto root = std::string(rootPath);

  if (root.empty()) {
    root = rpcs3::utils::get_hdd0_dir() + "game";
  }

  collectGameInfo(env, progressId, {std::move(root)});
  return true;
}

static bool installRap(JNIEnv *env, fs::file &&file, jlong progressId,
                       std::string_view rootPath) {
  Progress progress(env, progressId);

  auto ebootPath = locateEbootPath(rootPath);

  std::vector<std::uint8_t> bytes;
  if (!file.read(bytes, 16)) {
    progress.failure("Failed to read key");
    return false;
  }

  SelfAdditionalInfo info;
  decrypt_self(fs::file(ebootPath), nullptr, &info);

  auto npd = [&]() -> NPD_HEADER * {
    for (auto &supplemental : info.supplemental_hdr) {
      if (supplemental.type == 3) {
        return &supplemental.PS3_npdrm_header.npd;
      }
    }

    return nullptr;
  }();

  if (npd == nullptr) {
    progress.failure("Failed to fetch NPDRM of SELF");
    return false;
  }

  const auto licenseFile =
      fmt::format("%shome/%s/exdata/%s.rap", rpcs3::utils::get_hdd0_dir(),
                  Emu.GetUsr(), npd->content_id);

  if (!fs::write_file(licenseFile, fs::open_mode::create + fs::open_mode::trunc,
                      bytes)) {
    progress.failure(fmt::format("Failed to write key to %s", licenseFile));
    return false;
  }

  if (!decrypt_self(fs::file(ebootPath))) {
    progress.failure("Provided key is invalid for selected game");
    fs::remove_file(licenseFile);
    return false;
  }

  collectGameInfo(env, -1, {std::string(rootPath)});
  g_compilationQueue.push(progress, std::move(ebootPath));
  return true;
}

static bool copyFileStreamed(const fs::file &source,
                             const std::filesystem::path &destinationPath,
                             std::string &errorMessage) {
  fs::file destination(destinationPath.string(),
                       fs::create | fs::trunc | fs::write);

  if (!destination) {
    errorMessage = fmt::format("Failed to open output file: %s",
                               destinationPath.string());
    return false;
  }

  constexpr u64 copyBufferSize = 1024 * 1024;
  std::vector<std::uint8_t> buffer(copyBufferSize);
  const u64 totalSize = source.size();
  u64 copied = 0;

  while (copied < totalSize) {
    const u64 wanted = std::min<u64>(buffer.size(), totalSize - copied);
    const u64 read = source.read_at(copied, buffer.data(), wanted);

    if (read == 0) {
      errorMessage = fmt::format("Short read while copying %s at 0x%llx",
                                 destinationPath.string(), copied);
      return false;
    }

    if (destination.write(buffer.data(), read) != read) {
      errorMessage =
          fmt::format("Short write while copying %s", destinationPath.string());
      return false;
    }

    copied += read;
  }

  return true;
}

static bool installIso(JNIEnv *env, fs::file &&file, jlong progressId) {
  auto optIso = iso_dev::open(std::make_unique<file_view_block_dev>(file));
  Progress progress(env, progressId);

  if (!optIso) {
    progress.failure("Failed to read ISO");
    return false;
  }

  auto iso = std::move(*optIso);
  auto sfo_raw_file = iso.open("PS3_GAME/PARAM.SFO", fs::read);

  if (!sfo_raw_file) {
    progress.failure("Failed to locate PARAM.SFO in ISO");
    return false;
  }

  fs::file sfo_file;
  sfo_file.reset(std::move(sfo_raw_file));

  auto sfo = psf::load_object(sfo_file, "iso://PS3_GAME/PARAM.SFO");
  auto title_id = psf::get_string(sfo, "TITLE_ID");

  if (title_id.empty()) {
    progress.failure("Failed to fetch TITLE_ID from PARAM.SFO in ISO");
    return false;
  }

  if (auto gameInfo = fetchGameInfo(sfo)) {
    sendGameInfo(env, progressId, {{*gameInfo}});
  }

  std::filesystem::path destinationPath =
      fs::get_config_dir() + "games/" + std::string(title_id);
  std::size_t filesCount = 0;

  auto roots = [&] {
    std::vector<std::filesystem::path> result;
    std::vector<std::filesystem::path> workList;
    workList.push_back({});
    result.push_back({});

    while (!workList.empty()) {
      auto path = std::move(workList.back());
      workList.pop_back();

      fs::dir dir;
      dir.reset(iso.open_dir(path));

      for (auto &entry : dir) {
        if (entry.name == "." || entry.name == "..") {
          continue;
        }
        if (entry.name == "PS3_UPDATE" && path.empty()) {
          continue;
        }

        if (entry.is_directory) {
          result.push_back(path / entry.name);
          workList.push_back(path / entry.name);
        } else {
          filesCount++;
        }
      }
    }

    return result;
  }();

  progress.report(0, filesCount);

  std::size_t processedFiles = 0;
  std::error_code ec;

  for (auto &root : roots) {
    auto rootDestPath = root.empty() ? destinationPath : destinationPath / root;

    std::filesystem::create_directories(rootDestPath, ec);
    if (ec) {
      progress.failure(fmt::format("Failed to create dir %s: %s",
                                   rootDestPath.string(), ec.message()));
      return false;
    }

    fs::dir dir;
    dir.reset(iso.open_dir(root));

    for (auto &entry : dir) {
      if (entry.name == "." || entry.name == "..") {
        continue;
      }

      auto entryDestPath = rootDestPath / entry.name;

      if (entry.is_directory) {
        std::filesystem::create_directories(entryDestPath, ec);
        if (ec) {
          progress.failure(fmt::format("Failed to create dir %s: %s",
                                       entryDestPath.string(), ec.message()));
          return false;
        }

        continue;
      }
      auto raw_file = iso.open(root / entry.name, fs::read);

      if (!raw_file) {
        progress.failure(fmt::format("Failed to open file in ISO: %s",
                                     (root / entry.name).string()));
        return false;
      }

      fs::file file;
      file.reset(std::move(raw_file));

      std::string copyError;
      if (!copyFileStreamed(file, entryDestPath, copyError)) {
        progress.failure(copyError.empty()
                             ? fmt::format("Failed to copy file: %s, dest %s",
                                           entryDestPath.string(),
                                           destinationPath.string())
                             : copyError);
        return false;
      }

      progress.report(processedFiles++, filesCount);
    }
  }

  collectGameInfo(env, -1, {destinationPath});
  auto ebootPath = locateEbootPath(destinationPath.string());
  g_compilationQueue.push(progress, std::move(ebootPath));
  return true;
}

extern "C" bool _rpcsx_installFw(JNIEnv *env, int fd, long progressId) {
  return installPup(env, fs::file::from_native_handle(fd), progressId);
}

extern "C" bool _rpcsx_isInstallableFile(jint fd) {
  auto file = fs::file::from_native_handle(fd);
  AtExit atExit{[&] { file.release_handle(); }};

  auto type = getFileType(file);
  file.seek(0);
  return type != FileType::Unknown &&
         type != FileType::Rap; // FIXME: implement rap preinstallation
}

extern "C" jstring _rpcsx_getDirInstallPath(JNIEnv *env, jint fd) {
  auto file = fs::file::from_native_handle(fd);
  AtExit atExit{[&] { file.release_handle(); }};

  auto psf = psf::load_object(file, "");
  if (auto gameInfo = fetchGameInfo(psf)) {
    return wrap(env, gameInfo->path);
  }

  return nullptr;
}

extern "C" bool _rpcsx_install(JNIEnv *env, int fd, long progressId) {
  auto file = fs::file::from_native_handle(fd);
  AtExit atExit{[&] { file.release_handle(); }};

  auto type = getFileType(file);
  file.seek(0);

  switch (type) {
  case FileType::Unknown:
    Progress(env, progressId).failure("Unsupported file type");
    return false;

  case FileType::Pup:
    return installPup(env, std::move(file), progressId);

  case FileType::Pkg:
    return installPkg(env, std::move(file), progressId);

  case FileType::Edat:
    return installEdat(env, std::move(file), progressId);

  case FileType::Iso:
    return installIso(env, std::move(file), progressId);

  case FileType::Rap:
    Progress(env, progressId)
        .failure("RAP file cannot be preinstalled. Use lock button on "
                 "installed game instead");
    return false;
  }

  return true;
}

extern "C" bool _rpcsx_installKey(JNIEnv *env, int fd, long progressId,
                                  std::string_view gamePath) {
  auto file = fs::file::from_native_handle(fd);
  AtExit atExit{[&] { file.release_handle(); }};

  auto type = getFileType(file);
  file.seek(0);

  if (type == FileType::Rap) {
    return installRap(env, std::move(file), progressId, gamePath);
  }

  if (type == FileType::Edat) {
    return installEdat(env, std::move(file), progressId, gamePath);
  }

  Progress(env, progressId).failure("Unsupported key type");
  return false;
}

extern "C" std::string _rpcsx_systemInfo() {
  std::string result;

  fmt::append(result, "%s\n\n", utils::get_system_info());
  append_thor_feature_doctor(result);

  {
    vk::instance device_enum_context;
    if (device_enum_context.create("RPCS3")) {
      device_enum_context.bind();
      const std::vector<vk::physical_device> &gpus =
          device_enum_context.enumerate_devices();

      for (const auto &gpu : gpus) {
        fmt::append(result, "GPU: %s\n\nDriver: %s (v%s)\n\nVulkan: %s",
                    gpu.get_name(), gpu.get_driver_name(),
                    gpu.get_driver_version(), gpu.get_driver_vk_version());
      }
    }
  }

  return result;
}

static cfg::_base *find_cfg_node(cfg::_base *root, std::string_view path) {
  auto pathList = fmt::split(path, {"@@"});
  std::ranges::reverse(pathList);

  while (!pathList.empty()) {
    auto elem = pathList.back();
    pathList.pop_back();
    if (elem.empty()) {
      continue;
    }

    auto root_node = dynamic_cast<cfg::node *>(root);
    if (root_node == nullptr) {
      return nullptr;
    }

    cfg::_base *child_node = nullptr;

    for (auto node : root_node->get_nodes()) {
      if (node->get_name() == elem) {
        child_node = node;
        break;
      }
    }

    if (child_node == nullptr) {
      return nullptr;
    }

    root = child_node;
  }

  return root;
}

extern "C" void _rpcsx_loginUser(std::string_view userId) {
  Emu.SetUsr(std::string(userId));
}

extern "C" std::string _rpcsx_getUser() { return Emu.GetUsr(); }

extern "C" std::string _rpcsx_settingsGet(std::string_view path) {
  auto root = find_cfg_node(&g_cfg, path);

  if (root == nullptr) {
    return nullptr;
  }

  return root->to_json().dump(4);
}

extern "C" bool _rpcsx_settingsSet(std::string_view path,
                                   std::string_view valueString) {
  nlohmann::json value;
  try {
    value = nlohmann::json::parse(valueString);
  } catch (...) {
    rpcsx_android.error("settingsSet: node %s passed with invalid json '%s'",
                        path, valueString);
    return false;
  }

  auto root = find_cfg_node(&g_cfg, path);

  if (root == nullptr) {
    rpcsx_android.error("settingsSet: node %s not found", path);
    return false;
  }

  if (!root->from_json(value, !Emu.IsStopped())) {
    rpcsx_android.error("settingsSet: node %s not accepts value '%s'", path,
                        value.dump());
    return false;
  }

  Emulator::SaveSettings(g_cfg.to_string(), "");
  return true;
}

extern "C" std::string _rpcsx_getVersion() {
  return rx::getVersion().toString();
}

extern "C" void *_rpcsx_setCustomDriver(void *driverHandle) {
  auto prevLoader = vk::instance::g_vk_loader;
  if (prevLoader != nullptr) {
    vk::symbol_cache::cache_instance().clear();
  }

  vk::instance::g_vk_loader = driverHandle;

  if (driverHandle != nullptr) {
    vk::symbol_cache::cache_instance().initialize();
  }

  return prevLoader;
}

#pragma GCC diagnostic pop
