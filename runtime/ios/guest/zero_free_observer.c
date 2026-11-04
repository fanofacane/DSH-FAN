// SPDX-License-Identifier: AGPL-3.0-or-later
// Test-only next-in-chain free: inspect bytes BEFORE libc frees the object.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <stdint.h>
#include <malloc.h>
static void *watched;
static size_t watched_size;
static int observed;
void observe_free(void *p, size_t size) { watched = p; watched_size = size; observed = 0; }
int free_was_zero(void) { return observed; }
void free(void *p) {
    if (p && watched && (uintptr_t)p <= (uintptr_t)watched &&
        (uintptr_t)watched - (uintptr_t)p + watched_size <= malloc_usable_size(p)) {
        observed = 1;
        for (size_t i = 0; i < watched_size; ++i)
            if (((unsigned char *)watched)[i] != 0) observed = -1;
        watched = NULL;
    }
    void (*libc_free)(void *) = dlsym(RTLD_NEXT, "free");
    libc_free(p);
}
