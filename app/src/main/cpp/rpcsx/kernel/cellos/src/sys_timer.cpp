#include "stdafx.h"

#include "sys_timer.h"
#include "thor_spurs_probe.h"

#include "Emu/Cell/ErrorCodes.h"
#include "Emu/Cell/PPUThread.h"
#include "Emu/Cell/timers.hpp"
#include "Emu/IdManager.h"
#include "Emu/Memory/vm.h"
#include "Emu/RSX/RSXThread.h"

#include "Emu/System.h"
#include "Emu/system_config.h"
#include "rx/asm.hpp"
#include "sys_event.h"
#include "sys_process.h"

#include <cstdlib>
#include <deque>
#include <string_view>
#include <thread>

#ifdef ANDROID
#include <sys/system_properties.h>
#endif

LOG_CHANNEL(sys_timer);

namespace {

constexpr u64 thor_es_frame_poll_wait_max_us = 1000;
constexpr u64 thor_es_frame_poll_handler_grace_us_default = 500;
constexpr u64 thor_es_frame_poll_log_probe_mask = 1023;

struct thor_es_frame_poll_wait_state {
  u32 ppu_id = 0;
  u32 object_addr = 0;
  u32 normal_pre_counter = 0;
  u64 completed_vblank = 0;
  u64 calls = 0;
  u64 event_waits = 0;
  u64 handler_wakes = 0;
  u64 handler_grace_waits = 0;
  u64 counter_progress_after_grace = 0;
  u64 vblank_wakes = 0;
  u64 timeouts = 0;
  u64 fallback_sleeps = 0;
  u64 fallback_rearms = 0;
  u64 continuous_rearms = 0;
  u64 continuous_rearm_timeouts = 0;
  u64 continuous_rearm_progress = 0;
  u64 counter_progress_after_event = 0;
  u64 last_log_us = 0;
  bool armed = false;
};

thor_es_frame_poll_wait_state g_thor_es_frame_poll_wait_state;

enum class thor_es_frame_poll_wait_result : u8 {
  not_candidate,
  normal_sleep_fast,
  normal_sleep_diagnostic,
  waited,
};

enum class thor_es_frame_poll_cached_bool : u8 {
  uninitialized,
  disabled,
  enabled,
};

atomic_t<thor_es_frame_poll_wait_mode> g_thor_es_frame_poll_wait_mode{
    thor_es_frame_poll_wait_mode::uninitialized};
atomic_t<thor_es_frame_poll_cached_bool>
    g_thor_es_frame_poll_continuous_rearm{
        thor_es_frame_poll_cached_bool::uninitialized};
atomic_t<u64> g_thor_es_frame_poll_handler_grace_us{u64{umax}};

thor_es_frame_poll_wait_mode
parse_thor_es_frame_poll_wait(std::string_view value) {
  if (value == "fast") {
    return thor_es_frame_poll_wait_mode::fast;
  }

  if (value == "1" || value == "on" || value == "true" ||
      value == "wait") {
    return thor_es_frame_poll_wait_mode::diagnostic;
  }

  return thor_es_frame_poll_wait_mode::off;
}

void set_thor_es_vblank_waiter_registered(atomic_t<bool> &registered,
                                          bool value) noexcept {
#ifdef __ANDROID__
  // This flag only gates optional producer work. Handler data is published
  // through vblank_wait_token, and a missed hint retains the 1 ms timeout.
  auto &raw = const_cast<uchar &>(registered.raw());
  __atomic_store_n(&raw, static_cast<uchar>(value), __ATOMIC_RELAXED);
#else
  registered.release(value);
#endif
}

u32 observe_thor_es_vblank_wait_token(
    const atomic_t<u32> &wait_token) noexcept {
#ifdef __ANDROID__
  // These pre-wait reads only gate a bounded wait. wait_on rechecks the token
  // against the expected value, while the post-wait acquire publishes handler
  // writes before the guest counter load.
  return wait_token.observe();
#else
  return wait_token;
#endif
}

NEVER_INLINE thor_es_frame_poll_wait_mode
initialize_thor_es_frame_poll_wait_mode() {
  const auto mode = [] {
#ifdef ANDROID
    char property_value[PROP_VALUE_MAX]{};
    const int property_length = __system_property_get(
        "debug.rpcsx.thor.es_frame_wait", property_value);
    if (property_length > 0) {
      return parse_thor_es_frame_poll_wait(
          std::string_view{property_value,
                           static_cast<usz>(property_length)});
    }
#endif

    if (const char *value = std::getenv("RPCSX_THOR_ES_FRAME_POLL_WAIT")) {
      return parse_thor_es_frame_poll_wait(value);
    }

    if (const char *value = std::getenv("RPCS3_ES_FRAME_POLL_WAIT")) {
      return parse_thor_es_frame_poll_wait(value);
    }

    return thor_es_frame_poll_wait_mode::off;
  }();

  // The cached value is self-contained, so hot readers only need a relaxed
  // load. A concurrent first reader can compute and publish the same immutable
  // process property without consuming any dependent state.
  g_thor_es_frame_poll_wait_mode.release(mode);
  return mode;
}

FORCE_INLINE thor_es_frame_poll_wait_mode
get_thor_es_frame_poll_wait_mode() {
  const auto mode = g_thor_es_frame_poll_wait_mode.observe();
  if (mode == thor_es_frame_poll_wait_mode::uninitialized) [[unlikely]] {
    return initialize_thor_es_frame_poll_wait_mode();
  }

  return mode;
}

bool parse_thor_es_frame_poll_continuous_rearm(std::string_view value) {
  return value == "1" || value == "on" || value == "true" ||
         value == "continuous";
}

NEVER_INLINE bool initialize_thor_es_frame_poll_continuous_rearm() {
  const bool enabled = [] {
#ifdef ANDROID
    char property_value[PROP_VALUE_MAX]{};
    const int property_length = __system_property_get(
        "debug.rpcsx.thor.es_frame_wait_continuous_rearm", property_value);
    if (property_length > 0) {
      return parse_thor_es_frame_poll_continuous_rearm(
          std::string_view{property_value,
                           static_cast<usz>(property_length)});
    }
#endif

    if (const char *value =
            std::getenv("RPCSX_THOR_ES_FRAME_POLL_CONTINUOUS_REARM")) {
      return parse_thor_es_frame_poll_continuous_rearm(value);
    }

    if (const char *value =
            std::getenv("RPCS3_ES_FRAME_POLL_CONTINUOUS_REARM")) {
      return parse_thor_es_frame_poll_continuous_rearm(value);
    }

    return false;
  }();

  g_thor_es_frame_poll_continuous_rearm.release(
      enabled ? thor_es_frame_poll_cached_bool::enabled
              : thor_es_frame_poll_cached_bool::disabled);
  return enabled;
}

FORCE_INLINE bool is_thor_es_frame_poll_continuous_rearm_enabled() {
  const auto cached = g_thor_es_frame_poll_continuous_rearm.observe();
  if (cached == thor_es_frame_poll_cached_bool::uninitialized) [[unlikely]] {
    return initialize_thor_es_frame_poll_continuous_rearm();
  }

  return cached == thor_es_frame_poll_cached_bool::enabled;
}

u64 parse_thor_es_frame_poll_handler_grace_us(const char *value) {
  if (!value || !*value || *value == '-') {
    return thor_es_frame_poll_handler_grace_us_default;
  }

  char *end = nullptr;
  const u64 parsed = std::strtoull(value, &end, 10);
  if (end == value || *end != '\0') {
    return thor_es_frame_poll_handler_grace_us_default;
  }

  return std::clamp<u64>(parsed, 0, 500);
}

NEVER_INLINE u64 initialize_thor_es_frame_poll_handler_grace_us() {
  const u64 grace_us = [] {
#ifdef ANDROID
    char property_value[PROP_VALUE_MAX]{};
    if (__system_property_get("debug.rpcsx.thor.es_frame_wait_grace_us",
                              property_value) > 0) {
      return parse_thor_es_frame_poll_handler_grace_us(property_value);
    }
#endif

    if (const char *value =
            std::getenv("RPCSX_THOR_ES_FRAME_POLL_HANDLER_GRACE_US")) {
      return parse_thor_es_frame_poll_handler_grace_us(value);
    }

    if (const char *value =
            std::getenv("RPCS3_ES_FRAME_POLL_HANDLER_GRACE_US")) {
      return parse_thor_es_frame_poll_handler_grace_us(value);
    }

    return thor_es_frame_poll_handler_grace_us_default;
  }();

  g_thor_es_frame_poll_handler_grace_us.release(grace_us);
  return grace_us;
}

FORCE_INLINE u64 get_thor_es_frame_poll_handler_grace_us() {
  const u64 grace_us = g_thor_es_frame_poll_handler_grace_us.observe();
  if (grace_us == u64{umax}) [[unlikely]] {
    return initialize_thor_es_frame_poll_handler_grace_us();
  }

  return grace_us;
}

bool should_probe_thor_es_frame_poll_log() noexcept {
  // Keep the first activation row, then enter the outlined logger only once
  // per 1024 calls before its existing wall-time throttle.
  const u64 calls = g_thor_es_frame_poll_wait_state.calls;
  return calls == 1 || (calls & thor_es_frame_poll_log_probe_mask) == 0;
}

void log_thor_es_frame_poll_wait(const ppu_thread &ppu, u32 counter,
                                 u32 threshold, u64 vblank) {
  auto &state = g_thor_es_frame_poll_wait_state;
  const u64 now = get_system_time();
  if (state.last_log_us && now - state.last_log_us < 5'000'000) {
    return;
  }

  state.last_log_us = now;
  sys_timer.notice(
      "Thor Eternal Sonata frame poll wait: ppu=0x%x object=0x%x "
      "counter=%u threshold=%u vblank=%llu armed=%u max_wait_us=%llu "
      "handler_grace_us=%llu continuous_rearm=%u "
      "calls=%llu event_waits=%llu handler_wakes=%llu "
      "handler_grace_waits=%llu counter_progress_after_grace=%llu "
      "vblank_wakes=%llu timeouts=%llu "
      "fallback_sleeps=%llu fallback_rearms=%llu "
      "continuous_rearms=%llu continuous_rearm_timeouts=%llu "
      "continuous_rearm_progress=%llu "
      "counter_progress_after_event=%llu",
      ppu.id, state.object_addr, counter, threshold, vblank, state.armed,
      thor_es_frame_poll_wait_max_us,
      get_thor_es_frame_poll_handler_grace_us(),
      is_thor_es_frame_poll_continuous_rearm_enabled(), state.calls,
      state.event_waits, state.handler_wakes, state.handler_grace_waits,
      state.counter_progress_after_grace, state.vblank_wakes, state.timeouts,
      state.fallback_sleeps, state.fallback_rearms,
      state.continuous_rearms, state.continuous_rearm_timeouts,
      state.continuous_rearm_progress,
      state.counter_progress_after_event);
}

template <bool TrackStats>
FORCE_INLINE thor_es_frame_poll_wait_result
try_thor_es_frame_poll_wait_impl(ppu_thread &ppu) {
  constexpr auto normal_sleep_result =
      TrackStats
          ? thor_es_frame_poll_wait_result::normal_sleep_diagnostic
          : thor_es_frame_poll_wait_result::normal_sleep_fast;
  const u32 object_addr = static_cast<u32>(ppu.gpr[28]);
  const u32 frame_config_addr = static_cast<u32>(ppu.gpr[31]);
  if (frame_config_addr != object_addr + 4 || !vm::check_addr(object_addr) ||
      !vm::check_addr(frame_config_addr + 0x260)) {
    return thor_es_frame_poll_wait_result::not_candidate;
  }

  const u8 divisor = vm::read8(frame_config_addr + 0x260);
  if (divisor != 30 && divisor != 60) {
    return thor_es_frame_poll_wait_result::not_candidate;
  }

  const u32 threshold = 60 / divisor;
  const u32 counter = vm::read32(object_addr);
  if (counter >= threshold) {
    return thor_es_frame_poll_wait_result::not_candidate;
  }

  const auto renderer = rsx::get_current_renderer();
  if (!renderer) {
    return thor_es_frame_poll_wait_result::not_candidate;
  }

  auto &state = g_thor_es_frame_poll_wait_state;
  if (state.ppu_id != ppu.id || state.object_addr != object_addr) {
    state = {};
    state.ppu_id = ppu.id;
    state.object_addr = object_addr;
  }

  if constexpr (TrackStats) {
    state.calls++;
  }
  const auto vblank = +renderer->vblank_count;
  if (!state.armed) {
    state.normal_pre_counter = counter;
    if constexpr (TrackStats) {
      state.fallback_sleeps++;
      if (should_probe_thor_es_frame_poll_log()) {
        log_thor_es_frame_poll_wait(ppu, counter, threshold, vblank);
      }
    }
    return normal_sleep_result;
  }

  [[maybe_unused]] bool continuous_rearmed = false;
  if (vblank != state.completed_vblank) {
    if (!is_thor_es_frame_poll_continuous_rearm_enabled()) {
      state.normal_pre_counter = counter;
      if constexpr (TrackStats) {
        state.fallback_sleeps++;
        if (should_probe_thor_es_frame_poll_log()) {
          log_thor_es_frame_poll_wait(ppu, counter, threshold, vblank);
        }
      }
      return normal_sleep_result;
    }

    // A completed normal sleep has already proven this exact
    // title/object/counter relation. Keep using the bounded VBlank-handler
    // completion wait instead of returning to repeated 100 us guest sleeps.
    state.completed_vblank = vblank;
    if constexpr (TrackStats) {
      state.continuous_rearms++;
      continuous_rearmed = true;
    }
  }

  if constexpr (TrackStats) {
    state.event_waits++;
  }
  // Wait for the queued guest VBlank handler to finish, not merely for the
  // raw VBlank edge. This keeps the counter load after the guest callback.
  // The portable 32-bit generation avoids a newer 64-bit wait dependency.
  const u32 wait_token =
      observe_thor_es_vblank_wait_token(renderer->vblank_wait_token);
  set_thor_es_vblank_waiter_registered(
      renderer->vblank_waiter_registered, true);
  if (observe_thor_es_vblank_wait_token(renderer->vblank_wait_token) ==
      wait_token) {
    thread_ctrl::wait_on(renderer->vblank_wait_token, wait_token,
                         thor_es_frame_poll_wait_max_us);
  }
  set_thor_es_vblank_waiter_registered(
      renderer->vblank_waiter_registered, false);

  const u32 after_wait_token = renderer->vblank_wait_token;
  u32 after_counter = vm::read32(object_addr);
  if (after_wait_token != wait_token) {
    if constexpr (TrackStats) {
      state.handler_wakes++;
    }
    [[maybe_unused]] bool waited_for_grace = false;
    const u64 handler_grace_us =
        after_counter == counter ? get_thor_es_frame_poll_handler_grace_us() : 0;
    for (u64 waited_us = 0;
         after_counter == counter &&
         waited_us < handler_grace_us;
         waited_us += 100) {
      thread_ctrl::wait_for(100);
      if constexpr (TrackStats) {
        waited_for_grace = true;
        state.handler_grace_waits++;
      }
      after_counter = vm::read32(object_addr);
    }

    if constexpr (TrackStats) {
      if (waited_for_grace && after_counter != counter) {
        state.counter_progress_after_grace++;
      }
    }
  } else {
    if constexpr (TrackStats) {
      state.timeouts++;
      if (continuous_rearmed) {
        state.continuous_rearm_timeouts++;
      }
    }
  }

  const auto after_vblank = +renderer->vblank_count;
  if constexpr (TrackStats) {
    if (after_vblank != vblank) {
      state.vblank_wakes++;
    }
  }

  if (after_counter != counter) {
    if constexpr (TrackStats) {
      state.counter_progress_after_event++;
      if (continuous_rearmed) {
        state.continuous_rearm_progress++;
      }
    }
    state.completed_vblank = after_vblank;
  }

  if constexpr (TrackStats) {
    if (should_probe_thor_es_frame_poll_log()) {
      log_thor_es_frame_poll_wait(ppu, after_counter, threshold, after_vblank);
    }
  }
  return thor_es_frame_poll_wait_result::waited;
}

NEVER_INLINE thor_es_frame_poll_wait_result
try_thor_es_frame_poll_wait_diagnostic(ppu_thread &ppu) {
  return try_thor_es_frame_poll_wait_impl<true>(ppu);
}

thor_es_frame_poll_wait_result
try_thor_es_frame_poll_wait(ppu_thread &ppu, u64 sleep_time) {
  auto mode = ppu.thor_es_frame_poll_mode;
  if (mode == thor_es_frame_poll_wait_mode::off ||
      ppu.cia != 0x002a8300 || sleep_time != 100) {
    return thor_es_frame_poll_wait_result::not_candidate;
  }

  if (mode == thor_es_frame_poll_wait_mode::uninitialized) [[unlikely]] {
    mode = get_thor_es_frame_poll_wait_mode();
    ppu.thor_es_frame_poll_mode = mode;
    if (mode == thor_es_frame_poll_wait_mode::off) {
      return thor_es_frame_poll_wait_result::not_candidate;
    }
  }

  if (mode == thor_es_frame_poll_wait_mode::fast) {
    return try_thor_es_frame_poll_wait_impl<false>(ppu);
  }

  return try_thor_es_frame_poll_wait_diagnostic(ppu);
}

void observe_thor_es_frame_poll_fallback(
    const ppu_thread &ppu, thor_es_frame_poll_wait_result result) {
  auto &state = g_thor_es_frame_poll_wait_state;
  if (state.ppu_id != ppu.id || !state.object_addr ||
      !vm::check_addr(state.object_addr)) {
    return;
  }

  const u32 counter = vm::read32(state.object_addr);
  if (counter != state.normal_pre_counter) {
    if (const auto renderer = rsx::get_current_renderer()) {
      state.completed_vblank = renderer->vblank_count;
      state.armed = true;
      if (result ==
          thor_es_frame_poll_wait_result::normal_sleep_diagnostic) {
        state.fallback_rearms++;
      }
    }
  }
}

} // namespace

