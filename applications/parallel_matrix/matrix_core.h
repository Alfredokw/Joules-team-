#ifndef SEB_MATRIX_CORE_H
#define SEB_MATRIX_CORE_H

/*
 * Dynamically sized, pthread-parallel adaptation of PolyBench/C GEMM:
 * C := alpha*A*B + beta*C. Upstream snapshot and license are in provenance/.
 */
typedef struct {
    const double *a;
    const double *b;
    double *c;
    size_t n;
    size_t begin;
    size_t end;
} matrix_worker_args;

static void *matrix_worker(void *opaque)
{
    matrix_worker_args *args = opaque;
    const double alpha = 1.5;
    const double beta = 1.2;
    for (size_t i = args->begin; i < args->end; ++i) {
        for (size_t j = 0; j < args->n; ++j) args->c[i * args->n + j] *= beta;
        for (size_t k = 0; k < args->n; ++k) {
            double aik = alpha * args->a[i * args->n + k];
            for (size_t j = 0; j < args->n; ++j) {
                args->c[i * args->n + j] += aik * args->b[k * args->n + j];
            }
        }
    }
    return NULL;
}

static int run_matrix(int argc, char **argv, const char *variant,
                      void (*inject)(const bench_config *, double *, size_t))
{
    bench_config cfg = parse_config(argc, argv, 128, 608);
    if (cfg.n > SIZE_MAX / cfg.n || cfg.n * cfg.n > SIZE_MAX / sizeof(double)) {
        die("matrix dimension too large");
    }
    size_t cells = cfg.n * cfg.n;
    double *a = xmalloc(cells * sizeof(*a));
    double *b = xmalloc(cells * sizeof(*b));
    double *c = xmalloc(cells * sizeof(*c));
    for (size_t i = 0; i < cells; ++i) {
        a[i] = (double)((mix64(cfg.seed + i) % 1000) + 1) / 1000.0;
        b[i] = (double)((mix64(cfg.seed + i + 17) % 1000) + 1) / 1000.0;
        c[i] = (double)((i + 1) % cfg.n) / (double)cfg.n;
    }
    int threads = cfg.threads;
    if ((size_t)threads > cfg.n) threads = (int)cfg.n;
    cfg.threads = threads;
    pthread_t *ids = xmalloc((size_t)threads * sizeof(*ids));
    matrix_worker_args *args = xmalloc((size_t)threads * sizeof(*args));
    for (int t = 0; t < threads; ++t) {
        args[t] = (matrix_worker_args){a, b, c, cfg.n,
            cfg.n * (size_t)t / (size_t)threads,
            cfg.n * (size_t)(t + 1) / (size_t)threads};
        if (pthread_create(&ids[t], NULL, matrix_worker, &args[t]) != 0) die("pthread_create failed");
    }
    for (int t = 0; t < threads; ++t) pthread_join(ids[t], NULL);
    uint64_t checksum = 0;
    size_t stride = cells / 1024 + 1;
    for (size_t i = 0; i < cells; i += stride) {
        checksum ^= (uint64_t)(c[i] * 1000003.0) + mix64(i);
    }
    report_workload("parallel_matrix", variant, &cfg, checksum);
    inject(&cfg, c, cells);
    free(args);
    free(ids);
    free(c);
    free(b);
    free(a);
    return 0;
}

#endif
