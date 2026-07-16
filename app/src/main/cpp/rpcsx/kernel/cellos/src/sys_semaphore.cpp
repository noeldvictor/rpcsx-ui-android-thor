#include "stdafx.h"

#include "sys_semaphore.h"

#include "Emu/IdManager.h"
#include "Emu/System.h"

#include "Emu/Cell/ErrorCodes.h"
#include "Emu/Cell/PPUThread.h"
#include "Emu/Cell/timers.hpp"
#include "Emu/Memory/vm.h"
#include "thor_es_draw_stream_probe.h"
#include "thor_spurs_probe.h"

#include "rx/asm.hpp"

#include <array>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string_view>
#include <vector>

#ifdef ANDROID
#include <sys/system_properties.h>
#endif

LOG_CHANNEL(sys_semaphore);

enum class thor_es_sema_superpath_mode : u32 {
  disabled,
  profile,
  fast,
};

struct thor_es_sema_superpath_stats {
  std::atomic<u64> calls{0};
  std::atomic<u64> profile_hits{0};
  std::atomic<u64> fast_hits{0};
  std::atomic<u64> wait_hits{0};
  std::atomic<u64> post_hits{0};
  std::atomic<u64> zero_id_hits{0};
  std::atomic<u64> uncreated_id_hits{0};
  std::atomic<u64> destroyed_id_hits{0};
  std::atomic<u64> cached_id_hits{0};
  std::atomic<u64> direct_wait_hits{0};
  std::atomic<u64> direct_post_hits{0};
  std::atomic<u64> last_log_us{0};
  std::atomic<u32> max_created_index{umax};
  std::array<std::atomic<u32>, 32> destroyed_ids{};
  std::array<std::atomic<u32>, 64> cached_esrch_ids{};
};

struct thor_es_sema_fast_cache_entry {
  std::atomic<u32> sem_id{0};
  std::atomic<lv2_sema *> sema{nullptr};
};

static thor_es_sema_superpath_stats g_thor_es_sema_superpath_stats;
static std::array<thor_es_sema_fast_cache_entry, 64> g_thor_es_sema_fast_cache{};