struct lv2_timer_thread {
  shared_mutex mutex;
  std::deque<shared_ptr<lv2_timer>> timers;

  lv2_timer_thread();
  void operator()();

  // SAVESTATE_INIT_POS(46); // FREE SAVESTATE_INIT_POS number

  static constexpr auto thread_name = "Timer Thread"sv;
};

lv2_timer::lv2_timer(utils::serial &ar)
    : lv2_obj(1), state(ar), port(lv2_event_queue::load_ptr(ar, port, "timer")),
      source(ar), data1(ar), data2(ar), expire(ar), period(ar) {}

void lv2_timer::save(utils::serial &ar) {
  USING_SERIALIZATION_VERSION(lv2_sync);
  ar(state), lv2_event_queue::save_ptr(ar, port.get()),
      ar(source, data1, data2, expire, period);
}

u64 lv2_timer::check(u64 _now) noexcept {
  while (true) {
    const u32 _state = +state;

    if (_state == SYS_TIMER_STATE_RUN) {
      u64 next = expire;

      // If aborting, perform the last accurate check for event
      if (_now >= next) {
        lv2_obj::notify_all_t notify;

        std::lock_guard lock(mutex);
        return check_unlocked(_now);
      }

      return (next - _now);
    }

    break;
  }

  return umax;
}

