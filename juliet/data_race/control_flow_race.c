#include "../juliet_driver.h"

static uint64_t control_counter;
typedef struct { size_t iterations; int branch; } race_arg;
static void *worker(void *opaque)
{
    race_arg *arg = opaque;
    for (size_t i = 0; i < arg->iterations; ++i) {
        if (arg->branch) control_counter += 2;
        else control_counter++;
    }
    return NULL;
}

/* JULIET-DERIVED INJECTED ERROR
 * Original: CWE366_Race_Condition_Within_Thread__global_int_02.c.
 * CWE-366, control-flow variant of a global integer race.
 * Expected detector: TSan.
 */
NOINLINE static void trigger(const bench_config *cfg)
{
    size_t iterations = cfg->n < 10000 ? 10000 : cfg->n;
    race_arg args[2] = {{iterations, 0}, {iterations, 1}};
    pthread_t ids[2];
    pthread_create(&ids[0], NULL, worker, &args[0]);
    pthread_create(&ids[1], NULL, worker, &args[1]);
    pthread_join(ids[0], NULL);
    pthread_join(ids[1], NULL);
    observable_sink ^= control_counter;
}

int main(int argc, char **argv) { return run_juliet_case(argc, argv, "juliet_race_control", trigger); }
