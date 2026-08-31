#include "stdafx.h"

#include "sys_lwmutex.h"

#include "Emu/IdManager.h"
#include "Emu/System.h"

#include "Emu/Cell/ErrorCodes.h"
#include "Emu/Cell/PPUThread.h"

#include "rx/asm.hpp"

#include "cellos/thor_ppu_wait.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

LOG_CHANNEL(sys_lwmutex);

namespace {
constexpr u32 thor_transformers_main_lwmutex_lock_lr = 0x00e28c5c;
constexpr u32 thor_transformers_main_lwmutex_unlock_lr = 0x00e28c18;
constexpr u32 thor_transformers_main_lwmutex_caller = 0x00dd6264;
constexpr auto thor_transformers_fmod_receiver_name =
    "PPU[0x100000c] FMOD libAudio event receive thread";
constexpr u32 thor_transformers_lv2_lwmutex_trace_limit = 128;
constexpr u32 thor_transformers_post_audio_unlock_trace_limit = 8;
constexpr u32 thor_transformers_reown_scan_limit = 64;
constexpr u32 thor_transformers_audio_owner_candidate_limit = 64;
constexpr u32 thor_transformers_audio_dependency_log_limit = 16;
constexpr u32 thor_transformers_audio_dependency_yield_limit = 4096;

std::atomic<u32> g_thor_transformers_lv2_lwmutex_id{0};
std::atomic<u32> g_thor_transformers_lv2_lwmutex_trace_seq{0};
std::atomic<u32> g_thor_transformers_post_audio_unlock_trace_seq{0};
std::atomic<u32> g_thor_transformers_audio_owner_candidate_seq{0};
std::atomic<u32> g_thor_transformers_audio_dependency_seq{0};
std::atomic<u32> g_thor_transformers_audio_dependency_lwmutex_id{0};
std::atomic<u32> g_thor_transformers_audio_dependency_owner_id{0};
std::atomic<u32> g_thor_transformers_post_audio_lwmutex_id{0};
std::atomic<bool> g_thor_transformers_audio_owner_wake_completed{false};
std::atomic<bool> g_thor_transformers_audio_owner_signal_pending{false};

bool thor_transformers_is_fmod_receiver(const ppu_thread &ppu) {
  return ppu.id == 0x0100'000c &&
         static_cast<std::string>(ppu.thread_name) ==
             thor_transformers_fmod_receiver_name;
}

bool thor_transformers_lv2_lwmutex_trace_enabled() noexcept {
#ifdef __ANDROID__
  static const bool s_on = []() noexcept {
    char value[PROP_VALUE_MAX]{};
    return __system_property_get(
               "debug.rpcsx.thor.transformers_lwmutex_trace", value) > 0 &&
           value[0] && value[0] != '0';
  }();
  return s_on && Emu.GetTitleID() == "BLUS30357";
#else
  return false;
#endif
}

bool thor_transformers_post_audio_unlock_trace_target(
    const ppu_thread &ppu, u32 lwmutex_id) noexcept {
  const u32 post_audio_lwmutex_id =
      g_thor_transformers_post_audio_lwmutex_id.load(std::memory_order_acquire);
  return thor_transformers_lv2_lwmutex_trace_enabled() &&
         ppu.id == 0x0100'0000 &&
         static_cast<u32>(ppu.lr) == thor_transformers_main_lwmutex_unlock_lr &&
         post_audio_lwmutex_id && lwmutex_id == post_audio_lwmutex_id;
}

void thor_transformers_post_audio_unlock_trace(
    const ppu_thread &ppu, u32 lwmutex_id, u32 call, const char *stage,
    const lv2_lwmutex *mutex = nullptr, const ppu_thread *wake_ppu = nullptr) {
  if (call >= thor_transformers_post_audio_unlock_trace_limit) {
    return;
  }

  const auto queue = mutex ? mutex->load_sq() : nullptr;
  const s32 signaled = mutex
                           ? atomic_storage<s32>::load(
                                 mutex->lv2_control.raw().signaled)
                           : 0;
  sys_lwmutex.error(
      "Thor TWC POST AUDIO UNLOCK #%u: stage=%s ppu=0x%x cia=0x%x lr=0x%x "
      "sp=0x%llx id=0x%x signaled=0x%x queue_ppu=0x%x wake_ppu=0x%x",
      call, stage, ppu.id, ppu.cia, static_cast<u32>(ppu.lr), ppu.gpr[1],
      lwmutex_id, static_cast<u32>(signaled), queue ? queue->id : 0,
      wake_ppu ? wake_ppu->id : 0);
}

bool thor_transformers_audio_wake_fix_enabled() noexcept;

ppu_thread *thor_transformers_reown_with_trace(
    lv2_lwmutex &mutex, u32 call) {
  ppu_thread *result = nullptr;
  u32 attempt = 0;

  mutex.lv2_control.fetch_op(
      [&](lv2_lwmutex::control_data_t &data) -> bool {
        result = nullptr;

        const auto head = static_cast<ppu_thread *>(data.sq);
        const auto next = head ? +head->next_cpu : nullptr;
        const u32 state =
            head ? static_cast<u32>((+head->state).raw()) : 0;
        if (attempt < thor_transformers_post_audio_unlock_trace_limit) {
          sys_lwmutex.error(
              "Thor TWC POST AUDIO REOWN #%u.%u: stage=PRE-SCHEDULE "
              "head=0x%x next=0x%x state=0x%x self=%u signaled=0x%x",
              call, attempt, head ? head->id : 0, next ? next->id : 0,
              state, head && next == head ? 1u : 0u,
              static_cast<u32>(data.signaled));
        }
        attempt++;

        if (head) {
          ppu_thread *seen[thor_transformers_reown_scan_limit]{};
          auto scan = head;
          u32 depth = 0;
          u32 repeated_at = thor_transformers_reown_scan_limit;
          while (scan && depth < thor_transformers_reown_scan_limit) {
            for (u32 index = 0; index < depth; index++) {
              if (seen[index] == scan) {
                repeated_at = index;
                break;
              }
            }

            if (repeated_at != thor_transformers_reown_scan_limit) {
              break;
            }

            seen[depth++] = scan;
            scan = +scan->next_cpu;
          }

          const bool cycle =
              repeated_at != thor_transformers_reown_scan_limit;
          const bool limited = !cycle && scan != nullptr;
          if (attempt <= thor_transformers_post_audio_unlock_trace_limit) {
            sys_lwmutex.error(
                "Thor TWC POST AUDIO REOWN #%u.%u: "
                "stage=PRE-SCHEDULE-SCAN depth=%u cycle=%u "
                "repeated_at=%u limited=%u node=0x%x",
                call, attempt - 1, depth, cycle ? 1u : 0u,
                cycle ? repeated_at : 0u, limited ? 1u : 0u,
                scan ? scan->id : 0);
          }

          const bool repairable_self_cycle =
              cycle && depth == 1 && repeated_at == 0 && head && next == head &&
              thor_transformers_is_fmod_receiver(*head) &&
              thor_transformers_audio_wake_fix_enabled();
          if (repairable_self_cycle) {
            result = head;
            data.sq = nullptr;
            sys_lwmutex.error(
                "Thor TWC POST AUDIO REOWN #%u.%u: "
                "stage=REPAIR-SELF-CYCLE waiter=0x%x queue=0x0",
                call, attempt - 1, head->id);
            return true;
          }

          if (cycle || limited) {
            return false;
          }

          result = mutex.schedule<ppu_thread>(data.sq, mutex.protocol, false);

          if (attempt <= thor_transformers_post_audio_unlock_trace_limit) {
            const auto queue = static_cast<ppu_thread *>(data.sq);
            sys_lwmutex.error(
                "Thor TWC POST AUDIO REOWN #%u.%u: stage=POST-SCHEDULE "
                "result=0x%x queue=0x%x unchanged=%u",
                call, attempt - 1, result ? result->id : 0,
                queue ? queue->id : 0, head == queue ? 1u : 0u);
          }

          return head != data.sq;
        }

        data.signaled |= 1;
        return true;
      });

  sys_lwmutex.error(
      "Thor TWC POST AUDIO REOWN #%u: stage=POST-FETCH attempts=%u "
      "result=0x%x",
      call, attempt, result ? result->id : 0);

  if (result && cpu_flag::again - result->state) {
    result->next_cpu = nullptr;
  }

  return result;
}

bool thor_transformers_audio_wake_fix_enabled() noexcept {
#ifdef __ANDROID__
  static const bool s_on = []() noexcept {
    char value[PROP_VALUE_MAX]{};
    return __system_property_get(
               "debug.rpcsx.thor.transformers_audio_wake_fix", value) > 0 &&
           value[0] && value[0] != '0';
  }();
  return s_on && Emu.GetTitleID() == "BLUS30357";
#else
  return false;
#endif
}

stx::shared_ptr<named_thread<ppu_thread>>
thor_transformers_select_live_ppu(u32 ppu_id) {
  if (!ppu_id) {
    return {};
  }

  // Use the live PPU table. A direct ID lookup returned no owner for the
  // second Transformers FMOD lock while the PPU census still contained that
  // thread. This scan uses the same ID-manager lock that the caller holds.
  const auto selected = idm::select<named_thread<ppu_thread>>(
      [ppu_id](u32 candidate_id, named_thread<ppu_thread> &) {
        return candidate_id == ppu_id;
      },
      idm::unlocked);
  return selected.ptr;
}

void thor_transformers_discard_stale_audio_owner_signal(
    ppu_thread &ppu, u32 lwmutex_id) {
  if (!thor_transformers_audio_wake_fix_enabled() ||
      !thor_transformers_is_fmod_receiver(ppu) ||
      !g_thor_transformers_audio_owner_signal_pending.exchange(
          false, std::memory_order_acq_rel)) {
    return;
  }

  const u32 state_before = static_cast<u32>((+ppu.state).raw());
  const bool discarded = ppu.state.test_and_reset(cpu_flag::signal);
  const u32 state_after = static_cast<u32>((+ppu.state).raw());
  sys_lwmutex.error(
      "Thor TWC AUDIO OWNER SIGNAL: ppu=0x%x id=0x%x "
      "state=0x%x->0x%x discarded=%u",
      ppu.id, lwmutex_id, state_before, state_after, discarded ? 1u : 0u);
}

u32 thor_transformers_lv2_lwmutex_caller_lr(const ppu_thread &ppu) noexcept {
  if (static_cast<u32>(ppu.lr) != thor_transformers_main_lwmutex_lock_lr) {
    return 0;
  }

  const u64 stack_pointer = ppu.gpr[1];
  if (stack_pointer > 0xffff'ff7f) {
    return 0;
  }

  const u32 saved_link_address = static_cast<u32>(stack_pointer) + 0x80;
  if (!vm::check_addr(saved_link_address, vm::page_readable)) {
    return 0;
  }

  return static_cast<u32>(vm::read64(saved_link_address));
}

bool thor_transformers_lv2_lwmutex_trace_target(u32 lwmutex_id) noexcept {
  return thor_transformers_lv2_lwmutex_trace_enabled() &&
         g_thor_transformers_lv2_lwmutex_id.load(std::memory_order_relaxed) ==
             lwmutex_id;
}

bool thor_transformers_lv2_lwmutex_trace_arm(const ppu_thread &ppu,
                                             u32 lwmutex_id) {
  if (!thor_transformers_lv2_lwmutex_trace_enabled()) {
    return false;
  }

  u32 target =
      g_thor_transformers_lv2_lwmutex_id.load(std::memory_order_relaxed);
  if (target == lwmutex_id) {
    return true;
  }

  if (target || ppu.id != 0x0100'0000 ||
      static_cast<u32>(ppu.lr) != thor_transformers_main_lwmutex_lock_lr) {
    return false;
  }

  if (!g_thor_transformers_lv2_lwmutex_id.compare_exchange_strong(
          target, lwmutex_id, std::memory_order_relaxed)) {
    return target == lwmutex_id;
  }

  sys_lwmutex.error(
      "Thor TWC LV2 ARM: ppu=0x%x name=\"%s\" cia=0x%x lr=0x%x "
      "sp=0x%llx caller=0x%x id=0x%x",
      ppu.id, static_cast<std::string>(ppu.thread_name), ppu.cia,
      static_cast<u32>(ppu.lr), ppu.gpr[1],
      thor_transformers_lv2_lwmutex_caller_lr(ppu), lwmutex_id);
  return true;
}

void thor_transformers_lv2_lwmutex_trace(const ppu_thread &ppu,
                                         u32 lwmutex_id,
                                         const lv2_lwmutex &mutex,
                                         const char *action, u64 result = 0,
                                         u32 wake_ppu = 0) {
  if (!thor_transformers_lv2_lwmutex_trace_target(lwmutex_id)) {
    return;
  }

  const u32 sequence = g_thor_transformers_lv2_lwmutex_trace_seq.fetch_add(
      1, std::memory_order_relaxed);
  if (sequence >= thor_transformers_lv2_lwmutex_trace_limit) {
    return;
  }

  const auto queue = mutex.load_sq();
  const u32 queue_ppu = queue ? queue->id : 0;
  const s32 signaled =
      atomic_storage<s32>::load(mutex.lv2_control.raw().signaled);
  const u32 control = mutex.control.addr();
  const u32 owner =
      control ? static_cast<u32>(mutex.control->vars.owner.load()) : 0;
  const u32 waiter =
      control ? static_cast<u32>(mutex.control->vars.waiter.load()) : 0;
  const u32 attribute = control ? static_cast<u32>(mutex.control->attribute) : 0;
  const u32 sleep_queue =
      control ? static_cast<u32>(mutex.control->sleep_queue) : 0;

  sys_lwmutex.error(
      "Thor TWC LV2 #%u: %s ppu=0x%x name=\"%s\" cia=0x%x lr=0x%x "
      "sp=0x%llx caller=0x%x id=0x%x control=0x%x owner=0x%x waiter=%u "
      "attribute=0x%x sleepq=0x%x signaled=0x%x queue_ppu=0x%x "
      "wake_ppu=0x%x result=0x%llx",
      sequence, action, ppu.id, static_cast<std::string>(ppu.thread_name),
      ppu.cia, static_cast<u32>(ppu.lr), ppu.gpr[1],
      thor_transformers_lv2_lwmutex_caller_lr(ppu), lwmutex_id, control, owner,
      waiter, attribute, sleep_queue, static_cast<u32>(signaled), queue_ppu,
      wake_ppu, result);
}

bool thor_transformers_discover_audio_dependency(u32 primary_lwmutex_id,
                                                  bool log_miss = true) {
  const auto found = idm::select<lv2_obj, lv2_lwmutex>(
      [&](u32 candidate_lwmutex_id, lv2_lwmutex &candidate) -> bool {
        bool contains_fmod_receiver = false;
        for (auto cpu = candidate.load_sq(); cpu; cpu = cpu->next_cpu) {
          if (thor_transformers_is_fmod_receiver(*cpu)) {
            contains_fmod_receiver = true;
            break;
          }
        }

        if (!contains_fmod_receiver) {
          return false;
        }

        const u32 control = candidate.control.addr();
        const u32 owner_id =
            control
                ? static_cast<u32>(candidate.control->vars.owner.load())
                : 0;
        const auto owner = thor_transformers_select_live_ppu(owner_id);
        const u32 owner_state =
            owner ? static_cast<u32>((+owner->state).raw()) : 0;

        g_thor_transformers_audio_dependency_lwmutex_id.store(
            candidate_lwmutex_id, std::memory_order_relaxed);
        g_thor_transformers_audio_dependency_owner_id.store(
            owner_id, std::memory_order_release);

        const u32 sequence =
            g_thor_transformers_audio_dependency_seq.fetch_add(
                1, std::memory_order_relaxed);
        if (sequence < thor_transformers_audio_dependency_log_limit) {
          sys_lwmutex.error(
              "Thor TWC AUDIO OWNER DEPENDENCY #%u: primary=0x%x "
              "waiter=0x100000c id=0x%x control=0x%x owner=0x%x "
              "owner_state=0x%x phase=queue-scan",
              sequence, primary_lwmutex_id, candidate_lwmutex_id, control,
              owner_id, owner_state);
        }
        return true;
      },
      idm::unlocked);

  if (!found && log_miss) {
    const u32 sequence =
        g_thor_transformers_audio_dependency_seq.fetch_add(
            1, std::memory_order_relaxed);
    if (sequence < thor_transformers_audio_dependency_log_limit) {
      sys_lwmutex.error(
          "Thor TWC AUDIO OWNER DEPENDENCY #%u: primary=0x%x "
          "waiter=0x100000c phase=queue-scan-miss",
          sequence, primary_lwmutex_id);
    }
  }

  return static_cast<bool>(found);
}

void thor_transformers_complete_audio_owner_wake(
    const ppu_thread &waiting_ppu, u32 lwmutex_id,
    const lv2_lwmutex &mutex) {
  if (!thor_transformers_audio_wake_fix_enabled() ||
      waiting_ppu.id != 0x0100'0000 ||
      static_cast<u32>(waiting_ppu.lr) !=
          thor_transformers_main_lwmutex_lock_lr) {
    return;
  }

  thor_transformers_discover_audio_dependency(lwmutex_id);

  const u32 caller = thor_transformers_lv2_lwmutex_caller_lr(waiting_ppu);
  const u32 control = mutex.control.addr();
  const u32 owner_id =
      control ? static_cast<u32>(mutex.control->vars.owner.load()) : 0;
  const auto owner = thor_transformers_select_live_ppu(owner_id);
  const u32 state_before =
      owner ? static_cast<u32>((+owner->state).raw()) : 0;

  const auto retry_dependency_wake = [&](const char *action) {
    const u32 dependency_lwmutex_id =
        g_thor_transformers_audio_dependency_lwmutex_id.load(
            std::memory_order_relaxed);
    const u32 dependency_owner_id =
        g_thor_transformers_audio_dependency_owner_id.load(
            std::memory_order_acquire);
    const u32 dependency_lookup_id =
        dependency_owner_id != waiting_ppu.id &&
                dependency_owner_id != owner_id
            ? dependency_owner_id
            : 0;
    const auto dependency_owner =
        thor_transformers_select_live_ppu(dependency_lookup_id);
    const u32 dependency_state_before =
        dependency_owner
            ? static_cast<u32>((+dependency_owner->state).raw())
            : 0;
    const bool dependency_forced =
        dependency_owner
            ? lv2_obj::force_owner_wake_after_waiter_sleep(*dependency_owner)
            : false;
    const u32 dependency_state_after =
        dependency_owner
            ? static_cast<u32>((+dependency_owner->state).raw())
            : 0;
    const u32 sequence =
        g_thor_transformers_audio_dependency_seq.fetch_add(
            1, std::memory_order_relaxed);
    if (sequence < thor_transformers_audio_dependency_log_limit) {
      sys_lwmutex.error(
          "Thor TWC AUDIO OWNER CHAIN WAKE #%u: %s waiter=0x%x "
          "owner=0x%x dependency_id=0x%x dependency_owner=0x%x "
          "state=0x%x->0x%x forced=%u",
          sequence, action, waiting_ppu.id, owner_id,
          dependency_lwmutex_id, dependency_owner_id,
          dependency_state_before, dependency_state_after,
          dependency_forced ? 1u : 0u);
    }
  };

  if (caller != thor_transformers_main_lwmutex_caller) {
    if (!g_thor_transformers_audio_owner_wake_completed.load(
            std::memory_order_relaxed)) {
      return;
    }

    const u32 sequence =
        g_thor_transformers_audio_owner_candidate_seq.fetch_add(
            1, std::memory_order_relaxed);
    if (sequence < thor_transformers_audio_owner_candidate_limit) {
      sys_lwmutex.error(
          "Thor TWC AUDIO OWNER CANDIDATE #%u: waiter=0x%x caller=0x%x "
          "id=0x%x owner=0x%x owner_live=%u owner_state=0x%x control=0x%x",
          sequence, waiting_ppu.id, caller, lwmutex_id, owner_id,
          owner ? 1u : 0u, state_before, control);
    }

    const bool is_deferred_dependency_candidate =
        owner && thor_transformers_is_fmod_receiver(*owner);
    if (is_deferred_dependency_candidate) {
      g_thor_transformers_post_audio_lwmutex_id.store(
          lwmutex_id, std::memory_order_release);
      u32 yields = 0;
      while (yields < thor_transformers_audio_dependency_yield_limit &&
             cpu_flag::suspend - owner->state) {
        yields++;
        std::this_thread::yield();
      }

      const bool found =
          thor_transformers_discover_audio_dependency(lwmutex_id, false);
      const u32 owner_state_after_yield =
          static_cast<u32>((+owner->state).raw());
      sys_lwmutex.error(
          "Thor TWC AUDIO OWNER DEFERRED SCAN: waiter=0x%x caller=0x%x "
          "id=0x%x owner=0x%x state=0x%x->0x%x yields=%u found=%u",
          waiting_ppu.id, caller, lwmutex_id, owner_id, state_before,
          owner_state_after_yield, yields, found ? 1u : 0u);
      retry_dependency_wake(found ? "candidate-deferred"
                                  : "candidate-deferred-miss");
      return;
    }

    retry_dependency_wake("candidate");
    return;
  }

  const bool forced_wake =
      owner ? lv2_obj::force_owner_wake_after_waiter_sleep(
                  *owner, &g_thor_transformers_audio_owner_signal_pending)
            : false;
  const u32 state_after =
      owner ? static_cast<u32>((+owner->state).raw()) : 0;

  if (forced_wake) {
    g_thor_transformers_audio_owner_wake_completed.store(
        true, std::memory_order_release);
  }

  sys_lwmutex.error(
      "Thor TWC AUDIO OWNER WAKE: waiter=0x%x owner=0x%x id=0x%x "
      "state=0x%x->0x%x forced=%u",
      waiting_ppu.id, owner_id, lwmutex_id, state_before, state_after,
      forced_wake ? 1u : 0u);
  retry_dependency_wake("initial");
}
} // namespace