namespace {

constexpr u32 thor_es_draw_stream_size = 0x18'0000;
constexpr u32 thor_es_draw_stream_producer_cia = 0x31c1bc;
constexpr u32 thor_es_draw_stream_producer_lr = 0x2ac7f0;
constexpr u32 thor_es_draw_stream_consumer_cia = 0x31c18c;
constexpr u32 thor_es_draw_stream_consumer_lr = 0x2afd08;

struct thor_es_draw_stream_layout {
  u32 object{};
  u32 buffer0{};
  u32 buffer1{};
  u32 write{};
  u32 flags{};
  u32 published{};
};

struct thor_es_draw_stream_probe_state {
  std::mutex mutex;
  std::vector<u8> snapshot;
  thor_es_draw_stream_layout layout{};
  u64 generation{};
  u64 captures{};
  u64 comparisons{};
  u64 matches{};
  u64 mismatches{};
  u64 invalid_layouts{};
  u64 last_summary_us{};
  u32 semaphore_id{};
  u32 first_mismatch{umax};
  bool consumer_checked{};
  bool consumer_match{};
  bool valid{};
};

static thor_es_draw_stream_probe_state g_thor_es_draw_stream_probe;

static bool parse_thor_es_draw_stream_probe(std::string_view value) {
  return value == "1" || value == "on" || value == "true" ||
         value == "profile" || value == "verify";
}

static FORCE_INLINE bool thor_es_draw_stream_probe_enabled() {
  static const bool enabled = [] {
#ifdef ANDROID
    char property_value[PROP_VALUE_MAX]{};
    const int property_length = __system_property_get(
        "debug.rpcsx.thor.es_draw_stream_probe", property_value);
    if (property_length > 0) {
      return parse_thor_es_draw_stream_probe(
          std::string_view{property_value, static_cast<usz>(property_length)});
    }
#endif

    if (const char *value =
            std::getenv("RPCSX_THOR_ES_DRAW_STREAM_PROBE")) {
      return parse_thor_es_draw_stream_probe(value);
    }

    return false;
  }();

  return enabled;
}

static bool read_thor_es_draw_stream_u32(u32 address, u32 &value) {
  be_t<u32> guest_value{};
  if (!vm::try_access(address, &guest_value, sizeof(guest_value), false)) {
    return false;
  }

  value = guest_value;
  return true;
}

static bool get_thor_es_draw_stream_layout(
    u32 object, thor_es_draw_stream_layout &layout) {
  if (object > 0xffff'ffffu - 0x20) {
    return false;
  }

  layout = {};
  layout.object = object;
  if (!read_thor_es_draw_stream_u32(object + 0x14, layout.buffer0) ||
      !read_thor_es_draw_stream_u32(object + 0x18, layout.buffer1) ||
      !read_thor_es_draw_stream_u32(object + 0x1c, layout.write) ||
      !read_thor_es_draw_stream_u32(object + 0x20, layout.flags)) {
    return false;
  }

  // The producer toggles bit 0 after terminating the published buffer. The
  // parser deliberately selects the opposite slot.
  layout.published =
      layout.flags & 1 ? layout.buffer0 : layout.buffer1;
  return layout.published &&
         vm::check_addr(layout.published, vm::page_readable,
                        thor_es_draw_stream_size);
}

static u32 get_thor_es_draw_stream_snapshot_word(const std::vector<u8> &bytes,
                                                 u32 offset) {
  if (offset > bytes.size() || bytes.size() - offset < sizeof(u32)) {
    return 0;
  }

  return static_cast<u32>(bytes[offset]) << 24 |
         static_cast<u32>(bytes[offset + 1]) << 16 |
         static_cast<u32>(bytes[offset + 2]) << 8 |
         static_cast<u32>(bytes[offset + 3]);
}

static void log_thor_es_draw_stream_summary(
    const ppu_thread &ppu, const char *stage,
    const thor_es_draw_stream_probe_state &state, bool force = false) {
  const u64 now = get_system_time();
  if (!force && state.last_summary_us &&
      now - state.last_summary_us < 2'000'000) {
    return;
  }

  g_thor_es_draw_stream_probe.last_summary_us = now;
  sys_semaphore.notice(
      "Eternal Sonata draw-stream probe: stage=%s generation=%llu "
      "object=0x%x published=0x%x flags=0x%x write=0x%x sem_id=0x%x "
      "captures=%llu comparisons=%llu matches=%llu mismatches=%llu "
      "invalid_layouts=%llu cia=0x%x lr=0x%x",
      stage, state.generation, state.layout.object, state.layout.published,
      state.layout.flags, state.layout.write, state.semaphore_id,
      state.captures, state.comparisons, state.matches, state.mismatches,
      state.invalid_layouts, ppu.cia, static_cast<u32>(ppu.lr));
}

static void thor_es_draw_stream_probe_before_post_enabled(
    const ppu_thread &ppu, u32 sem_id, s32 count) {
  if (count != 1 || Emu.GetTitleID() != "BLUS30161" ||
      ppu.cia != thor_es_draw_stream_producer_cia ||
      static_cast<u32>(ppu.lr) != thor_es_draw_stream_producer_lr) {
    return;
  }

  const u32 semaphore_wrapper = static_cast<u32>(ppu.gpr[29]);
  thor_es_draw_stream_layout layout{};
  if (semaphore_wrapper < 0x38 ||
      !get_thor_es_draw_stream_layout(semaphore_wrapper - 0x38, layout)) {
    std::lock_guard lock(g_thor_es_draw_stream_probe.mutex);
    g_thor_es_draw_stream_probe.valid = false;
    g_thor_es_draw_stream_probe.invalid_layouts++;
    log_thor_es_draw_stream_summary(ppu, "producer-invalid-layout",
                                    g_thor_es_draw_stream_probe, true);
    return;
  }

  std::lock_guard lock(g_thor_es_draw_stream_probe.mutex);
  auto &state = g_thor_es_draw_stream_probe;
  state.snapshot.resize(thor_es_draw_stream_size);
  if (!vm::try_access(layout.published, state.snapshot.data(),
                      thor_es_draw_stream_size, false)) {
    state.valid = false;
    state.invalid_layouts++;
    log_thor_es_draw_stream_summary(ppu, "producer-copy-failed", state, true);
    return;
  }

  state.layout = layout;
  state.semaphore_id = sem_id;
  state.generation++;
  state.captures++;
  state.first_mismatch = umax;
  state.consumer_checked = false;
  state.consumer_match = false;
  state.valid = true;
  log_thor_es_draw_stream_summary(ppu, "producer-snapshot", state,
                                  state.generation == 1);
}

static void
thor_es_draw_stream_probe_after_wait_enabled(const ppu_thread &ppu) {
  if (Emu.GetTitleID() != "BLUS30161" ||
      ppu.cia != thor_es_draw_stream_consumer_cia ||
      static_cast<u32>(ppu.lr) != thor_es_draw_stream_consumer_lr) {
    return;
  }

  const u32 semaphore_wrapper = static_cast<u32>(ppu.gpr[30]);
  thor_es_draw_stream_layout layout{};
  if (semaphore_wrapper < 0x38 ||
      !get_thor_es_draw_stream_layout(semaphore_wrapper - 0x38, layout)) {
    std::lock_guard lock(g_thor_es_draw_stream_probe.mutex);
    g_thor_es_draw_stream_probe.invalid_layouts++;
    log_thor_es_draw_stream_summary(ppu, "consumer-invalid-layout",
                                    g_thor_es_draw_stream_probe, true);
    return;
  }

  std::lock_guard lock(g_thor_es_draw_stream_probe.mutex);
  auto &state = g_thor_es_draw_stream_probe;
  if (!state.valid || state.layout.object != layout.object ||
      state.layout.published != layout.published ||
      state.layout.flags != layout.flags) {
    state.invalid_layouts++;
    log_thor_es_draw_stream_summary(ppu, "consumer-layout-mismatch", state,
                                    true);
    return;
  }

  const u8 *live = vm::get_super_ptr<u8>(layout.published);
  state.comparisons++;
  state.consumer_checked = true;
  state.consumer_match =
      std::memcmp(state.snapshot.data(), live, thor_es_draw_stream_size) == 0;
  if (state.consumer_match) {
    state.matches++;
    log_thor_es_draw_stream_summary(ppu, "consumer-match", state);
    return;
  }

  state.mismatches++;
  state.first_mismatch = 0;
  while (state.first_mismatch < thor_es_draw_stream_size &&
         state.snapshot[state.first_mismatch] == live[state.first_mismatch]) {
    state.first_mismatch++;
  }

  const u32 aligned_offset = state.first_mismatch & ~3u;
  const u32 producer_word =
      get_thor_es_draw_stream_snapshot_word(state.snapshot, aligned_offset);
  u32 live_word = 0;
  read_thor_es_draw_stream_u32(layout.published + aligned_offset, live_word);
  sys_semaphore.error(
      "Eternal Sonata draw-stream handoff mismatch: generation=%llu "
      "object=0x%x published=0x%x first_byte=0x%x word_offset=0x%x "
      "producer_word=0x%x consumer_word=0x%x comparisons=%llu "
      "mismatches=%llu cia=0x%x lr=0x%x",
      state.generation, layout.object, layout.published, state.first_mismatch,
      aligned_offset, producer_word, live_word, state.comparisons,
      state.mismatches, ppu.cia, static_cast<u32>(ppu.lr));
}

static FORCE_INLINE void
maybe_thor_es_draw_stream_probe_before_post(const ppu_thread &ppu, u32 sem_id,
                                            s32 count) {
  if (thor_es_draw_stream_probe_enabled()) {
    thor_es_draw_stream_probe_before_post_enabled(ppu, sem_id, count);
  }
}

static FORCE_INLINE void
maybe_thor_es_draw_stream_probe_after_wait(const ppu_thread &ppu) {
  if (thor_es_draw_stream_probe_enabled()) {
    thor_es_draw_stream_probe_after_wait_enabled(ppu);
  }
}

} // namespace

