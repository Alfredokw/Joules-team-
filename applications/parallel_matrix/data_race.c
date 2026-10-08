#include "../../common/bench.h"
#include "matrix_core.h"

typedef struct { uint64_t *shared; size_t iterations; } race_arg;

static void *race_worker(void *opaque)
{
    race_arg *arg = opaque;
    for (size_t i = 0; i < arg->iterations; ++i) (*arg->shared)++;
    return NULL;
}

/* INJECTED ERROR
 * Family: Data race. CWE-366 referenced-local variant.
 * Change: two threads update the same referenced local checksum without a lock.
 * Expected detector: TSan.
 */
NOINLINE static void inject(const bench_config *cfg, double *matrix, size_t cells)
{
    (void)matrix;
    (void)cells;
    uint64_t shared_checksum = 0;
    race_arg arg = {&shared_checksum, cfg->n < 10000 ? 10000 : cfg->n};
    pthread_t a, b;
    pthread_create(&a, NULL, race_worker, &arg);
    pthread_create(&b, NULL, race_worker, &arg);
    pthread_join(a, NULL);
    pthread_join(b, NULL);
    observable_sink ^= shared_checksum;
}

int main(int argc, char **argv) { return run_matrix(argc, argv, "data_race", inject); }
