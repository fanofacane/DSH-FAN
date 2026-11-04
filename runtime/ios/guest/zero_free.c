// SPDX-License-Identifier: AGPL-3.0-or-later
// Independently implemented for RuntimeProbe from the zero_malloc.so /
// zero_free.so specification in OpenMinis/ish-arm64 kernel/exec.c at
// c5c264da19148512167aa493d7bd4e50aae1b74e. No implementation was copied.
// Target: musl Linux. Clear >=4096-byte allocations and blocks before free.
// realloc preserves the old contents; clearing must not destroy live JS data.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <malloc.h>
#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <stdatomic.h>
#include <string.h>
#include <unistd.h>

static void *(*next_malloc)(size_t);
static void *(*next_calloc)(size_t, size_t);
static void (*next_free)(void *);
static size_t (*next_usable)(void *);
static pthread_once_t once = PTHREAD_ONCE_INIT;
static _Thread_local int resolving;

// dlsym may recurse into an allocator during startup. These temporary blocks
// never enter musl's heap and are never handed to its free/usable-size routines.
typedef union { max_align_t alignment; size_t size; } boot_header;
static _Alignas(max_align_t) unsigned char boot_arena[65536];
static _Atomic size_t boot_used;
// musl intentionally rejects its own aligned_alloc when malloc is interposed.
// Keep over-aligned pointers interoperable with free/realloc/usable_size.
struct aligned_block { void *pointer, *base; size_t size; struct aligned_block *next; };
static struct aligned_block *aligned_blocks;
static pthread_mutex_t aligned_lock = PTHREAD_MUTEX_INITIALIZER;

static struct aligned_block *find_aligned(void *p, int remove) {
    pthread_mutex_lock(&aligned_lock);
    struct aligned_block **slot = &aligned_blocks;
    while (*slot && (*slot)->pointer != p) slot = &(*slot)->next;
    struct aligned_block *entry = *slot;
    if (entry && remove) *slot = entry->next;
    // Non-removing callers only need size, but free may be concurrent for
    // different objects. Each caller must own p (as for the libc routines).
    pthread_mutex_unlock(&aligned_lock);
    return entry;
}

static int is_boot(const void *p) {
    uintptr_t address = (uintptr_t)p;
    return address >= (uintptr_t)boot_arena &&
           address < (uintptr_t)boot_arena + sizeof(boot_arena);
}

static void *boot_alloc(size_t size) {
    size_t alignment = _Alignof(max_align_t);
    if (size > sizeof(boot_arena) - sizeof(boot_header) - alignment) {
        errno = ENOMEM; return NULL;
    }
    size_t total = (sizeof(boot_header) + size + alignment - 1) & ~(alignment - 1);
    size_t offset = atomic_fetch_add(&boot_used, total);
    if (offset > sizeof(boot_arena) - total) { errno = ENOMEM; return NULL; }
    boot_header *header = (boot_header *)(boot_arena + offset);
    header->size = size;
    return header + 1;
}

static void resolve(void) {
    resolving = 1;
    next_malloc = dlsym(RTLD_NEXT, "malloc");
    next_calloc = dlsym(RTLD_NEXT, "calloc");
    next_free = dlsym(RTLD_NEXT, "free");
    next_usable = dlsym(RTLD_NEXT, "malloc_usable_size");
    resolving = 0;
    if (!next_malloc || !next_calloc || !next_free || !next_usable) {
        static const char message[] = "zero_free: allocator resolution failed\n";
        write(STDERR_FILENO, message, sizeof(message) - 1);
        _exit(127);
    }
}

static void clear(void *p, size_t size) {
    // Volatile stores keep the wipe before free from being optimized away.
    volatile unsigned char *bytes = p;
    while (size--) *bytes++ = 0;
}

void *malloc(size_t size) {
    if (resolving) return boot_alloc(size);
    pthread_once(&once, resolve);
    void *p = next_malloc(size);
    if (p) {
        size_t usable = next_usable(p);
        if (usable >= 4096) clear(p, usable);
    }
    return p;
}

void *calloc(size_t count, size_t size) {
    if (size && count > SIZE_MAX / size) { errno = ENOMEM; return NULL; }
    if (resolving) return boot_alloc(count * size); // static arena starts zeroed
    pthread_once(&once, resolve);
    void *p = next_calloc(count, size);
    if (p) {
        size_t usable = next_usable(p);
        if (usable >= 4096) clear(p, usable);
    }
    return p;
}

void free(void *p) {
    if (!p || is_boot(p)) return;
    int saved_errno = errno;
    pthread_once(&once, resolve);
    struct aligned_block *entry = find_aligned(p, 1);
    void *base = entry ? entry->base : p;
    size_t usable = next_usable(base);
    if (usable >= 4096) clear(base, usable);
    next_free(base);
    if (entry) next_free(entry);
    errno = saved_errno;
}

void *realloc(void *p, size_t size) {
    if (!p) return malloc(size);
    if (!size) { free(p); return NULL; }
    if (!is_boot(p)) pthread_once(&once, resolve);
    size_t old_size = malloc_usable_size(p);
    void *replacement = malloc(size);
    if (!replacement) return NULL; // failed realloc leaves p untouched
    // musl's usable size is the allocated writable extent. Retain existing
    // bytes, then wipe the old allocation through our free interceptor.
    memcpy(replacement, p, old_size < size ? old_size : size);
    free(p);
    return replacement;
}

size_t malloc_usable_size(void *p) {
    if (!p) return 0;
    if (is_boot(p)) return ((boot_header *)p - 1)->size;
    pthread_once(&once, resolve);
    struct aligned_block *entry = find_aligned(p, 0);
    return entry ? entry->size : next_usable(p);
}

void *aligned_alloc(size_t alignment, size_t size) {
    if (!alignment || (alignment & (alignment - 1))) { errno = EINVAL; return NULL; }
    if (alignment <= _Alignof(max_align_t)) return malloc(size);
    if (size > SIZE_MAX - (alignment - 1)) { errno = ENOMEM; return NULL; }
    pthread_once(&once, resolve);
    struct aligned_block *entry = next_malloc(sizeof(*entry));
    void *base = next_malloc(size + alignment - 1);
    if (!entry || !base) {
        next_free(entry); next_free(base); errno = ENOMEM; return NULL;
    }
    size_t usable = next_usable(base);
    if (usable >= 4096) clear(base, usable);
    void *p = (void *)(((uintptr_t)base + alignment - 1) & ~(uintptr_t)(alignment - 1));
    *entry = (struct aligned_block){p, base, size, NULL};
    pthread_mutex_lock(&aligned_lock);
    entry->next = aligned_blocks;
    aligned_blocks = entry;
    pthread_mutex_unlock(&aligned_lock);
    return p;
}

int posix_memalign(void **result, size_t alignment, size_t size) {
    if (alignment < sizeof(void *) || (alignment & (alignment - 1))) return EINVAL;
    int saved_errno = errno;
    void *p = aligned_alloc(alignment, size);
    errno = saved_errno;
    if (!p) return ENOMEM;
    *result = p;
    return 0;
}

void *memalign(size_t alignment, size_t size) { return aligned_alloc(alignment, size); }