void thor_es_draw_stream_probe_tty(const ppu_thread &ppu,
                                   std::string_view message) {
  if (!thor_es_draw_stream_probe_enabled() ||
      Emu.GetTitleID() != "BLUS30161" ||
      message.find("unknown draw command") == std::string_view::npos) {
    return;
  }

  const u32 cursor = static_cast<u32>(ppu.gpr[31]);
  const u32 parser_object = static_cast<u32>(ppu.gpr[22]);

  std::lock_guard lock(g_thor_es_draw_stream_probe.mutex);
  const auto &state = g_thor_es_draw_stream_probe;
  if (!state.valid || cursor < state.layout.published + sizeof(u32) ||
      cursor > state.layout.published + thor_es_draw_stream_size) {
    sys_semaphore.error(
        "Eternal Sonata draw-stream parser fault outside snapshot: "
        "generation=%llu cursor=0x%x parser_object=0x%x "
        "snapshot_object=0x%x published=0x%x valid=%u checked=%u match=%u "
        "cia=0x%x lr=0x%x",
        state.generation, cursor, parser_object, state.layout.object,
        state.layout.published, state.valid, state.consumer_checked,
        state.consumer_match, ppu.cia, static_cast<u32>(ppu.lr));
    return;
  }

  const u32 word_offset = cursor - sizeof(u32) - state.layout.published;
  const u32 producer_word =
      get_thor_es_draw_stream_snapshot_word(state.snapshot, word_offset);
  u32 live_word = 0;
  const bool live_read = read_thor_es_draw_stream_u32(
      state.layout.published + word_offset, live_word);
  const u32 context_offset = word_offset & ~3u;
  const u32 context0 = get_thor_es_draw_stream_snapshot_word(
      state.snapshot, context_offset >= 8 ? context_offset - 8 : 0);
  const u32 context1 = get_thor_es_draw_stream_snapshot_word(
      state.snapshot, context_offset >= 4 ? context_offset - 4 : 0);
  const u32 context2 = get_thor_es_draw_stream_snapshot_word(
      state.snapshot, context_offset);
  const u32 context3 = get_thor_es_draw_stream_snapshot_word(
      state.snapshot, context_offset + 4);
  const u32 context4 = get_thor_es_draw_stream_snapshot_word(
      state.snapshot, context_offset + 8);

  sys_semaphore.error(
      "Eternal Sonata draw-stream parser fault: generation=%llu "
      "object=0x%x parser_object=0x%x published=0x%x cursor=0x%x "
      "word_offset=0x%x producer_word=0x%x live_word=0x%x live_read=%u "
      "producer_equals_live=%u handoff_checked=%u handoff_match=%u "
      "first_mismatch=0x%x context=[%08x %08x %08x %08x %08x] "
      "cia=0x%x lr=0x%x",
      state.generation, state.layout.object, parser_object,
      state.layout.published, cursor, word_offset, producer_word, live_word,
      live_read, live_read && producer_word == live_word,
      state.consumer_checked, state.consumer_match, state.first_mismatch,
      context0, context1, context2, context3, context4, ppu.cia,
      static_cast<u32>(ppu.lr));
}

