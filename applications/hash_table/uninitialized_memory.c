#include "../../common/bench.h"
#include "hash_core.h"

/* INJECTED ERROR
 * Family: Uninitialized memory. CWE-457.
 * Change: initialize a detached entry's key but consume its uninitialized value.
 * Expected detectors: MSan and Valgrind Memcheck.
 */
NOINLINE static void inject(const bench_config *cfg, uint64_t *queries, size_t count)
{
    (void)cfg;
    hash_entry *entry = xmalloc(sizeof(*entry));
    entry->key = queries[count / 2];
    observable_sink ^= entry->value;
    free(entry);
}

int main(int argc, char **argv) { return run_hash(argc, argv, "uninitialized_memory", inject); }
