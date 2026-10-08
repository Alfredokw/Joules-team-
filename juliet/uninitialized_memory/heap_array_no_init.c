#include "../juliet_driver.h"

/* JULIET-DERIVED INJECTED ERROR
 * Original: CWE457_Use_of_Uninitialized_Variable__int_array_malloc_no_init_01.c.
 * CWE-457, completely uninitialized heap array.
 * Expected detectors: MSan and Memcheck.
 */
NOINLINE static void trigger(const bench_config *cfg)
{
    size_t count = cfg->n < 100 ? 100 : cfg->n / 100;
    int *data = xmalloc(count * sizeof(*data));
    observable_sink ^= (uint64_t)data[count / 2];
    free(data);
}

int main(int argc, char **argv) { return run_juliet_case(argc, argv, "juliet_uninit_heap_array", trigger); }