static thor_es_sema_superpath_mode parse_thor_es_sema_superpath_mode(
    std::string_view value) {
  if (value.empty() || value == "0" || value == "off" || value == "false" ||
      value == "disabled") {
    return thor_es_sema_superpath_mode::disabled;
  }

  if (value == "profile" || value == "log" || value == "detect") {
    return thor_es_sema_superpath_mode::profile;
  }

  return thor_es_sema_superpath_mode::fast;
}

static thor_es_sema_superpath_mode get_thor_es_sema_superpath_mode() {
  static const thor_es_sema_superpath_mode mode = [] {
#ifdef ANDROID
    char property_value[PROP_VALUE_MAX]{};
    const int property_length = __system_property_get(
        "debug.rpcsx.thor.es_sema_superpath", property_value);
    if (property_length > 0) {
      return parse_thor_es_sema_superpath_mode(
          std::string_view{property_value, static_cast<usz>(property_length)});
    }
#endif

    if (const char *value = std::getenv("RPCSX_THOR_ES_SEMA_SUPERPATH")) {
      return parse_thor_es_sema_superpath_mode(value);
    }

    if (const char *value = std::getenv("RPCS3_ES_SEMA_ESRCH_SUPERPATH")) {
      return parse_thor_es_sema_superpath_mode(value);
    }

    return thor_es_sema_superpath_mode::disabled;
  }();

  return mode;
}

static const char *get_thor_es_sema_superpath_mode_name() {
  switch (get_thor_es_sema_superpath_mode()) {
  case thor_es_sema_superpath_mode::profile:
    return "profile";
  case thor_es_sema_superpath_mode::fast:
    return "fast";
  default:
    return "disabled";
  }
}

static bool is_thor_es_sema_superpath_candidate(const ppu_thread &ppu,
                                                bool post) {
  if (get_thor_es_sema_superpath_mode() ==
      thor_es_sema_superpath_mode::disabled) {
    return false;
  }

  if (Emu.GetTitleID() != "BLUS30161") {
    return false;
  }

  const std::string ppu_name = static_cast<std::string>(ppu.thread_name);
  if (ppu_name.find("main_thread") == std::string::npos) {
    return false;
  }

  const u32 cia = ppu.cia;

  if (post) {
    return cia >= 0x31c550 && cia <= 0x31c620;
  }

  return cia >= 0x31c168 && cia <= 0x31c1bc;
}

static u32 get_thor_es_sema_index(u32 sem_id) {
  return id_manager::get_index(
      sem_id, id_manager::id_traits<lv2_sema>::base,
      id_manager::id_traits<lv2_sema>::step,
      id_manager::id_traits<lv2_sema>::count,
      id_manager::id_traits<lv2_sema>::invl_range);
}

static void record_thor_es_sema_created_id(u32 sem_id) {
  if (get_thor_es_sema_superpath_mode() ==
          thor_es_sema_superpath_mode::disabled ||
      Emu.GetTitleID() != "BLUS30161") {
    return;
  }

  const u32 index = get_thor_es_sema_index(sem_id);
  if (index >= lv2_sema::id_count) {
    return;
  }

  auto &cached_id =
      g_thor_es_sema_superpath_stats
          .cached_esrch_ids[index %
                            g_thor_es_sema_superpath_stats.cached_esrch_ids
                                .size()];
  u32 expected = sem_id;
  cached_id.compare_exchange_strong(expected, 0, std::memory_order_relaxed);

  auto &fast_entry =
      g_thor_es_sema_fast_cache[index % g_thor_es_sema_fast_cache.size()];
  expected = sem_id;
  if (fast_entry.sem_id.compare_exchange_strong(expected, 0,
                                                std::memory_order_relaxed)) {
    fast_entry.sema.store(nullptr, std::memory_order_relaxed);
  }

  u32 current =
      g_thor_es_sema_superpath_stats.max_created_index.load(
          std::memory_order_relaxed);
  while ((current == umax || index > current) &&
         !g_thor_es_sema_superpath_stats.max_created_index
              .compare_exchange_weak(current, index,
                                     std::memory_order_relaxed)) {
  }
}

static void record_thor_es_sema_destroyed_id(u32 sem_id) {
  if (get_thor_es_sema_superpath_mode() ==
          thor_es_sema_superpath_mode::disabled ||
      Emu.GetTitleID() != "BLUS30161") {
    return;
  }

  const u32 index = get_thor_es_sema_index(sem_id);
  if (index >= lv2_sema::id_count) {
    return;
  }

  g_thor_es_sema_superpath_stats
      .destroyed_ids[index %
                     g_thor_es_sema_superpath_stats.destroyed_ids.size()]
      .store(sem_id, std::memory_order_relaxed);

  auto &fast_entry =
      g_thor_es_sema_fast_cache[index % g_thor_es_sema_fast_cache.size()];
  u32 expected = sem_id;
  if (fast_entry.sem_id.compare_exchange_strong(expected, 0,
                                                std::memory_order_relaxed)) {
    fast_entry.sema.store(nullptr, std::memory_order_relaxed);
  }
}

