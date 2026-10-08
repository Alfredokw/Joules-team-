#include "../../common/bench.h"
#include "matrix_core.h"

typedef struct { double sum; double correction; } partial_sum;

/* INJECTED ERROR
 * Family: Uninitialized memory. CWE-457.
 * Change: initialize only sum and consume the uninitialized correction field.
 * Expected detectors: MSan and Valgrind Memcheck.
 */
NOINLINE static void inject(const bench_config *cfg, double *matrix, size_t cells)
{
    (void)cfg;
    partial_sum *partial = xmalloc(sizeof(*partial));
    partial->sum = matrix[cells / 2];
    observable_sink ^= (uint64_t)(partial->correction);
    free(partial);
}

int main(int argc, char **argv) { return run_matrix(argc, argv, "uninitialized_memory", inject); }
