#include "../../common/bench.h"
#include "hash_core.h"

static uint64_t operation_counter;
typedef struct { size_t iterations; int branch; } race_arg;

static void *race_worker(void *opaque)
{
    race_arg *arg = opaque;
    for (size_t i = 0; i < arg->iterations; ++i) {
        if (arg->branch) operation_counter += 2;
        else operation_counter++;
    }
    return NULL;
}

/* INJECTED ERROR
 * Family: Data race. CWE-366 control-flow variant.
 * Change: two branches update the same global operation counter without a lock.
 * Expected detector: TSan.
 */
NOINLINE static void inject(const bench_config *cfg, uint64_t *queries, size_t count)
{
    (void)queries;
    (void)count;
    size_t iterations = cfg->n < 10000 ? 10000 : cfg->n;
    race_arg args[2] = {{iterations, 0}, {iterations, 1}};
    pthread_t ids[2];
    pthread_create(&ids[0], NULL, race_worker, &args[0]);
    pthread_create(&ids[1], NULL, race_worker, &args[1]);
    pthread_join(ids[0], NULL);
    pthread_join(ids[1], NULL);
    observable_sink ^= operation_counter;
}

int main(int argc, char **argv) { return run_hash(argc, argv, "data_race", inject); }