static void record_thor_es_sema_cached_esrch_id(u32 sem_id) {
  if (get_thor_es_sema_superpath_mode() ==
          thor_es_sema_superpath_mode::disabled ||
      Emu.GetTitleID() != "BLUS30161" || sem_id == 0) {
    return;
  }

  const u32 index = get_thor_es_sema_index(sem_id);
  if (index >= lv2_sema::id_count) {
    return;
  }

  g_thor_es_sema_superpath_stats
      .cached_esrch_ids[index %
                        g_thor_es_sema_superpath_stats.cached_esrch_ids.size()]
      .store(sem_id, std::memory_order_relaxed);
}

static void record_thor_es_sema_fast_object(u32 sem_id, lv2_sema *sema) {
  if (get_thor_es_sema_superpath_mode() ==
          thor_es_sema_superpath_mode::disabled ||
      Emu.GetTitleID() != "BLUS30161" || !sema) {
    return;
  }

  const u32 index = get_thor_es_sema_index(sem_id);
  if (index >= lv2_sema::id_count) {
    return;
  }

  auto &entry =
      g_thor_es_sema_fast_cache[index % g_thor_es_sema_fast_cache.size()];
  entry.sema.store(sema, std::memory_order_relaxed);
  entry.sem_id.store(sem_id, std::memory_order_relaxed);
}

static lv2_sema *get_thor_es_sema_fast_object(u32 sem_id) {
  const u32 index = get_thor_es_sema_index(sem_id);
  if (index >= lv2_sema::id_count) {
    return nullptr;
  }

  auto &entry =
      g_thor_es_sema_fast_cache[index % g_thor_es_sema_fast_cache.size()];
  if (entry.sem_id.load(std::memory_order_relaxed) != sem_id) {
    return nullptr;
  }

  return entry.sema.load(std::memory_order_relaxed);
}

static const char *get_thor_es_sema_fast_esrch_action(u32 sem_id) {
  if (sem_id == 0) {
    g_thor_es_sema_superpath_stats.zero_id_hits.fetch_add(
        1, std::memory_order_relaxed);
    return "fast-zero-esrch";
  }

  const u32 index = get_thor_es_sema_index(sem_id);
  if (index >= lv2_sema::id_count) {
    return nullptr;
  }

  if (g_thor_es_sema_superpath_stats
          .cached_esrch_ids[index %
                            g_thor_es_sema_superpath_stats.cached_esrch_ids
                                .size()]
          .load(std::memory_order_relaxed) == sem_id) {
    g_thor_es_sema_superpath_stats.cached_id_hits.fetch_add(
        1, std::memory_order_relaxed);
    return "fast-cached-esrch";
  }

  for (const auto &destroyed_id :
       g_thor_es_sema_superpath_stats.destroyed_ids) {
    if (destroyed_id.load(std::memory_order_relaxed) == sem_id) {
      g_thor_es_sema_superpath_stats.destroyed_id_hits.fetch_add(
          1, std::memory_order_relaxed);
      return "fast-destroyed-esrch";
    }
  }

  const u32 max_created_index =
      g_thor_es_sema_superpath_stats.max_created_index.load(
          std::memory_order_relaxed);
  if (max_created_index != umax && index > max_created_index &&
      (sem_id & 0xff) == 0) {
    g_thor_es_sema_superpath_stats.uncreated_id_hits.fetch_add(
        1, std::memory_order_relaxed);
    return "fast-uncreated-esrch";
  }

  return nullptr;
}

static bool try_thor_es_sema_fast_wait(ppu_thread &ppu, u32 sem_id) {
  lv2_sema *sema = get_thor_es_sema_fast_object(sem_id);
  if (!sema) {
    return false;
  }

  const s32 val = sema->val;
  if (val <= 0) {
    return false;
  }

  if (!sema->val.compare_and_swap_test(val, val - 1)) {
    return false;
  }

  ppu.gpr[3] = CELL_OK;
  return true;
}

static bool try_thor_es_sema_fast_post(u32 sem_id, s32 count) {
  if (count <= 0) {
    return false;
  }

  lv2_sema *sema = get_thor_es_sema_fast_object(sem_id);
  if (!sema) {
    return false;
  }

  const s32 val = sema->val;
  if (val < 0 || count > sema->max - val) {
    return false;
  }

  return sema->val.compare_and_swap_test(val, val + count);
}

