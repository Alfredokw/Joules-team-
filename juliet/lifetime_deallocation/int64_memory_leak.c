#include "../juliet_driver.h"

/* JULIET-DERIVED INJECTED ERROR
 * Original: CWE401_Memory_Leak__int64_t_malloc_01.c.
 * CWE-401, definitely-lost int64_t allocation.
 * Expected detector: Memcheck, with LeakSanitizer as a secondary detector.
 */
NOINLINE static void trigger(const bench_config *cfg)
{
    size_t count = cfg->n < 100 ? 100 : cfg->n / 100;
    volatile int64_t *data = xmalloc(count * sizeof(*data));
    data[0] = INT64_C(42);
    observable_sink ^= (uint64_t)data[0];
    /* Intentionally omit free(data). */
}

int main(int argc, char **argv) { return run_juliet_case(argc, argv, "juliet_lifetime_int64_leak", trigger); }
