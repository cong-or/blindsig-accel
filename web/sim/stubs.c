/* stubs.c — no-op implementations of CPU-affinity calls that Verilator's
 * runtime references for thread pinning. The WASM build is single-threaded and
 * never pins, so these just satisfy the linker. extern "C" keeps the symbol
 * names unmangled so they resolve the C references from verilated*.cpp. */
#ifdef __cplusplus
extern "C" {
#endif
int sched_getcpu(void) { return 0; }
int pthread_getaffinity_np(unsigned long t, unsigned long sz, void *set) {
    (void)t; (void)sz; (void)set; return 0;
}
int pthread_setaffinity_np(unsigned long t, unsigned long sz, const void *set) {
    (void)t; (void)sz; (void)set; return 0;
}
#ifdef __cplusplus
}
#endif
