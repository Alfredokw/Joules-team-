#ifndef SEB_HASH_CORE_H
#define SEB_HASH_CORE_H

#include "../../vendor/uthash/uthash.h"

typedef struct hash_entry {
    uint64_t key;
    uint64_t value;
    UT_hash_handle hh;
} hash_entry;

typedef struct {
    hash_entry *table;
    uint64_t *queries;
    size_t begin;
    size_t end;
    uint64_t checksum;
} hash_worker_args;

static void *hash_worker(void *opaque)
{
    hash_worker_args *args = opaque;
    uint64_t checksum = 0;
    for (size_t i = args->begin; i < args->end; ++i) {
        hash_entry *found = NULL;
        HASH_FIND(hh, args->table, &args->queries[i], sizeof(uint64_t), found);
        if (found != NULL) checksum ^= found->value + mix64(i);
    }
    args->checksum = checksum;
    return NULL;
}

static int run_hash(int argc, char **argv, const char *variant,
                    void (*inject)(const bench_config *, uint64_t *, size_t))
{
    bench_config cfg = parse_config(argc, argv, 50000, 300000);
    hash_entry *table = NULL;
    for (size_t i = 0; i < cfg.n; ++i) {
        hash_entry *entry = xmalloc(sizeof(*entry));
        entry->key = mix64(cfg.seed + i + 1);
        entry->value = mix64(cfg.seed + i + 101);
        HASH_ADD(hh, table, key, sizeof(uint64_t), entry);
    }
    size_t query_count = cfg.n * 5;
    uint64_t *queries = xmalloc(query_count * sizeof(*queries));
    for (size_t i = 0; i < query_count; ++i) {
        queries[i] = (i & 1U) ? mix64(cfg.seed + (i % cfg.n) + 1)
                              : mix64(cfg.seed + cfg.n + i + 1);
    }
    int threads = cfg.threads;
    pthread_t *ids = xmalloc((size_t)threads * sizeof(*ids));
    hash_worker_args *args = xmalloc((size_t)threads * sizeof(*args));
    for (int t = 0; t < threads; ++t) {
        args[t] = (hash_worker_args){table, queries,
            query_count * (size_t)t / (size_t)threads,
            query_count * (size_t)(t + 1) / (size_t)threads, 0};
        if (pthread_create(&ids[t], NULL, hash_worker, &args[t]) != 0) die("pthread_create failed");
    }
    uint64_t checksum = 0;
    for (int t = 0; t < threads; ++t) {
        pthread_join(ids[t], NULL);
        checksum ^= args[t].checksum;
    }
    report_workload("hash_table", variant, &cfg, checksum);
    inject(&cfg, queries, query_count);
    hash_entry *entry, *tmp;
    HASH_ITER(hh, table, entry, tmp) {
        HASH_DEL(table, entry);
        free(entry);
    }
    free(args);
    free(ids);
    free(queries);
    return 0;
}

#endif