u64 lv2_timer::check_unlocked(u64 _now) noexcept {
  const u64 next = expire;

  if (_now < next || state != SYS_TIMER_STATE_RUN) {
    return umax;
  }

  if (port) {
    port->send(source, data1, data2, next);
  }

  if (period) {
    // Set next expiration time and check again
    const u64 expire0 = rx::add_saturate<u64>(next, period);
    expire.release(expire0);
    return rx::sub_saturate<u64>(expire0, _now);
  }

  // Stop after oneshot
  state.release(SYS_TIMER_STATE_STOP);
  return umax;
}

lv2_timer_thread::lv2_timer_thread() {
  Emu.PostponeInitCode([this]() {
    idm::select<lv2_obj, lv2_timer>([&](u32 id, lv2_timer &) {
      timers.emplace_back(idm::get_unlocked<lv2_obj, lv2_timer>(id));
    });
  });
}

void lv2_timer_thread::operator()() {
  u64 sleep_time = 0;

  while (true) {
    if (sleep_time != umax) {
      // Scale time
      sleep_time =
          std::min(sleep_time, u64{umax} / 100) * 100 / g_cfg.core.clocks_scale;
    }

    thread_ctrl::wait_for(sleep_time);

    if (thread_ctrl::state() == thread_state::aborting) {
      break;
    }

    sleep_time = umax;

    if (Emu.IsPausedOrReady()) {
      sleep_time = 10000;
      continue;
    }

    const u64 _now = get_guest_system_time();

    reader_lock lock(mutex);

    for (const auto &timer : timers) {
      while (lv2_obj::check(timer)) {
        if (thread_ctrl::state() == thread_state::aborting) {
          break;
        }

        if (const u64 advised_sleep_time = timer->check(_now)) {
          if (sleep_time > advised_sleep_time) {
            sleep_time = advised_sleep_time;
          }

          break;
        }
      }
    }
  }
}