bool thor_transformers_audio_owner_wake_completed() noexcept {
  return g_thor_transformers_audio_owner_wake_completed.load(
      std::memory_order_acquire);
}

lv2_lwmutex::lv2_lwmutex(utils::serial &ar)
    : protocol(ar), control(ar.pop<decltype(control)>()),
      name(ar.pop<be_t<u64>>()) {
  ar(lv2_control.raw().signaled);
}

void lv2_lwmutex::save(utils::serial &ar) {
  ar(protocol, control, name, lv2_control.raw().signaled);
}

error_code _sys_lwmutex_create(ppu_thread &ppu, vm::ptr<u32> lwmutex_id,
                               u32 protocol, vm::ptr<sys_lwmutex_t> control,
                               s32 has_name, u64 name) {
  ppu.state += cpu_flag::wait;

  sys_lwmutex.trace(u8"_sys_lwmutex_create(lwmutex_id=*0x%x, protocol=0x%x, "
                    u8"control=*0x%x, has_name=0x%x, name=0x%llx (“%s”))",
                    lwmutex_id, protocol, control, has_name, name,
                    lv2_obj::name_64{std::bit_cast<be_t<u64>>(name)});

  if (protocol != SYS_SYNC_FIFO && protocol != SYS_SYNC_RETRY &&
      protocol != SYS_SYNC_PRIORITY) {
    sys_lwmutex.error("_sys_lwmutex_create(): unknown protocol (0x%x)",
                      protocol);
    return CELL_EINVAL;
  }

  if (!(has_name < 0)) {
    name = 0;
  }

  if (const u32 id = idm::make<lv2_obj, lv2_lwmutex>(protocol, control, name)) {
    ppu.check_state();
    *lwmutex_id = id;
    return CELL_OK;
  }

  return CELL_EAGAIN;
}