static void log_thor_es_sema_superpath(const ppu_thread &ppu,
                                       const char *syscall_name,
                                       const char *action, u32 sem_id,
                                       u64 extra) {
  g_thor_es_sema_superpath_stats.calls.fetch_add(1,
                                                 std::memory_order_relaxed);

  const u64 now = get_system_time();
  u64 last =
      g_thor_es_sema_superpath_stats.last_log_us.load(
          std::memory_order_relaxed);
  if (last && now - last < 1'000'000) {
    return;
  }

  if (!g_thor_es_sema_superpath_stats.last_log_us.compare_exchange_strong(
          last, now, std::memory_order_relaxed)) {
    return;
  }

  const std::string ppu_name = static_cast<std::string>(ppu.thread_name);
  const u32 max_created_index =
      g_thor_es_sema_superpath_stats.max_created_index.load(
          std::memory_order_relaxed);

  sys_semaphore.notice(
      "Eternal Sonata semaphore superpath: mode=%s action=%s syscall=%s "
      "title=%s ppu=0x%x name=\"%s\" cia=0x%x lr=0x%x sem_id=0x%x "
      "extra=0x%llx calls=%llu profile_hits=%llu fast_hits=%llu "
      "wait_hits=%llu post_hits=%llu zero_id_hits=%llu "
      "uncreated_id_hits=%llu destroyed_id_hits=%llu cached_id_hits=%llu "
      "direct_wait_hits=%llu direct_post_hits=%llu max_created_index=%u",
      get_thor_es_sema_superpath_mode_name(), action, syscall_name,
      Emu.GetTitleID(), ppu.id, ppu_name, ppu.cia, static_cast<u32>(ppu.lr),
      sem_id, extra,
      g_thor_es_sema_superpath_stats.calls.load(std::memory_order_relaxed),
      g_thor_es_sema_superpath_stats.profile_hits.load(
          std::memory_order_relaxed),
      g_thor_es_sema_superpath_stats.fast_hits.load(
          std::memory_order_relaxed),
      g_thor_es_sema_superpath_stats.wait_hits.load(
          std::memory_order_relaxed),
      g_thor_es_sema_superpath_stats.post_hits.load(
          std::memory_order_relaxed),
      g_thor_es_sema_superpath_stats.zero_id_hits.load(
          std::memory_order_relaxed),
      g_thor_es_sema_superpath_stats.uncreated_id_hits.load(
          std::memory_order_relaxed),
      g_thor_es_sema_superpath_stats.destroyed_id_hits.load(
          std::memory_order_relaxed),
      g_thor_es_sema_superpath_stats.cached_id_hits.load(
          std::memory_order_relaxed),
      g_thor_es_sema_superpath_stats.direct_wait_hits.load(
          std::memory_order_relaxed),
      g_thor_es_sema_superpath_stats.direct_post_hits.load(
          std::memory_order_relaxed),
      max_created_index == umax ? umax : max_created_index);
}

lv2_sema::lv2_sema(utils::serial &ar)
    : protocol(ar), key(ar), name(ar), max(ar) {
  ar(val);
}

std::function<void(void *)> lv2_sema::load(utils::serial &ar) {
  return load_func(make_shared<lv2_sema>(exact_t<utils::serial &>(ar)));
}

void lv2_sema::save(utils::serial &ar) {
  USING_SERIALIZATION_VERSION(lv2_sync);
  ar(protocol, key, name, max, std::max<s32>(+val, 0));
}

error_code sys_semaphore_create(ppu_thread &ppu, vm::ptr<u32> sem_id,
                                vm::ptr<sys_semaphore_attribute_t> attr,
                                s32 initial_val, s32 max_val) {
  ppu.state += cpu_flag::wait;

  sys_semaphore.trace("sys_semaphore_create(sem_id=*0x%x, attr=*0x%x, "
                      "initial_val=%d, max_val=%d)",
                      sem_id, attr, initial_val, max_val);

  if (!sem_id || !attr) {
    return CELL_EFAULT;
  }

  if (max_val <= 0 || initial_val > max_val || initial_val < 0) {
    sys_semaphore.error("sys_semaphore_create(): invalid parameters "
                        "(initial_val=%d, max_val=%d)",
                        initial_val, max_val);
    return CELL_EINVAL;
  }

  const auto _attr = *attr;

  const u32 protocol = _attr.protocol;

  if (protocol != SYS_SYNC_FIFO && protocol != SYS_SYNC_PRIORITY) {
    sys_semaphore.error("sys_semaphore_create(): unknown protocol (0x%x)",
                        protocol);
    return CELL_EINVAL;
  }

  const u64 ipc_key = lv2_obj::get_key(_attr);

  if (ipc_key) {
    sys_semaphore.warning("sys_semaphore_create(sem_id=*0x%x, attr=*0x%x, "
                          "initial_val=%d, max_val=%d): IPC=0x%016x",
                          sem_id, attr, initial_val, max_val, ipc_key);
  }

  if (auto error =
          lv2_obj::create<lv2_sema>(_attr.pshared, ipc_key, _attr.flags, [&] {
            return make_shared<lv2_sema>(protocol, ipc_key, _attr.name_u64,
                                         max_val, initial_val);
          })) {
    return error;
  }

  static_cast<void>(ppu.test_stopped());

  const u32 created_id = idm::last_id();
  *sem_id = created_id;
  record_thor_es_sema_created_id(created_id);
  return CELL_OK;
}

error_code sys_semaphore_destroy(ppu_thread &ppu, u32 sem_id) {
  ppu.state += cpu_flag::wait;

  sys_semaphore.trace("sys_semaphore_destroy(sem_id=0x%x)", sem_id);

  const auto sem =
      idm::withdraw<lv2_obj, lv2_sema>(sem_id, [](lv2_sema &sema) -> CellError {
        if (sema.val < 0) {
          return CELL_EBUSY;
        }

        lv2_obj::on_id_destroy(sema, sema.key);
        return {};
      });

  if (!sem) {
    return CELL_ESRCH;
  }

  if (sem->key) {
    sys_semaphore.warning("sys_semaphore_destroy(sem_id=0x%x): IPC=0x%016x",
                          sem_id, sem->key);
  }

  if (sem.ret) {
    return sem.ret;
  }

  record_thor_es_sema_destroyed_id(sem_id);
  return CELL_OK;
}

