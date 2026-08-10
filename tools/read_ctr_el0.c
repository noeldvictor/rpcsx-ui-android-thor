#include <stdio.h>
#include <stdint.h>
int main(void) {
    uint64_t ctr;
    __asm__ volatile("mrs %0, ctr_el0" : "=r"(ctr));
    unsigned erg   = (unsigned)((ctr >> 20) & 0xF);   // exclusive reservation granule
    unsigned cwg   = (unsigned)((ctr >> 24) & 0xF);   // cache writeback granule
    unsigned dminl = (unsigned)((ctr >>  16) & 0xF);  // smallest D-cache line
    unsigned iminl = (unsigned)(ctr & 0xF);
    printf("CTR_EL0 = 0x%016llx\n", (unsigned long long)ctr);
    printf("ERG   field=%u -> exclusive reservation granule = %u bytes\n", erg,   erg   ? 4u << erg   : 0);
    printf("CWG   field=%u -> cache writeback granule       = %u bytes\n", cwg,   cwg   ? 4u << cwg   : 0);
    printf("DminLine field=%u -> min D-cache line           = %u bytes\n", dminl, 4u << dminl);
    printf("IminLine field=%u -> min I-cache line           = %u bytes\n", iminl, 4u << iminl);
    printf("\nPS3 reservation is 128 bytes. Monitor usable as the whole reservation: %s\n",
           (erg && (4u << erg) >= 128) ? "YES" : "NO (but still a free negative check)");
    return 0;
}