error_code _sys_lwmutex_destroy(ppu_thread &ppu, u32 lwmutex_id) {
  ppu.state += cpu_flag::wait;

  sys_lwmutex.trace("_sys_lwmutex_destroy(lwmutex_id=0x%x)", lwmutex_id);

  shared_ptr<lv2_lwmutex> _mutex;

  while (true) {
    s32 old_val = 0;

    auto [ptr, ret] = idm::withdraw<lv2_obj, lv2_lwmutex>(
        lwmutex_id, [&](lv2_lwmutex &mutex) -> CellError {
          // Ignore check on first iteration
          if (_mutex && std::addressof(mutex) != _mutex.get()) {
            // Other thread has destroyed the lwmutex earlier
            return CELL_ESRCH;
          }

          std::lock_guard lock(mutex.mutex);

          if (mutex.load_sq()) {
            return CELL_EBUSY;
          }

          old_val = mutex.lwcond_waiters.or_fetch(smin);

          if (old_val != smin) {
            // Deschedule if waiters were found
            lv2_obj::sleep(ppu);

            // Repeat loop: there are lwcond waiters
            return CELL_EAGAIN;
          }

          return {};
        });

    if (!ptr) {
      return CELL_ESRCH;
    }

    if (ret) {
      if (ret != CELL_EAGAIN) {
        return ret;
      }
    } else {
      break;
    }

    _mutex = std::move(ptr);

    // Wait for all lwcond waiters to quit
    while (old_val + 0u > 1u << 31) {
      thread_ctrl::wait_on(_mutex->lwcond_waiters, old_val);

      if (ppu.is_stopped()) {
        ppu.state += cpu_flag::again;
        return {};
      }

      old_val = _mutex->lwcond_waiters;
    }

    // Wake up from sleep
    ppu.check_state();
  }

  return CELL_OK;
}

