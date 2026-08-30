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
constexpr u32 thor_transformers_main_lwmutex_caller = 0x00dd6264;
constexpr u32 thor_transformers_lv2_lwmutex_trace_limit = 128;

std::atomic<u32> g_thor_transformers_lv2_lwmutex_id{0};
std::atomic<u32> g_thor_transformers_lv2_lwmutex_trace_seq{0};

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

void thor_transformers_complete_audio_owner_wake(
    const ppu_thread &waiting_ppu, u32 lwmutex_id,
    const lv2_lwmutex &mutex) {
  if (!thor_transformers_audio_wake_fix_enabled() ||
      waiting_ppu.id != 0x0100'0000 ||
      static_cast<u32>(waiting_ppu.lr) !=
          thor_transformers_main_lwmutex_lock_lr ||
      thor_transformers_lv2_lwmutex_caller_lr(waiting_ppu) !=
          thor_transformers_main_lwmutex_caller) {
    return;
  }

  const u32 control = mutex.control.addr();
  const u32 owner_id =
      control ? static_cast<u32>(mutex.control->vars.owner.load()) : 0;
  const auto owner =
      idm::get_unlocked<named_thread<ppu_thread>>(owner_id);
  const u32 state_before =
      owner ? static_cast<u32>((+owner->state).raw()) : 0;
  const bool forced_wake =
      owner ? lv2_obj::force_owner_wake_after_waiter_sleep(*owner) : false;
  const u32 state_after =
      owner ? static_cast<u32>((+owner->state).raw()) : 0;

  sys_lwmutex.error(
      "Thor TWC AUDIO OWNER WAKE: waiter=0x%x owner=0x%x id=0x%x "
      "state=0x%x->0x%x forced=%u",
      waiting_ppu.id, owner_id, lwmutex_id, state_before, state_after,
      forced_wake ? 1u : 0u);
}
} // namespace

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

  const auto mutex = idm::check<lv2_obj, lv2_lwmutex>(
      lwmutex_id, [&, notify = lv2_obj::notify_all_t()](lv2_lwmutex &mutex) {
        thor_transformers_lv2_lwmutex_trace(ppu, lwmutex_id, mutex,
                                            "UNLOCK-ENTER");
        if (mutex.try_unlock(false)) {
          thor_transformers_lv2_lwmutex_trace(ppu, lwmutex_id, mutex,
                                              "UNLOCK-SIGNAL");
          return;
        }

        std::lock_guard lock(mutex.mutex);

        if (const auto cpu = mutex.reown<ppu_thread>()) {
          if (static_cast<ppu_thread *>(cpu)->state & cpu_flag::again) {
            ppu.state += cpu_flag::again;
            thor_transformers_lv2_lwmutex_trace(
                ppu, lwmutex_id, mutex, "UNLOCK-AGAIN", 0, cpu->id);
            return;
          }

          thor_transformers_lv2_lwmutex_trace(
              ppu, lwmutex_id, mutex, "UNLOCK-HANDOFF", 0, cpu->id);
          mutex.awake(cpu);
          notify.cleanup(); // lv2_lwmutex::mutex is not really active 99% of
                            // the time, can be ignored
        }
      });

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
