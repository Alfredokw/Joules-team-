#include "../juliet_driver.h"

/* JULIET-DERIVED INJECTED ERROR
 * Original: CWE416_Use_After_Free__malloc_free_char_01.c.
 * CWE-416, one heap read after free.
 * Expected detectors: ASan and Memcheck.
 */
NOINLINE static void trigger(const bench_config *cfg)
{
    (void)cfg;
    char *data = xmalloc(100);
    data[0] = 'A';
    free(data);
    volatile size_t index = 0;
    observable_sink ^= (unsigned char)data[index];
}

int main(int argc, char **argv) { return run_juliet_case(argc, argv, "juliet_lifetime_uaf", trigger); }
