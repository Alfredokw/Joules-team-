#include "../juliet_driver.h"

/* JULIET-DERIVED INJECTED ERROR
 * Original: CWE401_Memory_Leak__char_malloc_01.c.
 * CWE-401, definitely-lost character allocation.
 * This replaces the native-crashing double-free case. Expected detector:
 * Memcheck, with LeakSanitizer as a secondary detector.
 */
NOINLINE static void trigger(const bench_config *cfg)
{
    size_t count = cfg->n < 100 ? 100 : cfg->n / 100;
    char *data = xmalloc(count);
    memset(data, 'L', count);
    observable_sink ^= (unsigned char)data[count / 2];
    /* Intentionally omit free(data). */
}

int main(int argc, char **argv) { return run_juliet_case(argc, argv, "juliet_lifetime_char_leak", trigger); }
