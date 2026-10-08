#include "../../common/bench.h"
#include "bst_core.h"

/* INJECTED ERROR
 * Family: Out-of-bounds access. CWE-126 heap buffer over-read.
 * Change: read the element immediately after the query array.
 * Expected detectors: ASan and Valgrind Memcheck.
 */
NOINLINE static void inject(const bench_config *cfg, uint64_t *queries, size_t count)
{
    (void)cfg;
    volatile size_t one_past = count;
    observable_sink ^= queries[one_past];
}

int main(int argc, char **argv) { return run_bst(argc, argv, "out_of_bounds", inject); }
