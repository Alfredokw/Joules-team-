#include "../../common/bench.h"
#include "bst_core.h"

typedef struct { uint64_t key; uint64_t found; } search_result;

/* INJECTED ERROR
 * Family: Uninitialized memory. CWE-457.
 * Change: initialize only the key field and consume the uninitialized found field.
 * Expected detectors: MSan and Valgrind Memcheck.
 */
NOINLINE static void inject(const bench_config *cfg, uint64_t *queries, size_t count)
{
    (void)cfg;
    search_result *result = xmalloc(sizeof(*result));
    result->key = queries[count / 2];
    observable_sink ^= result->found;
    free(result);
}

int main(int argc, char **argv) { return run_bst(argc, argv, "uninitialized_memory", inject); }
