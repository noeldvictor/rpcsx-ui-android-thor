// Does the Thor have a real core-idling primitive for a spin-wait?
//
// rx/asm.hpp's busy_wait spins on cntvct_el0 with pause() between reads, and
// this tree already records that pause() emits YIELD on AArch64, which retires
// as a nop on a non-SMT core: no clock drop, no park. That is why five SPUs can
// burn ~60% of a core each while 83-89% guest-idle.
//
// ARM offers better, if the chip has it:
//   YIELD   the current hint, effectively free and effectively useless
//   WFE     wait for event - parks until an event, SEV, or interrupt. Returns
//           immediately if the local event register is already set, which makes
//           it safe to probe but means it can spin-return.
//   WFET    ARMv8.7 FEAT_WFxT, wait-for-event WITH TIMEOUT in CNTVCT ticks.
//           This is the one that would let a backoff park for a bounded time.
//   SEVL    set event locally, so a following WFE returns at once - used to make
//           WFE safe in a loop.
#include <stdio.h>
#include <stdint.h>
#include <time.h>
#include <signal.h>
#include <setjmp.h>
#include <string.h>
static sigjmp_buf J; static void ill(int s){(void)s;siglongjmp(J,1);}
static uint64_t ns(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (uint64_t)t.tv_sec*1000000000ull+t.tv_nsec;}
#define N 200000
#define B(name,expr) do{ if(sigsetjmp(J,1)==0){ for(int i=0;i<1000;i++){expr;} \
    uint64_t a=ns(); for(int i=0;i<N;i++){expr;} uint64_t b=ns(); \
    printf("  %-26s %8.2f ns/op\n",name,(double)(b-a)/N);} \
    else printf("  %-26s TRAPS (SIGILL)\n",name);}while(0)
int main(void){
  struct sigaction sa; memset(&sa,0,sizeof sa); sa.sa_handler=ill; sigaction(SIGILL,&sa,NULL);
  uint64_t hw=0; __asm__ volatile("mrs %0, id_aa64isar2_el1":"=r"(hw));
  printf("(ID_AA64ISAR2_EL1 read: if this printed, EL1 ID regs are emulated for us)\n");
  printf("hwcap probe via instruction trial:\n");
  B("yield",  __asm__ volatile("yield"));
  B("sevl",   __asm__ volatile("sevl"));
  B("sevl;wfe", __asm__ volatile("sevl; wfe"));
  // FEAT_WFxT: WFET Xt = 0xD5031000 | Rt ; use x0
  B("sevl;wfet x0", { uint64_t d=1000; __asm__ volatile("sevl; mov x0,%0; .inst 0xd5031000"::"r"(d):"x0"); });
  printf("\n(a WFE that returns in ~yield time is spin-returning, not parking)\n");
  return 0;
}