error_code sys_timer_create(ppu_thread &ppu, vm::ptr<u32> timer_id) {
  ppu.state += cpu_flag::wait;

  sys_timer.warning("sys_timer_create(timer_id=*0x%x)", timer_id);

  if (auto ptr = idm::make_ptr<lv2_obj, lv2_timer>()) {
    auto &thread = g_fxo->get<named_thread<lv2_timer_thread>>();
    {
      std::lock_guard lock(thread.mutex);

      // Theoretically could have been destroyed by sys_timer_destroy by now
      if (auto it = std::find(thread.timers.begin(), thread.timers.end(), ptr);
          it == thread.timers.end()) {
        thread.timers.emplace_back(std::move(ptr));
      }
    }

    ppu.check_state();
    *timer_id = idm::last_id();
    return CELL_OK;
  }

  return CELL_EAGAIN;
}

error_code sys_timer_destroy(ppu_thread &ppu, u32 timer_id) {
  ppu.state += cpu_flag::wait;

  sys_timer.warning("sys_timer_destroy(timer_id=0x%x)", timer_id);

  auto timer = idm::withdraw<lv2_obj, lv2_timer>(
      timer_id, [&](lv2_timer &timer) -> CellError {
        if (reader_lock lock(timer.mutex); lv2_obj::check(timer.port)) {
          return CELL_EISCONN;
        }

        timer.exists--;
        return {};
      });

  if (!timer) {
    return CELL_ESRCH;
  }

  if (timer.ret) {
    return timer.ret;
  }

  auto &thread = g_fxo->get<named_thread<lv2_timer_thread>>();
  std::lock_guard lock(thread.mutex);

  if (auto it =
          std::find(thread.timers.begin(), thread.timers.end(), timer.ptr);
      it != thread.timers.end()) {
    thread.timers.erase(it);
  }

  return CELL_OK;
}

