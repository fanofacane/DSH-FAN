// SPDX-License-Identifier: AGPL-3.0-or-later
#define _GNU_SOURCE
#include <assert.h>
#include <dlfcn.h>
#include <errno.h>
#include <malloc.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void zeros(const void *p, size_t n) {
    for (size_t i = 0; i < n; ++i) assert(((const unsigned char *)p)[i] == 0);
}
static void *worker(void *arg) {
    (void)arg;
    for (int i = 0; i < 100; ++i) {
        void *p = malloc(8192); assert(p); zeros(p, 8192); memset(p, 0xA5, 8192); free(p);
    }
    return NULL;
}
int main(void) {
    void (*observe)(void *, size_t) = dlsym(RTLD_DEFAULT, "observe_free");
    int (*was_zero)(void) = dlsym(RTLD_DEFAULT, "free_was_zero");
    assert(observe && was_zero);
    for (size_t n = 4096; n <= 8192; n *= 2) {
        unsigned char *p = malloc(n); assert(p); zeros(p, n);
        memset(p, 0xA5, n); observe(p, n); errno = EDOM; free(p);
        assert(errno == EDOM && was_zero() == 1);
    }
    unsigned char *p = calloc(512, 8); assert(p); zeros(p, 4096); memset(p, 0x5A, 4096);
    observe(p, 4096);
    p = realloc(p, 16384); assert(p && was_zero() == 1);
    for (size_t i = 0; i < 4096; ++i) assert(p[i] == 0x5A);
    zeros(p + 8192, 8192);
    observe(p, 16384); p = realloc(p, 64); assert(p && was_zero() == 1);
    for (size_t i = 0; i < 64; ++i) assert(p[i] == 0x5A);
    free(p);
    void *aligned = NULL; assert(posix_memalign(&aligned, 4096, 8192) == 0);
    memset(aligned, 0x77, 8192); observe(aligned, 8192); free(aligned); assert(was_zero() == 1);
    volatile size_t huge = SIZE_MAX;
    assert(calloc(huge, 2) == NULL);
    free(NULL);
    pthread_t threads[4];
    for (int i = 0; i < 4; ++i) assert(pthread_create(&threads[i], NULL, worker, NULL) == 0);
    for (int i = 0; i < 4; ++i) pthread_join(threads[i], NULL);
    puts("zero_free allocation/free/realloc/alignment/overflow/thread checks PASS");
}
