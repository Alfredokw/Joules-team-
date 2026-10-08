#include "../../common/bench.h"
#include "bst_core.h"

/* INJECTED ERROR
 * Family: Lifetime/deallocation. CWE-416 heap use-after-free.
 * Change: release a heap result and then read its value once.
 * Expected detectors: ASan and Valgrind Memcheck.
 */
NOINLINE static void inject(const bench_config *cfg, uint64_t *queries, size_t count)
{
    (void)cfg;
    uint64_t *result = xmalloc(sizeof(*result));
    *result = queries[count / 2];
    free(result);
    observable_sink ^= *result;
}

int main(int argc, char **argv) { return run_bst(argc, argv, "lifetime_deallocation", inject); }
