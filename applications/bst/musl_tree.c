#include <stdlib.h>
#include "musl_tree.h"

#define MAXH (sizeof(void *) * 8 * 3 / 2)

struct node {
    const void *key;
    struct node *a[2];
    int h;
};

static int height(struct node *n) { return n ? n->h : 0; }

static int rotate(void **p, struct node *x, int dir)
{
    struct node *y = x->a[dir];
    struct node *z = y->a[!dir];
    int hx = x->h;
    int hz = height(z);
    if (hz > height(y->a[dir])) {
        x->a[dir] = z->a[!dir];
        y->a[!dir] = z->a[dir];
        z->a[!dir] = x;
        z->a[dir] = y;
        x->h = hz;
        y->h = hz;
        z->h = hz + 1;
    } else {
        x->a[dir] = z;
        y->a[!dir] = x;
        x->h = hz + 1;
        y->h = hz + 2;
        z = y;
    }
    *p = z;
    return z->h - hx;
}

static int balance(void **p)
{
    struct node *n = *p;
    int h0 = height(n->a[0]);
    int h1 = height(n->a[1]);
    if ((unsigned)(h0 - h1 + 1) < 3U) {
        int old = n->h;
        n->h = h0 < h1 ? h1 + 1 : h0 + 1;
        return n->h - old;
    }
    return rotate(p, n, h0 < h1);
}

void *bench_tsearch(const void *key, void **rootp,
                    int (*cmp)(const void *, const void *))
{
    if (rootp == NULL) return NULL;
    void **ancestors[MAXH];
    struct node *n = *rootp;
    int i = 0;
    ancestors[i++] = rootp;
    while (n != NULL) {
        int c = cmp(key, n->key);
        if (c == 0) return n;
        ancestors[i++] = (void **)&n->a[c > 0];
        n = n->a[c > 0];
    }
    struct node *created = malloc(sizeof(*created));
    if (created == NULL) return NULL;
    created->key = key;
    created->a[0] = created->a[1] = NULL;
    created->h = 1;
    *ancestors[--i] = created;
    while (i && balance(ancestors[--i])) {}
    return created;
}

void *bench_tfind(const void *key, void *const *rootp,
                  int (*cmp)(const void *, const void *))
{
    if (rootp == NULL) return NULL;
    struct node *n = *rootp;
    while (n != NULL) {
        int c = cmp(key, n->key);
        if (c == 0) return n;
        n = n->a[c > 0];
    }
    return NULL;
}

static void destroy_node(struct node *n, void (*free_key)(void *))
{
    if (n == NULL) return;
    destroy_node(n->a[0], free_key);
    destroy_node(n->a[1], free_key);
    if (free_key != NULL) free_key((void *)n->key);
    free(n);
}

void bench_tdestroy(void *root, void (*free_key)(void *))
{
    destroy_node(root, free_key);
}
