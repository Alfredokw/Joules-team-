#include "../../common/bench.h"
#include "hash_core.h"

/* INJECTED ERROR
 * Family: Out-of-bounds access. CWE-126 heap buffer over-read.
 * Change: copy two keys starting from the final element of the query array.
 * Expected detectors: ASan and Valgrind Memcheck.
 */
NOINLINE static void inject(const bench_config *cfg, uint64_t *queries, size_t count)
{
    (void)cfg;
    uint64_t pair[2] = {0, 0};
    memcpy(pair, &queries[count - 1], sizeof(pair));
    observable_sink ^= pair[0] ^ pair[1];
}

int main(int argc, char **argv) { return run_hash(argc, argv, "out_of_bounds", inject); }