error_code sys_timer_get_information(ppu_thread &ppu, u32 timer_id,
                                     vm::ptr<sys_timer_information_t> info) {
  ppu.state += cpu_flag::wait;

  sys_timer.trace("sys_timer_get_information(timer_id=0x%x, info=*0x%x)",
                  timer_id, info);

  sys_timer_information_t _info{};
  const u64 now = get_guest_system_time();

  const auto timer =
      idm::check<lv2_obj, lv2_timer>(timer_id, [&](lv2_timer &timer) {
        std::lock_guard lock(timer.mutex);

        timer.check_unlocked(now);
        timer.get_information(_info);
      });

  if (!timer) {
    return CELL_ESRCH;
  }

  ppu.check_state();
  std::memcpy(info.get_ptr(), &_info, info.size());
  return CELL_OK;
}

error_code _sys_timer_start(ppu_thread &ppu, u32 timer_id, u64 base_time,
                            u64 period) {
  ppu.state += cpu_flag::wait;

  (period ? sys_timer.warning : sys_timer.trace)(
      "_sys_timer_start(timer_id=0x%x, base_time=0x%llx, period=0x%llx)",
      timer_id, base_time, period);

  const u64 start_time = get_guest_system_time();

  if (period && period < 100) {
    // Invalid periodic timer
    return CELL_EINVAL;
  }

  const auto timer = idm::check<lv2_obj, lv2_timer>(
      timer_id, [&](lv2_timer &timer) -> CellError {
        std::lock_guard lock(timer.mutex);

        // LV2 Disassembly: Simple nullptr check (assignment test, do not use
        // lv2_obj::check here)
        if (!timer.port) {
          return CELL_ENOTCONN;
        }

        timer.check_unlocked(start_time);
        if (timer.state != SYS_TIMER_STATE_STOP) {
          return CELL_EBUSY;
        }

        if (!period && start_time >= base_time) {
          // Invalid oneshot
          return CELL_ETIMEDOUT;
        }

        const u64 expire =
            period == 0 ? base_time : // oneshot
                base_time == 0
                ? rx::add_saturate(start_time, period)
                :
                // periodic timer with no base (using start time as base)
                start_time < rx::add_saturate(base_time, period)
                ? rx::add_saturate(base_time, period)
                :
                // periodic with base time over start time
                [&]() -> u64 // periodic timer base before start time (align to
                             // be at least a period over start time)
        {
          // Optimized from a loop in LV2:
          // do
          // {
          // 	  base_time += period;
          // }
          // while (base_time < start_time);

          const u64 start_time_with_base_time_reminder = rx::add_saturate(
              start_time - start_time % period, base_time % period);

          return rx::add_saturate(
              start_time_with_base_time_reminder,
              start_time_with_base_time_reminder < start_time ? period : 0);
        }();

        timer.expire = expire;
        timer.period = period;
        timer.state = SYS_TIMER_STATE_RUN;
        return {};
      });

  if (!timer) {
    return CELL_ESRCH;
  }

  if (timer.ret) {
    if (timer.ret == CELL_ETIMEDOUT) {
      return not_an_error(timer.ret);
    }

    return timer.ret;
  }

  g_fxo->get<named_thread<lv2_timer_thread>>()([] {});

  return CELL_OK;
}