error_code sys_semaphore_wait(ppu_thread &ppu, u32 sem_id, u64 timeout) {
  ppu.state += cpu_flag::wait;

  sys_semaphore.trace("sys_semaphore_wait(sem_id=0x%x, timeout=0x%llx)", sem_id,
                      timeout);

  if (is_thor_es_sema_superpath_candidate(ppu, false)) {
    g_thor_es_sema_superpath_stats.wait_hits.fetch_add(
        1, std::memory_order_relaxed);

    if (get_thor_es_sema_superpath_mode() ==
        thor_es_sema_superpath_mode::profile) {
      g_thor_es_sema_superpath_stats.profile_hits.fetch_add(
          1, std::memory_order_relaxed);
      log_thor_es_sema_superpath(ppu, "sys_semaphore_wait", "profile", sem_id,
                                 timeout);
    } else if (try_thor_es_sema_fast_wait(ppu, sem_id)) {
      const u64 fast_hits =
          g_thor_es_sema_superpath_stats.fast_hits.fetch_add(
              1, std::memory_order_relaxed) +
          1;
      g_thor_es_sema_superpath_stats.direct_wait_hits.fetch_add(
          1, std::memory_order_relaxed);
      if ((fast_hits & 0x3ff) == 0) {
        log_thor_es_sema_superpath(ppu, "sys_semaphore_wait",
                                   "fast-direct-wait", sem_id, timeout);
      }
      maybe_thor_es_draw_stream_probe_after_wait(ppu);
      return CELL_OK;
    } else if (const char *action =
                   get_thor_es_sema_fast_esrch_action(sem_id)) {
      g_thor_es_sema_superpath_stats.fast_hits.fetch_add(
          1, std::memory_order_relaxed);
      log_thor_es_sema_superpath(ppu, "sys_semaphore_wait", action, sem_id,
                                 timeout);
      return CELL_ESRCH;
    }
  }

  const auto sem = idm::get<lv2_obj, lv2_sema>(
      sem_id, [&, notify = lv2_obj::notify_all_t()](lv2_sema &sema) {
        const s32 val = sema.val;

        if (val > 0) {
          if (sema.val.compare_and_swap_test(val, val - 1)) {
            return true;
          }
        }

        lv2_obj::prepare_for_sleep(ppu);

        std::lock_guard lock(sema.mutex);

        if (sema.val-- <= 0) {
          sema.sleep(ppu, timeout);
          lv2_obj::emplace(sema.sq, &ppu);
          return false;
        }

        return true;
      });

  if (!sem) {
    if (is_thor_es_sema_superpath_candidate(ppu, false)) {
      record_thor_es_sema_cached_esrch_id(sem_id);
    }

    return CELL_ESRCH;
  }

  record_thor_es_sema_fast_object(sem_id, sem.ptr.get());

  if (sem.ret) {
    thor_spurs_probe_log_ppu_wait("sem_wait_ready", ppu, sem_id, timeout,
                                  sem->key, static_cast<u64>(+sem->val),
                                  CELL_OK);
    maybe_thor_es_draw_stream_probe_after_wait(ppu);
    return CELL_OK;
  }

  ppu.gpr[3] = CELL_OK;

  while (auto state = +ppu.state) {
    if (state & cpu_flag::signal &&
        ppu.state.test_and_reset(cpu_flag::signal)) {
      break;
    }

    if (is_stopped(state)) {
      std::lock_guard lock(sem->mutex);

      for (auto cpu = +sem->sq; cpu; cpu = cpu->next_cpu) {
        if (cpu == &ppu) {
          ppu.state += cpu_flag::again;
          return {};
        }
      }

      break;
    }

    for (usz i = 0; cpu_flag::signal - ppu.state && i < 50; i++) {
      rx::busy_wait(500);
    }

    if (ppu.state & cpu_flag::signal) {
      continue;
    }

    if (timeout) {
      if (lv2_obj::wait_timeout(timeout, &ppu)) {
        // Wait for rescheduling
        if (ppu.check_state()) {
          continue;
        }

        ppu.state += cpu_flag::wait;

        std::lock_guard lock(sem->mutex);

        if (!sem->unqueue(sem->sq, &ppu)) {
          break;
        }

        ensure(0 > sem->val.fetch_op([](s32 &val) {
          if (val < 0) {
            val++;
          }
        }));

        ppu.gpr[3] = CELL_ETIMEDOUT;
        break;
      }
    } else {
      ppu.state.wait(state);
    }
  }

  const s32 result = static_cast<s32>(ppu.gpr[3]);
  thor_spurs_probe_log_ppu_wait("sem_wait_wait", ppu, sem_id, timeout,
                                sem->key, static_cast<u64>(+sem->val),
                                result);
  if (result == CELL_OK) {
    maybe_thor_es_draw_stream_probe_after_wait(ppu);
  }
  return not_an_error(result);
}

