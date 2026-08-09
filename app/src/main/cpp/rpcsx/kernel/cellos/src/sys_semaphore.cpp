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

#include "cellos/thor_ppu_wait.h"

#include <array>
#include <atomic>
#include <charconv>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string_view>
#include <vector>

#ifdef ANDROID
#include <sys/system_properties.h>
#endif

LOG_CHANNEL(sys_semaphore);

#if !defined(__ANDROID__) || defined(RPCSX_THOR_SEMA_SUPERPATH)
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
#endif

#if !defined(__ANDROID__) || defined(RPCSX_THOR_DRAW_STREAM_PROBE)
namespace {

constexpr u32 thor_es_draw_stream_size = 0x18'0000;
// ppu.cia still points at the SC instruction while the host syscall handler is
// running. The following instruction addresses (0x31c1bc / 0x31c18c) are only
// visible after the handler returns to the guest.
constexpr u32 thor_es_draw_stream_post_cia = 0x31c1b8;
constexpr u32 thor_es_draw_stream_wait_cia = 0x31c188;
constexpr u32 thor_es_draw_stream_producer_prior_completion_wait_lr = 0x2ac7e4;
constexpr u32 thor_es_draw_stream_producer_work_post_lr = 0x2ac7f0;
constexpr u32 thor_es_draw_stream_producer_completion_wait_lr = 0x2ac830;
constexpr u32 thor_es_draw_stream_producer_completion_restore_lr = 0x2ac83c;
constexpr u32 thor_es_draw_stream_consumer_completion_post_lr = 0x2accb4;
constexpr u32 thor_es_draw_stream_consumer_work_wait_lr = 0x2afd08;

struct thor_es_draw_stream_layout {
  u32 object{};
  u32 buffer0{};
  u32 buffer1{};
  u32 write{};
  u32 flags{};
  u32 published{};
};

struct thor_es_draw_stream_snapshot {
  std::vector<u8> bytes;
  thor_es_draw_stream_layout layout{};
  u64 generation{};
  bool valid{};
};

struct thor_es_draw_stream_probe_state {
  std::mutex mutex;
  std::array<thor_es_draw_stream_snapshot, 2> snapshots;
  thor_es_draw_stream_layout layout{};
  thor_es_draw_stream_layout consumer_layout{};
  thor_es_draw_stream_layout selector_restore_layout{};
  u64 generation{};
  u64 captures{};
  u64 comparisons{};
  u64 matches{};
  u64 mismatches{};
  u64 invalid_layouts{};
  u64 previous_generation_consumers{};
  u64 selector_repairs{};
  u64 selector_repair_failures{};
  u64 selector_restores{};
  u64 selector_restore_failures{};
  u64 selector_restore_generation{};
  u64 producer_work_posts{};
  u64 consumer_work_waits{};
  u64 producer_prior_completion_waits{};
  u64 consumer_completion_posts{};
  u64 producer_completion_waits{};
  u64 producer_completion_restores{};
  u64 sequence_anomalies{};
  u64 last_summary_us{};
  u32 semaphore_id{};
  u32 completion_semaphore_id{};
  u32 current_slot{umax};
  u32 previous_slot{umax};
  u32 consumer_slot{umax};
  u64 consumer_generation{};
  u32 first_mismatch{umax};
  bool consumer_from_previous{};
  bool consumer_checked{};
  bool consumer_match{};
  bool selector_restore_pending{};
  bool valid{};
};

static thor_es_draw_stream_probe_state g_thor_es_draw_stream_probe;

enum class thor_es_draw_stream_probe_mode : u32 {
  disabled,
  verify,
  repair,
};

static thor_es_draw_stream_probe_mode
parse_thor_es_draw_stream_probe_mode(std::string_view value) {
  if (value == "repair" || value == "fix") {
    return thor_es_draw_stream_probe_mode::repair;
  }

  if (value == "1" || value == "on" || value == "true" ||
      value == "profile" || value == "verify") {
    return thor_es_draw_stream_probe_mode::verify;
  }

  return thor_es_draw_stream_probe_mode::disabled;
}

static thor_es_draw_stream_probe_mode get_thor_es_draw_stream_probe_mode() {
  static const thor_es_draw_stream_probe_mode mode = [] {
#ifdef ANDROID
    char property_value[PROP_VALUE_MAX]{};
    const int property_length = __system_property_get(
        "debug.rpcsx.thor.es_draw_stream_probe", property_value);
    if (property_length > 0) {
      return parse_thor_es_draw_stream_probe_mode(
          std::string_view{property_value, static_cast<usz>(property_length)});
    }
#endif

    if (const char *value = std::getenv("RPCSX_THOR_ES_DRAW_STREAM_PROBE")) {
      return parse_thor_es_draw_stream_probe_mode(value);
    }

    return thor_es_draw_stream_probe_mode::disabled;
  }();

  return mode;
}

static FORCE_INLINE bool thor_es_draw_stream_probe_enabled() {
  return get_thor_es_draw_stream_probe_mode() !=
         thor_es_draw_stream_probe_mode::disabled;
}

static FORCE_INLINE bool thor_es_draw_stream_repair_enabled() {
  return get_thor_es_draw_stream_probe_mode() ==
         thor_es_draw_stream_probe_mode::repair;
}

static const char *get_thor_es_draw_stream_probe_mode_name() {
  switch (get_thor_es_draw_stream_probe_mode()) {
  case thor_es_draw_stream_probe_mode::verify:
    return "verify";
  case thor_es_draw_stream_probe_mode::repair:
    return "repair";
  default:
    return "disabled";
  }
}

static bool read_thor_es_draw_stream_u32(u32 address, u32 &value) {
  be_t<u32> guest_value{};
  if (!vm::try_access(address, &guest_value, sizeof(guest_value), false)) {
    return false;
  }

  value = guest_value;
  return true;
}

static bool write_thor_es_draw_stream_selector(u32 object, u32 flags) {
  if (object > 0xffff'ffffu - 0x20) {
    return false;
  }

  be_t<u32> guest_flags = flags;
  return vm::try_access(object + 0x20, &guest_flags, sizeof(guest_flags), true);
}

static bool get_thor_es_draw_stream_layout(u32 object,
                                           thor_es_draw_stream_layout &layout) {
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
  layout.published = layout.flags & 1 ? layout.buffer0 : layout.buffer1;
  return layout.published && vm::check_addr(layout.published, vm::page_readable,
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

static u32
find_thor_es_draw_stream_snapshot(const thor_es_draw_stream_probe_state &state,
                                  u32 object, u32 published) {
  u32 result = umax;
  for (u32 index = 0; index < state.snapshots.size(); index++) {
    const auto &snapshot = state.snapshots[index];
    if (!snapshot.valid || snapshot.layout.object != object ||
        snapshot.layout.published != published) {
      continue;
    }

    if (result == umax ||
        snapshot.generation > state.snapshots[result].generation) {
      result = index;
    }
  }

  return result;
}

static u32 choose_thor_es_draw_stream_snapshot(
    const thor_es_draw_stream_probe_state &state, u32 object, u32 published) {
  if (const u32 matching =
          find_thor_es_draw_stream_snapshot(state, object, published);
      matching != umax) {
    return matching;
  }

  for (u32 index = 0; index < state.snapshots.size(); index++) {
    if (!state.snapshots[index].valid) {
      return index;
    }
  }

  return state.snapshots[0].generation <= state.snapshots[1].generation ? 0 : 1;
}

static bool parse_thor_es_draw_stream_fault_word(std::string_view message,
                                                 u32 &word) {
  constexpr std::string_view marker = "unknown draw command";
  const usz marker_pos = message.find(marker);
  if (marker_pos == std::string_view::npos) {
    return false;
  }

  const usz open = message.find('(', marker_pos + marker.size());
  const usz close = open == std::string_view::npos
                        ? std::string_view::npos
                        : message.find(')', open + 1);
  if (open == std::string_view::npos || close == std::string_view::npos ||
      close == open + 1) {
    return false;
  }

  std::string_view value = message.substr(open + 1, close - open - 1);
  if (value.starts_with("0x") || value.starts_with("0X")) {
    value.remove_prefix(2);
  }
  if (value.empty()) {
    return false;
  }

  const auto result =
      std::from_chars(value.data(), value.data() + value.size(), word, 16);
  return result.ec == std::errc{} && result.ptr == value.data() + value.size();
}

struct thor_es_draw_stream_word_scan {
  u64 count{};
  u32 first_offset{umax};
};

static thor_es_draw_stream_word_scan
scan_thor_es_draw_stream_word(const u8 *bytes, usz size, u32 word) {
  thor_es_draw_stream_word_scan result{};
  for (u32 offset = 0; offset + sizeof(u32) <= size; offset += sizeof(u32)) {
    const u32 current = static_cast<u32>(bytes[offset]) << 24 |
                        static_cast<u32>(bytes[offset + 1]) << 16 |
                        static_cast<u32>(bytes[offset + 2]) << 8 |
                        static_cast<u32>(bytes[offset + 3]);
    if (current != word) {
      continue;
    }

    if (result.first_offset == umax) {
      result.first_offset = offset;
    }
    result.count++;
  }

  return result;
}

static void
log_thor_es_draw_stream_summary(const ppu_thread &ppu, const char *stage,
                                const thor_es_draw_stream_probe_state &state,
                                bool force = false) {
  const u64 now = get_system_time();
  if (!force && state.last_summary_us &&
      now - state.last_summary_us < 2'000'000) {
    return;
  }

  g_thor_es_draw_stream_probe.last_summary_us = now;
  sys_semaphore.notice(
      "Eternal Sonata draw-stream probe: mode=%s stage=%s generation=%llu "
      "object=0x%x published=0x%x flags=0x%x write=0x%x sem_id=0x%x "
      "captures=%llu comparisons=%llu matches=%llu mismatches=%llu "
      "invalid_layouts=%llu previous_consumers=%llu selector_repairs=%llu "
      "selector_repair_failures=%llu selector_restores=%llu "
      "selector_restore_failures=%llu selector_restore_pending=%u "
      "work_posts=%llu "
      "work_waits=%llu prior_completion_waits=%llu completion_posts=%llu "
      "completion_waits=%llu completion_restores=%llu sequence_anomalies=%llu "
      "cia=0x%x lr=0x%x",
      get_thor_es_draw_stream_probe_mode_name(), stage, state.generation,
      state.layout.object, state.layout.published, state.layout.flags,
      state.layout.write, state.semaphore_id,
      state.captures, state.comparisons, state.matches, state.mismatches,
      state.invalid_layouts, state.previous_generation_consumers,
      state.selector_repairs, state.selector_repair_failures,
      state.selector_restores, state.selector_restore_failures,
      state.selector_restore_pending,
      state.producer_work_posts, state.consumer_work_waits,
      state.producer_prior_completion_waits, state.consumer_completion_posts,
      state.producer_completion_waits, state.producer_completion_restores,
      state.sequence_anomalies, ppu.cia, static_cast<u32>(ppu.lr));
}

static void log_thor_es_draw_stream_layout_mismatch(
    const ppu_thread &ppu, const thor_es_draw_stream_probe_state &state,
    const thor_es_draw_stream_layout &consumer) {
  const auto *previous = state.previous_slot < state.snapshots.size()
                             ? &state.snapshots[state.previous_slot]
                             : nullptr;
  sys_semaphore.error(
      "Eternal Sonata draw-stream layout mismatch: generation=%llu "
      "producer_object=0x%x producer_buffer0=0x%x producer_buffer1=0x%x "
      "producer_write=0x%x producer_flags=0x%x producer_published=0x%x "
      "previous_generation=%llu previous_published=0x%x "
      "consumer_object=0x%x consumer_buffer0=0x%x consumer_buffer1=0x%x "
      "consumer_write=0x%x consumer_flags=0x%x consumer_published=0x%x "
      "work_posts=%llu work_waits=%llu prior_completion_waits=%llu "
      "completion_posts=%llu completion_waits=%llu completion_restores=%llu "
      "sequence_anomalies=%llu cia=0x%x lr=0x%x",
      state.generation, state.layout.object, state.layout.buffer0,
      state.layout.buffer1, state.layout.write, state.layout.flags,
      state.layout.published,
      previous && previous->valid ? previous->generation : 0,
      previous && previous->valid ? previous->layout.published : 0,
      consumer.object, consumer.buffer0, consumer.buffer1, consumer.write,
      consumer.flags, consumer.published, state.producer_work_posts,
      state.consumer_work_waits, state.producer_prior_completion_waits,
      state.consumer_completion_posts, state.producer_completion_waits,
      state.producer_completion_restores, state.sequence_anomalies, ppu.cia,
      static_cast<u32>(ppu.lr));
}

static void
thor_es_draw_stream_probe_before_work_post_enabled(const ppu_thread &ppu,
                                                   u32 sem_id, s32 count) {
  if (count != 1 || Emu.GetTitleID() != "BLUS30161" ||
      ppu.cia != thor_es_draw_stream_post_cia ||
      static_cast<u32>(ppu.lr) != thor_es_draw_stream_producer_work_post_lr) {
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
  const u32 snapshot_slot = choose_thor_es_draw_stream_snapshot(
      state, layout.object, layout.published);
  auto &snapshot = state.snapshots[snapshot_slot];
  if (get_thor_es_draw_stream_probe_mode() ==
      thor_es_draw_stream_probe_mode::verify) {
    snapshot.bytes.resize(thor_es_draw_stream_size);
    if (!vm::try_access(layout.published, snapshot.bytes.data(),
                        thor_es_draw_stream_size, false)) {
      state.valid = false;
      state.invalid_layouts++;
      log_thor_es_draw_stream_summary(ppu, "producer-copy-failed", state,
                                      true);
      return;
    }
  } else {
    // Repair mode tracks only the two alternating layouts. Avoid copying and
    // comparing 1.5 MiB every frame on the handheld.
    snapshot.bytes.clear();
  }

  if (state.producer_work_posts &&
      (state.consumer_work_waits != state.producer_work_posts ||
       state.producer_prior_completion_waits != state.producer_work_posts ||
       state.consumer_completion_posts != state.producer_work_posts ||
       state.producer_completion_waits != state.producer_work_posts ||
       state.producer_completion_restores != state.producer_work_posts)) {
    state.sequence_anomalies++;
    log_thor_es_draw_stream_summary(ppu, "producer-sequence-anomaly", state,
                                    true);
  }

  state.previous_slot = state.current_slot != snapshot_slot
                            ? state.current_slot
                            : state.previous_slot;
  state.current_slot = snapshot_slot;
  state.layout = layout;
  state.semaphore_id = sem_id;
  state.generation++;
  snapshot.layout = layout;
  snapshot.generation = state.generation;
  snapshot.valid = true;
  state.captures++;
  state.producer_work_posts++;
  state.valid = true;
  log_thor_es_draw_stream_summary(ppu, "producer-snapshot", state,
                                  state.generation == 1);
}

static bool can_repair_thor_es_draw_stream_selector(
    const thor_es_draw_stream_probe_state &state,
    const thor_es_draw_stream_layout &consumer) {
  if (!thor_es_draw_stream_repair_enabled() || !state.producer_work_posts ||
      state.current_slot >= state.snapshots.size() ||
      state.previous_slot >= state.snapshots.size() ||
      state.selector_restore_pending) {
    return false;
  }

  const auto &current = state.snapshots[state.current_slot];
  const auto &previous = state.snapshots[state.previous_slot];
  if (!current.valid || !previous.valid ||
      current.generation != state.generation ||
      previous.generation + 1 != current.generation) {
    return false;
  }

  // Mask only the exact race observed on Thor: one work token is pending, all
  // completion edges are from the immediately preceding generation, and the
  // shared object already describes the other alternating slot. The producer
  // can prepare that next slot before blocking on completion, so only the
  // consumer selector bit may be changed. The producer-owned write pointer
  // must remain untouched and the selector must be restored before wakeup.
  const bool exact_sequence =
      state.consumer_work_waits + 1 == state.producer_work_posts &&
      state.producer_prior_completion_waits + 1 ==
          state.producer_work_posts &&
      state.consumer_completion_posts + 1 == state.producer_work_posts &&
      state.producer_completion_waits + 1 == state.producer_work_posts &&
      state.producer_completion_restores + 1 == state.producer_work_posts;
  const bool stable_buffers =
      consumer.object == current.layout.object &&
      consumer.buffer0 == current.layout.buffer0 &&
      consumer.buffer1 == current.layout.buffer1;
  const bool exact_previous_layout =
      consumer.write == previous.layout.write &&
      consumer.flags == previous.layout.flags &&
      consumer.published == previous.layout.published;
  const bool one_selector_toggle =
      (consumer.flags ^ current.layout.flags) == 1 &&
      consumer.published != current.layout.published;

  return exact_sequence && stable_buffers && exact_previous_layout &&
         one_selector_toggle;
}

static bool repair_thor_es_draw_stream_selector(
    const ppu_thread &ppu, thor_es_draw_stream_probe_state &state,
    thor_es_draw_stream_layout &consumer) {
  if (!can_repair_thor_es_draw_stream_selector(state, consumer)) {
    return false;
  }

  const thor_es_draw_stream_layout observed = consumer;
  const thor_es_draw_stream_layout expected = state.layout;
  if (!write_thor_es_draw_stream_selector(expected.object, expected.flags) ||
      !get_thor_es_draw_stream_layout(expected.object, consumer) ||
      consumer.buffer0 != observed.buffer0 ||
      consumer.buffer1 != observed.buffer1 ||
      consumer.write != observed.write || consumer.flags != expected.flags ||
      consumer.published != expected.published) {
    // A failed verification must not leave the selector masked. The write
    // pointer is never part of this rollback because repair does not own it.
    write_thor_es_draw_stream_selector(expected.object, observed.flags);
    state.selector_repair_failures++;
    sys_semaphore.error(
        "Eternal Sonata draw-stream selector repair failed: generation=%llu "
        "object=0x%x observed_write=0x%x observed_flags=0x%x "
        "observed_published=0x%x expected_write=0x%x expected_flags=0x%x "
        "expected_published=0x%x failures=%llu cia=0x%x lr=0x%x",
        state.generation, expected.object, observed.write, observed.flags,
        observed.published, expected.write, expected.flags, expected.published,
        state.selector_repair_failures, ppu.cia, static_cast<u32>(ppu.lr));
    return false;
  }

  state.selector_repairs++;
  state.selector_restore_layout = observed;
  state.selector_restore_generation = state.generation;
  state.selector_restore_pending = true;
  sys_semaphore.notice(
      "Eternal Sonata draw-stream selector repaired: generation=%llu "
      "object=0x%x observed_write=0x%x observed_flags=0x%x "
      "observed_published=0x%x repaired_write=0x%x repaired_flags=0x%x "
      "repaired_published=0x%x repairs=%llu restore_pending=1 "
      "work_posts=%llu work_waits=%llu cia=0x%x lr=0x%x",
      state.generation, expected.object, observed.write, observed.flags,
      observed.published, consumer.write, consumer.flags, consumer.published,
      state.selector_repairs, state.producer_work_posts,
      state.consumer_work_waits + 1, ppu.cia, static_cast<u32>(ppu.lr));
  return true;
}

static bool restore_thor_es_draw_stream_selector(
    const ppu_thread &ppu, thor_es_draw_stream_probe_state &state) {
  if (!state.selector_restore_pending) {
    return true;
  }

  const thor_es_draw_stream_layout restore = state.selector_restore_layout;
  thor_es_draw_stream_layout masked = restore;
  masked.flags = state.layout.flags;
  masked.published = state.layout.published;
  thor_es_draw_stream_layout masked_live{};
  thor_es_draw_stream_layout restored_live{};
  const bool exact_generation =
      state.selector_restore_generation == state.generation &&
      state.consumer_generation == state.generation;
  const bool masked_state =
      get_thor_es_draw_stream_layout(masked.object, masked_live) &&
      masked_live.buffer0 == restore.buffer0 &&
      masked_live.buffer1 == restore.buffer1 &&
      masked_live.flags == masked.flags &&
      masked_live.published == masked.published;
  const bool restored =
      exact_generation && masked_state &&
      write_thor_es_draw_stream_selector(restore.object, restore.flags) &&
      get_thor_es_draw_stream_layout(restore.object, restored_live) &&
      restored_live.buffer0 == restore.buffer0 &&
      restored_live.buffer1 == restore.buffer1 &&
      restored_live.write == masked_live.write &&
      restored_live.flags == restore.flags &&
      restored_live.published == restore.published;

  state.selector_restore_pending = false;
  if (!restored) {
    state.selector_restore_failures++;
    sys_semaphore.error(
        "Eternal Sonata draw-stream selector restore failed: "
        "generation=%llu restore_generation=%llu object=0x%x "
        "masked_write=0x%x masked_flags=0x%x masked_published=0x%x "
        "restore_write=0x%x restore_flags=0x%x restore_published=0x%x "
        "live_write=0x%x live_flags=0x%x live_published=0x%x "
        "exact_generation=%u masked_state=%u failures=%llu cia=0x%x lr=0x%x",
        state.generation, state.selector_restore_generation, masked.object,
        masked.write, masked.flags, masked.published, restore.write,
        restore.flags, restore.published, restored_live.write,
        restored_live.flags, restored_live.published, exact_generation,
        masked_state,
        state.selector_restore_failures, ppu.cia, static_cast<u32>(ppu.lr));
    return false;
  }

  state.selector_restores++;
  sys_semaphore.notice(
      "Eternal Sonata draw-stream selector restored: generation=%llu "
      "object=0x%x masked_write=0x%x masked_flags=0x%x "
      "masked_published=0x%x restored_write=0x%x restored_flags=0x%x "
      "restored_published=0x%x restores=%llu work_posts=%llu "
      "completion_posts=%llu cia=0x%x lr=0x%x",
      state.generation, masked.object, masked.write, masked.flags,
      masked.published, restored_live.write, restored_live.flags,
      restored_live.published,
      state.selector_restores, state.producer_work_posts,
      state.consumer_completion_posts + 1, ppu.cia,
      static_cast<u32>(ppu.lr));
  return true;
}

static void
thor_es_draw_stream_probe_after_consumer_wait_enabled(const ppu_thread &ppu,
                                                      u32 sem_id) {
  if (Emu.GetTitleID() != "BLUS30161" ||
      ppu.cia != thor_es_draw_stream_wait_cia ||
      static_cast<u32>(ppu.lr) != thor_es_draw_stream_consumer_work_wait_lr) {
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
      state.semaphore_id != sem_id) {
    state.invalid_layouts++;
    state.consumer_layout = layout;
    state.consumer_slot = umax;
    state.consumer_generation = 0;
    state.first_mismatch = umax;
    state.consumer_from_previous = false;
    state.consumer_checked = false;
    state.consumer_match = false;
    log_thor_es_draw_stream_summary(ppu, "consumer-layout-mismatch", state,
                                    true);
    log_thor_es_draw_stream_layout_mismatch(ppu, state, layout);
    return;
  }

  repair_thor_es_draw_stream_selector(ppu, state, layout);
  state.consumer_work_waits++;
  state.consumer_layout = layout;
  state.consumer_slot =
      find_thor_es_draw_stream_snapshot(state, layout.object, layout.published);
  state.consumer_generation = 0;
  state.first_mismatch = umax;
  state.consumer_from_previous = false;
  state.consumer_checked = false;
  state.consumer_match = false;
  if (state.consumer_slot == umax) {
    state.invalid_layouts++;
    log_thor_es_draw_stream_summary(ppu, "consumer-layout-mismatch", state,
                                    true);
    log_thor_es_draw_stream_layout_mismatch(ppu, state, layout);
    return;
  }

  const auto &snapshot = state.snapshots[state.consumer_slot];
  state.consumer_generation = snapshot.generation;
  state.consumer_from_previous = state.consumer_slot != state.current_slot &&
                                 snapshot.generation < state.generation;
  if (state.consumer_from_previous) {
    state.previous_generation_consumers++;
    log_thor_es_draw_stream_summary(ppu, "consumer-previous-generation", state,
                                    true);
  }

  if (get_thor_es_draw_stream_probe_mode() ==
      thor_es_draw_stream_probe_mode::repair) {
    log_thor_es_draw_stream_summary(ppu, "consumer-repair-mode", state);
    return;
  }

  const u8 *live = vm::get_super_ptr<u8>(layout.published);
  state.comparisons++;
  state.consumer_checked = true;
  state.consumer_match =
      std::memcmp(snapshot.bytes.data(), live, thor_es_draw_stream_size) == 0;
  if (state.consumer_match) {
    state.matches++;
    log_thor_es_draw_stream_summary(ppu, "consumer-match", state);
    return;
  }

  state.mismatches++;
  state.first_mismatch = 0;
  while (state.first_mismatch < thor_es_draw_stream_size &&
         snapshot.bytes[state.first_mismatch] == live[state.first_mismatch]) {
    state.first_mismatch++;
  }

  const u32 aligned_offset = state.first_mismatch & ~3u;
  const u32 producer_word =
      get_thor_es_draw_stream_snapshot_word(snapshot.bytes, aligned_offset);
  u32 live_word = 0;
  read_thor_es_draw_stream_u32(layout.published + aligned_offset, live_word);
  sys_semaphore.error(
      "Eternal Sonata draw-stream handoff mismatch: generation=%llu "
      "consumer_generation=%llu consumer_from_previous=%u "
      "object=0x%x published=0x%x first_byte=0x%x word_offset=0x%x "
      "producer_word=0x%x consumer_word=0x%x comparisons=%llu "
      "mismatches=%llu work_posts=%llu work_waits=%llu "
      "prior_completion_waits=%llu completion_posts=%llu "
      "completion_waits=%llu completion_restores=%llu cia=0x%x lr=0x%x",
      state.generation, state.consumer_generation, state.consumer_from_previous,
      layout.object, layout.published, state.first_mismatch, aligned_offset,
      producer_word, live_word, state.comparisons, state.mismatches,
      state.producer_work_posts, state.consumer_work_waits,
      state.producer_prior_completion_waits, state.consumer_completion_posts,
      state.producer_completion_waits, state.producer_completion_restores,
      ppu.cia, static_cast<u32>(ppu.lr));
}

static FORCE_INLINE void
maybe_thor_es_draw_stream_probe_before_post(const ppu_thread &ppu, u32 sem_id,
                                            s32 count) {
  if (!thor_es_draw_stream_probe_enabled() || count != 1 ||
      Emu.GetTitleID() != "BLUS30161" ||
      ppu.cia != thor_es_draw_stream_post_cia) {
    return;
  }

  const u32 lr = static_cast<u32>(ppu.lr);
  if (lr == thor_es_draw_stream_producer_work_post_lr) {
    thor_es_draw_stream_probe_before_work_post_enabled(ppu, sem_id, count);
    return;
  }

  u32 object = 0;
  if (lr == thor_es_draw_stream_consumer_completion_post_lr) {
    object = static_cast<u32>(ppu.gpr[22]);
  } else if (lr == thor_es_draw_stream_producer_completion_restore_lr) {
    object = static_cast<u32>(ppu.gpr[28]);
  } else {
    return;
  }

  std::lock_guard lock(g_thor_es_draw_stream_probe.mutex);
  auto &state = g_thor_es_draw_stream_probe;
  if (!state.valid || !object || object != state.layout.object ||
      (state.completion_semaphore_id &&
       state.completion_semaphore_id != sem_id)) {
    return;
  }

  state.completion_semaphore_id = sem_id;
  if (lr == thor_es_draw_stream_consumer_completion_post_lr) {
    restore_thor_es_draw_stream_selector(ppu, state);
    state.consumer_completion_posts++;
  } else {
    state.producer_completion_restores++;
  }
}

static FORCE_INLINE void
maybe_thor_es_draw_stream_probe_after_wait(const ppu_thread &ppu, u32 sem_id) {
  if (!thor_es_draw_stream_probe_enabled() || Emu.GetTitleID() != "BLUS30161" ||
      ppu.cia != thor_es_draw_stream_wait_cia) {
    return;
  }

  const u32 lr = static_cast<u32>(ppu.lr);
  if (lr == thor_es_draw_stream_consumer_work_wait_lr) {
    thor_es_draw_stream_probe_after_consumer_wait_enabled(ppu, sem_id);
    return;
  }

  u32 object = 0;
  if (lr == thor_es_draw_stream_producer_prior_completion_wait_lr) {
    const u32 semaphore_wrapper = static_cast<u32>(ppu.gpr[29]);
    object = semaphore_wrapper >= 0x38 ? semaphore_wrapper - 0x38 : 0;
  } else if (lr == thor_es_draw_stream_producer_completion_wait_lr) {
    object = static_cast<u32>(ppu.gpr[28]);
  } else {
    return;
  }

  std::lock_guard lock(g_thor_es_draw_stream_probe.mutex);
  auto &state = g_thor_es_draw_stream_probe;
  if (!state.valid || !object || object != state.layout.object ||
      (state.completion_semaphore_id &&
       state.completion_semaphore_id != sem_id)) {
    return;
  }

  state.completion_semaphore_id = sem_id;
  if (lr == thor_es_draw_stream_producer_prior_completion_wait_lr) {
    state.producer_prior_completion_waits++;
  } else {
    state.producer_completion_waits++;
  }
}

} // namespace

void thor_es_draw_stream_probe_tty(const ppu_thread &ppu,
                                   std::string_view message) {
  if (!thor_es_draw_stream_probe_enabled() || Emu.GetTitleID() != "BLUS30161" ||
      message.find("unknown draw command") == std::string_view::npos) {
    return;
  }

  u32 fault_word = 0;
  const bool fault_word_parsed =
      parse_thor_es_draw_stream_fault_word(message, fault_word);

  std::lock_guard lock(g_thor_es_draw_stream_probe.mutex);
  const auto &state = g_thor_es_draw_stream_probe;
  const auto *snapshot = state.consumer_slot < state.snapshots.size()
                             ? &state.snapshots[state.consumer_slot]
                             : nullptr;
  if (!state.valid || !state.consumer_checked || !snapshot ||
      !snapshot->valid || snapshot->generation != state.consumer_generation ||
      snapshot->bytes.size() != thor_es_draw_stream_size ||
      !vm::check_addr(state.consumer_layout.published, vm::page_readable,
                      thor_es_draw_stream_size)) {
    sys_semaphore.error(
        "Eternal Sonata draw-stream parser fault outside snapshot: "
        "generation=%llu fault_word=0x%x fault_word_parsed=%u "
        "producer_object=0x%x producer_published=0x%x "
        "consumer_generation=%llu consumer_object=0x%x "
        "consumer_published=0x%x valid=%u checked=%u match=%u "
        "selector_repairs=%llu selector_repair_failures=%llu "
        "selector_restores=%llu selector_restore_failures=%llu "
        "selector_restore_pending=%u "
        "work_posts=%llu work_waits=%llu prior_completion_waits=%llu "
        "completion_posts=%llu completion_waits=%llu completion_restores=%llu "
        "sequence_anomalies=%llu cia=0x%x lr=0x%x",
        state.generation, fault_word, fault_word_parsed, state.layout.object,
        state.layout.published, state.consumer_generation,
        state.consumer_layout.object, state.consumer_layout.published,
        state.valid, state.consumer_checked, state.consumer_match,
        state.selector_repairs, state.selector_repair_failures,
        state.selector_restores, state.selector_restore_failures,
        state.selector_restore_pending,
        state.producer_work_posts, state.consumer_work_waits,
        state.producer_prior_completion_waits, state.consumer_completion_posts,
        state.producer_completion_waits, state.producer_completion_restores,
        state.sequence_anomalies, ppu.cia, static_cast<u32>(ppu.lr));
    return;
  }

  const u8 *live = vm::get_super_ptr<u8>(state.consumer_layout.published);
  const bool fault_buffer_match =
      std::memcmp(snapshot->bytes.data(), live, thor_es_draw_stream_size) == 0;
  u32 fault_first_mismatch = umax;
  if (!fault_buffer_match) {
    fault_first_mismatch = 0;
    while (fault_first_mismatch < thor_es_draw_stream_size &&
           snapshot->bytes[fault_first_mismatch] ==
               live[fault_first_mismatch]) {
      fault_first_mismatch++;
    }
  }

  const u32 mismatch_word_offset =
      fault_first_mismatch == umax ? umax : fault_first_mismatch & ~3u;
  const u32 producer_mismatch_word =
      fault_first_mismatch == umax ? 0
                                   : get_thor_es_draw_stream_snapshot_word(
                                         snapshot->bytes, mismatch_word_offset);
  u32 live_mismatch_word = 0;
  if (fault_first_mismatch != umax) {
    read_thor_es_draw_stream_u32(state.consumer_layout.published +
                                     mismatch_word_offset,
                                 live_mismatch_word);
  }

  const thor_es_draw_stream_word_scan producer_fault =
      fault_word_parsed
          ? scan_thor_es_draw_stream_word(snapshot->bytes.data(),
                                          snapshot->bytes.size(), fault_word)
          : thor_es_draw_stream_word_scan{};
  const thor_es_draw_stream_word_scan live_fault =
      fault_word_parsed ? scan_thor_es_draw_stream_word(
                              live, thor_es_draw_stream_size, fault_word)
                        : thor_es_draw_stream_word_scan{};

  sys_semaphore.error(
      "Eternal Sonata draw-stream parser fault: generation=%llu "
      "consumer_generation=%llu consumer_from_previous=%u "
      "producer_object=0x%x producer_buffer0=0x%x producer_buffer1=0x%x "
      "producer_write=0x%x producer_flags=0x%x producer_published=0x%x "
      "consumer_object=0x%x consumer_buffer0=0x%x consumer_buffer1=0x%x "
      "consumer_write=0x%x consumer_flags=0x%x consumer_published=0x%x "
      "fault_word=0x%x fault_word_parsed=%u "
      "fault_buffer_match=%u fault_first_mismatch=0x%x "
      "mismatch_word_offset=0x%x producer_mismatch_word=0x%x "
      "live_mismatch_word=0x%x producer_fault_count=%llu "
      "producer_fault_first=0x%x live_fault_count=%llu live_fault_first=0x%x "
      "handoff_checked=%u handoff_match=%u handoff_first_mismatch=0x%x "
      "work_posts=%llu work_waits=%llu prior_completion_waits=%llu "
      "completion_posts=%llu completion_waits=%llu completion_restores=%llu "
      "sequence_anomalies=%llu "
      "cia=0x%x lr=0x%x",
      state.generation, state.consumer_generation, state.consumer_from_previous,
      state.layout.object, state.layout.buffer0, state.layout.buffer1,
      state.layout.write, state.layout.flags, state.layout.published,
      state.consumer_layout.object, state.consumer_layout.buffer0,
      state.consumer_layout.buffer1, state.consumer_layout.write,
      state.consumer_layout.flags, state.consumer_layout.published, fault_word,
      fault_word_parsed, fault_buffer_match, fault_first_mismatch,
      mismatch_word_offset, producer_mismatch_word, live_mismatch_word,
      producer_fault.count, producer_fault.first_offset, live_fault.count,
      live_fault.first_offset, state.consumer_checked, state.consumer_match,
      state.first_mismatch, state.producer_work_posts,
      state.consumer_work_waits, state.producer_prior_completion_waits,
      state.consumer_completion_posts, state.producer_completion_waits,
      state.producer_completion_restores, state.sequence_anomalies, ppu.cia,
      static_cast<u32>(ppu.lr));
}
#else
static FORCE_INLINE constexpr void
maybe_thor_es_draw_stream_probe_before_post(const ppu_thread &, u32,
                                             s32) noexcept {}

static FORCE_INLINE constexpr void
maybe_thor_es_draw_stream_probe_after_wait(const ppu_thread &, u32) noexcept {
}
#endif

#if !defined(__ANDROID__) || defined(RPCSX_THOR_SEMA_SUPERPATH)
static thor_es_sema_superpath_mode
parse_thor_es_sema_superpath_mode(std::string_view value) {
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
  // acq_rel keeps the pointer clear from floating above the id clear. The
  // window this closes is benign on its own - a reader that sees a stale id and
  // an already-nulled pointer just returns nullptr - but leaving one relaxed
  // access in a three-operation protocol is how the next reader of this code
  // concludes the whole thing is relaxed by design.
  if (fast_entry.sem_id.compare_exchange_strong(expected, 0,
                                                std::memory_order_acq_rel)) {
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
  // Publish-then-flag. The pointer must be visible to any reader that observes
  // the id, so the id store is a *release* and the pointer store stays relaxed
  // underneath it.
  //
  // Both were relaxed, which is correct on x86 and a data race here. TSO does
  // not reorder store-store, so a reader that saw the new id was guaranteed to
  // see the pointer written before it. AArch64 makes no such promise: with
  // relaxed ordering the id can become visible first, and the reader then
  // matches the id and dereferences a stale or null lv2_sema*.
  entry.sema.store(sema, std::memory_order_relaxed);
  entry.sem_id.store(sem_id, std::memory_order_release);
}

static lv2_sema *get_thor_es_sema_fast_object(u32 sem_id) {
  const u32 index = get_thor_es_sema_index(sem_id);
  if (index >= lv2_sema::id_count) {
    return nullptr;
  }

  auto &entry =
      g_thor_es_sema_fast_cache[index % g_thor_es_sema_fast_cache.size()];
  // Acquire, pairing with the release in record_thor_es_sema_fast_object. This
  // is the other half of the same race: relaxed permits the pointer load to be
  // satisfied *before* the id load, so the validation would run against a
  // pointer read earlier than the check that is supposed to authorise it.
  //
  // Acquire is one-way and that is all this needs - everything sequenced before
  // the matching release becomes visible. No StoreLoad guarantee is required
  // here, so the RCpc LDAPR that armv8.4 selects for an explicit acquire is
  // sufficient; see the RCsc note in docs/arm64/memory-model.md for the case
  // where it would not be.
  if (entry.sem_id.load(std::memory_order_acquire) != sem_id) {
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
#endif

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
#if !defined(__ANDROID__) || defined(RPCSX_THOR_SEMA_SUPERPATH)
  record_thor_es_sema_created_id(created_id);
#endif
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

#if !defined(__ANDROID__) || defined(RPCSX_THOR_SEMA_SUPERPATH)
  record_thor_es_sema_destroyed_id(sem_id);
#endif
  return CELL_OK;
}

error_code sys_semaphore_wait(ppu_thread &ppu, u32 sem_id, u64 timeout) {
  ppu.state += cpu_flag::wait;

  sys_semaphore.trace("sys_semaphore_wait(sem_id=0x%x, timeout=0x%llx)", sem_id,
                      timeout);

#if !defined(__ANDROID__) || defined(RPCSX_THOR_SEMA_SUPERPATH)
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
      maybe_thor_es_draw_stream_probe_after_wait(ppu, sem_id);
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
#endif

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
#if !defined(__ANDROID__) || defined(RPCSX_THOR_SEMA_SUPERPATH)
    if (is_thor_es_sema_superpath_candidate(ppu, false)) {
      record_thor_es_sema_cached_esrch_id(sem_id);
    }
#endif

    return CELL_ESRCH;
  }

#if !defined(__ANDROID__) || defined(RPCSX_THOR_SEMA_SUPERPATH)
  record_thor_es_sema_fast_object(sem_id, sem.ptr.get());
#endif

  if (sem.ret) {
    THOR_SPURS_PROBE_LOG_PPU_WAIT("sem_wait_ready", ppu, sem_id, timeout,
                                  sem->key, static_cast<u64>(+sem->val),
                                  CELL_OK);
    maybe_thor_es_draw_stream_probe_after_wait(ppu, sem_id);
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

    const usz thor_spin_iters = thor::ppu_spin_iters();
    for (usz i = 0; cpu_flag::signal - ppu.state && i < thor_spin_iters; i++) {
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
  THOR_SPURS_PROBE_LOG_PPU_WAIT("sem_wait_wait", ppu, sem_id, timeout,
                                sem->key, static_cast<u64>(+sem->val),
                                result);
  if (result == CELL_OK) {
    maybe_thor_es_draw_stream_probe_after_wait(ppu, sem_id);
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

#if !defined(__ANDROID__) || defined(RPCSX_THOR_SEMA_SUPERPATH)
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
#endif

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
#if !defined(__ANDROID__) || defined(RPCSX_THOR_SEMA_SUPERPATH)
    if (is_thor_es_sema_superpath_candidate(ppu, true)) {
      record_thor_es_sema_cached_esrch_id(sem_id);
    }
#endif

    return CELL_ESRCH;
  }

#if !defined(__ANDROID__) || defined(RPCSX_THOR_SEMA_SUPERPATH)
  record_thor_es_sema_fast_object(sem_id, sem.ptr.get());
#endif

  if (count <= 0) {
    return CELL_EINVAL;
  }

  lv2_obj::notify_all_t notify;

  if (sem.ret) {
    THOR_SPURS_PROBE_LOG_PPU_WAIT("sem_post_fast", ppu, sem_id,
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

  THOR_SPURS_PROBE_LOG_PPU_WAIT("sem_post", ppu, sem_id,
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