error_code sys_timer_stop(ppu_thread &ppu, u32 timer_id) {
  ppu.state += cpu_flag::wait;

  sys_timer.trace("sys_timer_stop()");

  const auto timer = idm::check<lv2_obj, lv2_timer>(
      timer_id, [now = get_guest_system_time(),
                 notify = lv2_obj::notify_all_t()](lv2_timer &timer) {
        std::lock_guard lock(timer.mutex);
        timer.check_unlocked(now);
        timer.state = SYS_TIMER_STATE_STOP;
      });

  if (!timer) {
    return CELL_ESRCH;
  }

  return CELL_OK;
}

error_code sys_timer_connect_event_queue(ppu_thread &ppu, u32 timer_id,
                                         u32 queue_id, u64 name, u64 data1,
                                         u64 data2) {
  ppu.state += cpu_flag::wait;

  sys_timer.warning("sys_timer_connect_event_queue(timer_id=0x%x, "
                    "queue_id=0x%x, name=0x%llx, data1=0x%llx, data2=0x%llx)",
                    timer_id, queue_id, name, data1, data2);

  const auto timer = idm::check<lv2_obj, lv2_timer>(
      timer_id, [&](lv2_timer &timer) -> CellError {
        auto found = idm::get_unlocked<lv2_obj, lv2_event_queue>(queue_id);

        if (!found) {
          return CELL_ESRCH;
        }

        std::lock_guard lock(timer.mutex);

        if (lv2_obj::check(timer.port)) {
          return CELL_EISCONN;
        }

        // Connect event queue
        timer.port = found;
        timer.source =
            name ? name : (u64{process_getpid() + 0u} << 32) | u64{timer_id};
        timer.data1 = data1;
        timer.data2 = data2;
        return {};
      });

  if (!timer) {
    return CELL_ESRCH;
  }

  if (timer.ret) {
    return timer.ret;
  }

  return CELL_OK;
}