error_code sys_semaphore_trywait(ppu_thread &ppu, u32 sem_id) {
  ppu.state += cpu_flag::wait;

  sys_semaphore.trace("sys_semaphore_trywait(sem_id=0x%x)", sem_id);

  const auto sem = idm::check<lv2_obj, lv2_sema>(
      sem_id, [&](lv2_sema &sema) { return sema.val.try_dec(0); });

  if (!sem) {
    return CELL_ESRCH;
  }

  if (!sem.ret) {
    return not_an_error(CELL_EBUSY);
  }

  return CELL_OK;
}

error_code sys_semaphore_post(ppu_thread &ppu, u32 sem_id, s32 count) {
  ppu.state += cpu_flag::wait;

  sys_semaphore.trace("sys_semaphore_post(sem_id=0x%x, count=%d)", sem_id,
                      count);

  // Snapshot before the semaphore mutation makes the consumer runnable.
  maybe_thor_es_draw_stream_probe_before_post(ppu, sem_id, count);

  if (is_thor_es_sema_superpath_candidate(ppu, true)) {
    g_thor_es_sema_superpath_stats.post_hits.fetch_add(
        1, std::memory_order_relaxed);

    if (get_thor_es_sema_superpath_mode() ==
        thor_es_sema_superpath_mode::profile) {
      g_thor_es_sema_superpath_stats.profile_hits.fetch_add(
          1, std::memory_order_relaxed);
      log_thor_es_sema_superpath(ppu, "sys_semaphore_post", "profile", sem_id,
                                 static_cast<u32>(count));
    } else if (try_thor_es_sema_fast_post(sem_id, count)) {
      const u64 fast_hits =
          g_thor_es_sema_superpath_stats.fast_hits.fetch_add(
              1, std::memory_order_relaxed) +
          1;
      g_thor_es_sema_superpath_stats.direct_post_hits.fetch_add(
          1, std::memory_order_relaxed);
      if ((fast_hits & 0x3ff) == 0) {
        log_thor_es_sema_superpath(ppu, "sys_semaphore_post",
                                   "fast-direct-post", sem_id,
                                   static_cast<u32>(count));
      }
      return CELL_OK;
    } else if (const char *action =
                   get_thor_es_sema_fast_esrch_action(sem_id)) {
      g_thor_es_sema_superpath_stats.fast_hits.fetch_add(
          1, std::memory_order_relaxed);
      log_thor_es_sema_superpath(ppu, "sys_semaphore_post", action, sem_id,
                                 static_cast<u32>(count));
      return CELL_ESRCH;
    }
  }

  const auto sem = idm::get<lv2_obj, lv2_sema>(sem_id, [&](lv2_sema &sema) {
    const s32 val = sema.val;

    if (val >= 0 && count > 0 && count <= sema.max - val) {
      if (sema.val.compare_and_swap_test(val, val + count)) {
        return true;
      }
    }

    return false;
  });

  if (!sem) {
    if (is_thor_es_sema_superpath_candidate(ppu, true)) {
      record_thor_es_sema_cached_esrch_id(sem_id);
    }

    return CELL_ESRCH;
  }

  record_thor_es_sema_fast_object(sem_id, sem.ptr.get());

  if (count <= 0) {
    return CELL_EINVAL;
  }

  lv2_obj::notify_all_t notify;

  if (sem.ret) {
    thor_spurs_probe_log_ppu_wait("sem_post_fast", ppu, sem_id,
                                  static_cast<u64>(count), sem->key,
                                  static_cast<u64>(+sem->val), CELL_OK);
    return CELL_OK;
  } else {
    std::lock_guard lock(sem->mutex);

    for (auto cpu = +sem->sq; cpu; cpu = cpu->next_cpu) {
      if (static_cast<ppu_thread *>(cpu)->state & cpu_flag::again) {
        ppu.state += cpu_flag::again;
        return {};
      }
    }

    const auto [val, ok] = sem->val.fetch_op([&](s32 &val) {
      if (count + 0u <= sem->max + 0u - val) {
        val += count;
        return true;
      }

      return false;
    });

    if (!ok) {
      return not_an_error(CELL_EBUSY);
    }

    // Wake threads
    const s32 to_awake = std::min<s32>(-std::min<s32>(val, 0), count);

    for (s32 i = 0; i < to_awake; i++) {
      sem->append((ensure(sem->schedule<ppu_thread>(sem->sq, sem->protocol))));
    }

    if (to_awake > 0) {
      lv2_obj::awake_all();
    }
  }

  thor_spurs_probe_log_ppu_wait("sem_post", ppu, sem_id,
                                static_cast<u64>(count), sem->key,
                                static_cast<u64>(+sem->val), CELL_OK);
  return CELL_OK;
}

error_code sys_semaphore_get_value(ppu_thread &ppu, u32 sem_id,
                                   vm::ptr<s32> count) {
  ppu.state += cpu_flag::wait;

  sys_semaphore.trace("sys_semaphore_get_value(sem_id=0x%x, count=*0x%x)",
                      sem_id, count);

  const auto sema = idm::check<lv2_obj, lv2_sema>(
      sem_id, [](lv2_sema &sema) { return std::max<s32>(0, sema.val); });

  if (!sema) {
    return CELL_ESRCH;
  }

  if (!count) {
    return CELL_EFAULT;
  }

  static_cast<void>(ppu.test_stopped());

  *count = sema.ret;
  return CELL_OK;
}
