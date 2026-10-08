#include "../juliet_driver.h"

/* JULIET-DERIVED INJECTED ERROR
 * Original: CWE126_Buffer_Overread__char_alloca_loop_01.c.
 * CWE-126, stack buffer over-read through a loop.
 * This read-only replacement avoids the destructive stack write previously
 * considered. Expected detector: ASan.
 */
NOINLINE static void trigger(const bench_config *cfg)
{
    (void)cfg;
    volatile char source[10] = {0};
    volatile size_t limit = 11;
    for (size_t i = 0; i < limit; ++i) observable_sink ^= (unsigned char)source[i];
}

int main(int argc, char **argv) { return run_juliet_case(argc, argv, "juliet_oob_stack_loop", trigger); }
