#include "../../common/bench.h"
#include "matrix_core.h"

/* INJECTED ERROR
 * Family: Out-of-bounds access. CWE-126 stack buffer over-read.
 * Change: read one position beyond a stack sample of matrix results.
 * Expected detector: ASan.
 */
NOINLINE static void inject(const bench_config *cfg, double *matrix, size_t cells)
{
    (void)cfg;
    double sample[16];
    for (size_t i = 0; i < 16; ++i) sample[i] = matrix[i % cells];
    volatile size_t one_past = 16;
    observable_sink ^= (uint64_t)sample[one_past];
}

int main(int argc, char **argv) { return run_matrix(argc, argv, "out_of_bounds", inject); }
