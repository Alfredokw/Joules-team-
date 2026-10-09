#include "../../common/bench.h"
#include "hash_core.h"

/* INJECTED ERROR
 * Family: Lifetime/deallocation. CWE-401 memory leak.
 * Change: allocate a detached hash-style entry and intentionally lose it.
 * Expected detector: Valgrind Memcheck (also LeakSanitizer when enabled).
 */
NOINLINE static void inject(const bench_config *cfg, uint64_t *queries, size_t count)
{
    volatile hash_entry *leaked = xmalloc(sizeof(*leaked));
    leaked->key = queries[count / 2];
    leaked->value = mix64(cfg->seed);
    observable_sink ^= leaked->value;
    /* Intentionally omit free(leaked). */
}

int main(int argc, char **argv) { return run_hash(argc, argv, "lifetime_deallocation", inject); }