error_code _sys_lwmutex_lock(ppu_thread &ppu, u32 lwmutex_id, u64 timeout) {
  thor_transformers_discard_stale_audio_owner_signal(ppu, lwmutex_id);
  ppu.state += cpu_flag::wait;

  sys_lwmutex.trace("_sys_lwmutex_lock(lwmutex_id=0x%x, timeout=0x%llx)",
                    lwmutex_id, timeout);

  ppu.gpr[3] = CELL_OK;
  thor_transformers_lv2_lwmutex_trace_arm(ppu, lwmutex_id);

  const auto mutex = idm::get<lv2_obj, lv2_lwmutex>(
      lwmutex_id, [&, notify = lv2_obj::notify_all_t()](lv2_lwmutex &mutex) {
        thor_transformers_lv2_lwmutex_trace(ppu, lwmutex_id, mutex,
                                            "LOCK-ENTER", timeout);
        if (s32 signal = mutex.lv2_control
                             .fetch_op([](lv2_lwmutex::control_data_t &data) {
                               if (data.signaled) {
                                 data.signaled = 0;
                                 return true;
                               }

                               return false;
                             })
                             .first.signaled) {
          if (~signal & 1) {
            ppu.gpr[3] = CELL_EBUSY;
          }

          thor_transformers_lv2_lwmutex_trace(
              ppu, lwmutex_id, mutex, "LOCK-SIGNAL", ppu.gpr[3]);
          return true;
        }

        lv2_obj::prepare_for_sleep(ppu);

        ppu.cancel_sleep = 1;

        if (s32 signal = mutex.try_own(&ppu)) {
          if (~signal & 1) {
            ppu.gpr[3] = CELL_EBUSY;
          }

          ppu.cancel_sleep = 0;
          thor_transformers_lv2_lwmutex_trace(
              ppu, lwmutex_id, mutex, "LOCK-OWN", ppu.gpr[3]);
          return true;
        }

        thor_transformers_lv2_lwmutex_trace(ppu, lwmutex_id, mutex,
                                            "LOCK-SLEEP", timeout);
        const bool finished = !mutex.sleep(ppu, timeout);
        if (!finished) {
          thor_transformers_complete_audio_owner_wake(ppu, lwmutex_id, mutex);
        }
        notify.cleanup();
        thor_transformers_lv2_lwmutex_trace(
            ppu, lwmutex_id, mutex,
            finished ? "LOCK-FINISHED" : "LOCK-QUEUED", ppu.gpr[3]);
        return finished;
      });

  if (!mutex) {
    return CELL_ESRCH;
  }

  if (mutex.ret) {
    thor_transformers_lv2_lwmutex_trace(ppu, lwmutex_id, *mutex,
                                        "LOCK-RETURN", ppu.gpr[3]);
    return not_an_error(ppu.gpr[3]);
  }

  while (auto state = +ppu.state) {
    if (state & cpu_flag::signal &&
        ppu.state.test_and_reset(cpu_flag::signal)) {
      break;
    }

    if (is_stopped(state)) {
      std::lock_guard lock(mutex->mutex);

      for (auto cpu = mutex->load_sq(); cpu; cpu = cpu->next_cpu) {
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

        if (!mutex->load_sq()) {
          // Sleep queue is empty, so the thread must have been signaled
          mutex->mutex.lock_unlock();
          break;
        }

        std::lock_guard lock(mutex->mutex);

        bool success = false;

        mutex->lv2_control.fetch_op([&](lv2_lwmutex::control_data_t &data) {
          success = false;

          ppu_thread *sq = static_cast<ppu_thread *>(data.sq);

          const bool retval = &ppu == sq;

          if (!mutex->unqueue<false>(sq, &ppu)) {
            return false;
          }

          success = true;

          if (!retval) {
            return false;
          }

          data.sq = sq;
          return true;
        });

        if (success) {
          ppu.next_cpu = nullptr;
          ppu.gpr[3] = CELL_ETIMEDOUT;
        }

        break;
      }
    } else {
      ppu.state.wait(state);
    }
  }

  thor_transformers_lv2_lwmutex_trace(ppu, lwmutex_id, *mutex, "LOCK-WAKE",
                                      ppu.gpr[3]);
  thor_transformers_lv2_lwmutex_trace(ppu, lwmutex_id, *mutex, "LOCK-RETURN",
                                      ppu.gpr[3]);
  return not_an_error(ppu.gpr[3]);
}