error_code sys_timer_disconnect_event_queue(ppu_thread &ppu, u32 timer_id) {
  ppu.state += cpu_flag::wait;

  sys_timer.warning("sys_timer_disconnect_event_queue(timer_id=0x%x)",
                    timer_id);

  const auto timer = idm::check<lv2_obj, lv2_timer>(
      timer_id,
      [now = get_guest_system_time(),
       notify = lv2_obj::notify_all_t()](lv2_timer &timer) -> CellError {
        std::lock_guard lock(timer.mutex);

        timer.check_unlocked(now);
        timer.state = SYS_TIMER_STATE_STOP;

        if (!lv2_obj::check(timer.port)) {
          return CELL_ENOTCONN;
        }

        timer.port.reset();
        return {};
      });

  if (!timer) {
    return CELL_ESRCH;
  }

  if (timer.ret) {
    return timer.ret;
  }

  return CELL_OK;
}

error_code sys_timer_sleep(ppu_thread &ppu, u32 sleep_time) {
  ppu.state += cpu_flag::wait;

  sys_timer.trace("sys_timer_sleep(sleep_time=%d)", sleep_time);

  return sys_timer_usleep(ppu, sleep_time * u64{1000000});
}

error_code sys_timer_usleep(ppu_thread &ppu, u64 sleep_time) {
  ppu.state += cpu_flag::wait;

  sys_timer.trace("sys_timer_usleep(sleep_time=0x%llx)", sleep_time);

  const u64 requested_sleep_time = sleep_time;

  if (sleep_time) {
    const s64 add_time = g_cfg.core.usleep_addend;

    // Over/underflow checks
    if (add_time >= 0) {
      sleep_time = rx::add_saturate<u64>(sleep_time, add_time);
    } else {
      sleep_time =
          std::max<u64>(1, rx::sub_saturate<u64>(sleep_time, -add_time));
    }

    const auto frame_poll_result =
        try_thor_es_frame_poll_wait(ppu, sleep_time);
    if (frame_poll_result == thor_es_frame_poll_wait_result::waited) {
      thor_spurs_probe_log_ppu_wait(
          "usleep-frame-poll", ppu, 0, requested_sleep_time,
          thor_es_frame_poll_wait_max_us,
          static_cast<u64>((+ppu.state).raw()), CELL_OK);
      return CELL_OK;
    }

    lv2_obj::sleep(ppu, g_cfg.core.sleep_timers_accuracy <
                                sleep_timers_accuracy_level::_usleep
                            ? sleep_time
                            : 0);

    if (!lv2_obj::wait_timeout(sleep_time, &ppu, true, true)) {
      ppu.state += cpu_flag::again;
    }

    if (frame_poll_result !=
        thor_es_frame_poll_wait_result::not_candidate) {
      observe_thor_es_frame_poll_fallback(ppu, frame_poll_result);
    }
  } else {
    std::this_thread::yield();
  }

  thor_spurs_probe_log_ppu_wait("usleep", ppu, 0, requested_sleep_time,
                                sleep_time, static_cast<u64>((+ppu.state).raw()),
                                CELL_OK);
  return CELL_OK;
}
