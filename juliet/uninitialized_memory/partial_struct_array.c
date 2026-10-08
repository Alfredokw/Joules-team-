#include "../juliet_driver.h"

typedef struct { uint64_t initialized; uint64_t uninitialized; } juliet_record;

/* JULIET-DERIVED INJECTED ERROR
 * Original: CWE457_Use_of_Uninitialized_Variable__struct_array_malloc_partial_init_01.c.
 * CWE-457, partially initialized structure array.
 * Expected detectors: MSan and Memcheck.
 */
NOINLINE static void trigger(const bench_config *cfg)
{
    size_t count = cfg->n < 100 ? 100 : cfg->n / 100;
    juliet_record *data = xmalloc(count * sizeof(*data));
    for (size_t i = 0; i < count; ++i) data[i].initialized = i;
    observable_sink ^= data[count / 2].uninitialized;
    free(data);
}

int main(int argc, char **argv) { return run_juliet_case(argc, argv, "juliet_uninit_partial_struct", trigger); }