error_code _sys_lwmutex_trylock(ppu_thread &ppu, u32 lwmutex_id) {
  ppu.state += cpu_flag::wait;

  sys_lwmutex.trace("_sys_lwmutex_trylock(lwmutex_id=0x%x)", lwmutex_id);

  const auto mutex =
      idm::check<lv2_obj, lv2_lwmutex>(lwmutex_id, [&](lv2_lwmutex &mutex) {
        auto [_, ok] =
            mutex.lv2_control.fetch_op([](lv2_lwmutex::control_data_t &data) {
              if (data.signaled & 1) {
                data.signaled = 0;
                return true;
              }

              return false;
            });

        return ok;
      });

  if (!mutex) {
    return CELL_ESRCH;
  }

  if (!mutex.ret) {
    return not_an_error(CELL_EBUSY);
  }

  return CELL_OK;
}

error_code _sys_lwmutex_unlock(ppu_thread &ppu, u32 lwmutex_id) {
  ppu.state += cpu_flag::wait;

  sys_lwmutex.trace("_sys_lwmutex_unlock(lwmutex_id=0x%x)", lwmutex_id);

  const bool trace_post_audio_unlock =
      thor_transformers_post_audio_unlock_trace_target(ppu, lwmutex_id);
  const u32 post_audio_unlock_call =
      trace_post_audio_unlock
          ? g_thor_transformers_post_audio_unlock_trace_seq.fetch_add(
                1, std::memory_order_relaxed)
          : thor_transformers_post_audio_unlock_trace_limit;
  thor_transformers_post_audio_unlock_trace(
      ppu, lwmutex_id, post_audio_unlock_call, "PRE-IDM");

  const auto mutex = idm::check<lv2_obj, lv2_lwmutex>(
      lwmutex_id, [&, notify = lv2_obj::notify_all_t()](lv2_lwmutex &mutex) {
        thor_transformers_post_audio_unlock_trace(
            ppu, lwmutex_id, post_audio_unlock_call, "POST-IDM", &mutex);
        thor_transformers_lv2_lwmutex_trace(ppu, lwmutex_id, mutex,
                                            "UNLOCK-ENTER");
        thor_transformers_post_audio_unlock_trace(
            ppu, lwmutex_id, post_audio_unlock_call, "PRE-TRY-UNLOCK", &mutex);
        if (mutex.try_unlock(false)) {
          thor_transformers_post_audio_unlock_trace(
              ppu, lwmutex_id, post_audio_unlock_call, "POST-TRY-SIGNAL",
              &mutex);
          thor_transformers_lv2_lwmutex_trace(ppu, lwmutex_id, mutex,
                                              "UNLOCK-SIGNAL");
          return;
        }

        thor_transformers_post_audio_unlock_trace(
            ppu, lwmutex_id, post_audio_unlock_call, "POST-TRY-QUEUED",
            &mutex);
        thor_transformers_post_audio_unlock_trace(
            ppu, lwmutex_id, post_audio_unlock_call, "PRE-QUEUE-LOCK", &mutex);
        std::lock_guard lock(mutex.mutex);
        thor_transformers_post_audio_unlock_trace(
            ppu, lwmutex_id, post_audio_unlock_call, "POST-QUEUE-LOCK",
            &mutex);

        thor_transformers_post_audio_unlock_trace(
            ppu, lwmutex_id, post_audio_unlock_call, "PRE-REOWN", &mutex);
        const auto reowned =
            trace_post_audio_unlock
                ? thor_transformers_reown_with_trace(
                      mutex, post_audio_unlock_call)
                : mutex.reown<ppu_thread>();
        if (const auto cpu = reowned) {
          thor_transformers_post_audio_unlock_trace(
              ppu, lwmutex_id, post_audio_unlock_call, "POST-REOWN", &mutex,
              cpu);
          if (static_cast<ppu_thread *>(cpu)->state & cpu_flag::again) {
            ppu.state += cpu_flag::again;
            thor_transformers_lv2_lwmutex_trace(
                ppu, lwmutex_id, mutex, "UNLOCK-AGAIN", 0, cpu->id);
            return;
          }

          thor_transformers_lv2_lwmutex_trace(
              ppu, lwmutex_id, mutex, "UNLOCK-HANDOFF", 0, cpu->id);
          thor_transformers_post_audio_unlock_trace(
              ppu, lwmutex_id, post_audio_unlock_call, "PRE-AWAKE", &mutex,
              cpu);
          mutex.awake(cpu);
          thor_transformers_post_audio_unlock_trace(
              ppu, lwmutex_id, post_audio_unlock_call, "POST-AWAKE", &mutex,
              cpu);
          thor_transformers_post_audio_unlock_trace(
              ppu, lwmutex_id, post_audio_unlock_call, "PRE-CLEANUP", &mutex,
              cpu);
          notify.cleanup(); // lv2_lwmutex::mutex is not really active 99% of
                            // the time, can be ignored
          thor_transformers_post_audio_unlock_trace(
              ppu, lwmutex_id, post_audio_unlock_call, "POST-CLEANUP", &mutex,
              cpu);
        } else {
          thor_transformers_post_audio_unlock_trace(
              ppu, lwmutex_id, post_audio_unlock_call, "POST-REOWN-EMPTY",
              &mutex);
        }
      });

  thor_transformers_post_audio_unlock_trace(
      ppu, lwmutex_id, post_audio_unlock_call, "POST-IDM-CHECK",
      mutex ? &*mutex : nullptr);

  if (!mutex) {
    return CELL_ESRCH;
  }

  thor_transformers_lv2_lwmutex_trace(ppu, lwmutex_id, *mutex,
                                      "UNLOCK-RETURN");
  return CELL_OK;
}

