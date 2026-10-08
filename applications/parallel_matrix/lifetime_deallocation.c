#include "../../common/bench.h"
#include "matrix_core.h"

/* INJECTED ERROR
 * Family: Lifetime/deallocation. CWE-401 memory leak.
 * Change: allocate a temporary result row and intentionally omit its free.
 * Expected detector: Valgrind Memcheck (also LeakSanitizer when enabled).
 */
NOINLINE static void inject(const bench_config *cfg, double *matrix, size_t cells)
{
    size_t count = cfg->n < cells ? cfg->n : cells;
    double *temporary_row = xmalloc(count * sizeof(*temporary_row));
    memcpy(temporary_row, matrix, count * sizeof(*temporary_row));
    observable_sink ^= (uint64_t)temporary_row[count / 2];
    /* Intentionally omit free(temporary_row). */
}

int main(int argc, char **argv) { return run_matrix(argc, argv, "lifetime_deallocation", inject); }