error_code _sys_lwmutex_unlock2(ppu_thread &ppu, u32 lwmutex_id) {
  ppu.state += cpu_flag::wait;

  sys_lwmutex.warning("_sys_lwmutex_unlock2(lwmutex_id=0x%x)", lwmutex_id);

  const auto mutex = idm::check<lv2_obj, lv2_lwmutex>(
      lwmutex_id, [&, notify = lv2_obj::notify_all_t()](lv2_lwmutex &mutex) {
        thor_transformers_lv2_lwmutex_trace(ppu, lwmutex_id, mutex,
                                            "UNLOCK2-ENTER");
        if (mutex.try_unlock(true)) {
          thor_transformers_lv2_lwmutex_trace(ppu, lwmutex_id, mutex,
                                              "UNLOCK2-SIGNAL");
          return;
        }

        std::lock_guard lock(mutex.mutex);

        if (const auto cpu = mutex.reown<ppu_thread>(true)) {
          if (static_cast<ppu_thread *>(cpu)->state & cpu_flag::again) {
            ppu.state += cpu_flag::again;
            thor_transformers_lv2_lwmutex_trace(
                ppu, lwmutex_id, mutex, "UNLOCK2-AGAIN", CELL_EBUSY,
                cpu->id);
            return;
          }

          static_cast<ppu_thread *>(cpu)->gpr[3] = CELL_EBUSY;
          thor_transformers_lv2_lwmutex_trace(
              ppu, lwmutex_id, mutex, "UNLOCK2-HANDOFF", CELL_EBUSY,
              cpu->id);
          mutex.awake(cpu);
          notify.cleanup(); // lv2_lwmutex::mutex is not really active 99% of
                            // the time, can be ignored
        }
      });

  if (!mutex) {
    return CELL_ESRCH;
  }

  thor_transformers_lv2_lwmutex_trace(ppu, lwmutex_id, *mutex,
                                      "UNLOCK2-RETURN");
  return CELL_OK;
}
