// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from iSH and OpenMinis, retaining their contributors' copyright.
// Based on the phase-1 RuntimeKernel bridge (git 68d6415); see notices.
#import "ISHRuntime.h"
#define ISH_INTERNAL
#include <mach/mach.h>
#include <os/proc.h>
#include <TargetConditionals.h>
#include <locale.h>
#include <sys/stat.h>
#include <resolv.h>
#include <netdb.h>
#include "kernel/init.h"
#include "kernel/task.h"
#include "kernel/calls.h"
#include "kernel/fs.h"
#include "fs/real.h"
#include "fs/fake.h"
#include "fs/dev.h"
#include "fs/devices.h"
#include "fs/fd.h"
#include "fs/path.h"
#include "fs/proc.h"
#include "tools/fakefs.h"
#include <archive.h>
#include <archive_entry.h>

static struct task *init_task;
static BOOL boot_attempted;
static dispatch_source_t memory_feed;
static NSMutableDictionary<NSNumber *, NSNumber *> *exits;
static NSMutableSet<NSNumber *> *tracked_children;
extern int do_wait(int, pid_t_, struct siginfo_ *, struct rusage_ *, int);
// Guest wait ABI, private constants in the pinned kernel/exit.c (not Darwin's).
enum { P_ALL_ = 0, WNOHANG_ = 1, WEXITED_ = 4 };
static uint64_t physical_footprint(void) {
    task_vm_info_data_t info = {0};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return 0;
    return info.phys_footprint;
}
// Adapted from iSH app/AppDelegate.m: copy the host resolver's nameservers
// and search domains into the guest. Returns nil when the host has none.
static NSString *host_resolv_conf(void) {
    struct __res_state res;
    memset(&res, 0, sizeof(res));
    if (res_ninit(&res) != 0) return nil;
    NSMutableString *conf = [NSMutableString string];
    if (res.dnsrch[0] != NULL) {
        [conf appendString:@"search"];
        for (int i = 0; res.dnsrch[i] != NULL; i++) [conf appendFormat:@" %s", res.dnsrch[i]];
        [conf appendString:@"\n"];
    }
    union res_sockaddr_union servers[MAXNS];
    int found = res_getservers(&res, servers, MAXNS);
    int written = 0;
    for (int i = 0; i < found; i++) {
        struct sockaddr *address = (struct sockaddr *) &servers[i].sin;
        if (address->sa_len == 0) continue;
        char host[NI_MAXHOST];
        if (getnameinfo(address, address->sa_len, host, sizeof(host), NULL, 0, NI_NUMERICHOST) != 0) continue;
        [conf appendFormat:@"nameserver %s\n", host];
        written++;
    }
    res_ndestroy(&res);
    return written ? conf : nil;
}

static BOOL write_guest_file(const char *path, NSString *text) {
    struct fd *fd = generic_open(path, O_WRONLY_ | O_CREAT_ | O_TRUNC_, 0644);
    if (IS_ERR(fd)) return NO;
    NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
    ssize_t count = fd->ops->write(fd, bytes.bytes, bytes.length);
    fd_close(fd);
    return count == (ssize_t) bytes.length;
}
static void feed_memory_status(void) {
    // Same admission API as OpenMinis' host governor. Without a live feed,
    // the legacy commitment ledger refuses Node's fourth 128 MB thread
    // stack even when the host has ample memory. Read real host headroom;
    // do not raise the kernel ceiling or invent a device memory allowance.
    uint64_t footprint = physical_footprint();
    uint64_t available = os_proc_available_memory();
#if TARGET_OS_SIMULATOR
    // Simulator reports zero for the iOS Jetsam allowance. Use measured
    // Reclaimable Mac pages for simulator functionality, never an iPhone budget.
    // Darwin available = free + inactive (the same accounting as psutil/Zabbix).
    // Free alone collapses after a large build despite gigabytes of file cache.
    if (available == 0) {
        vm_statistics64_data_t stats = {0};
        mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
        mach_port_t host = mach_host_self();
        kern_return_t result = host_statistics64(host, HOST_VM_INFO64,
                                                 (host_info64_t)&stats, &count);
        mach_port_deallocate(mach_task_self(), host);
        if (result != KERN_SUCCESS) return;
        available = ((uint64_t)stats.free_count + (uint64_t)stats.inactive_count) * (uint64_t)getpagesize();
    }
#endif
    ish_set_memory_status(footprint + available, available, false);
}

static void import_progress(void *cookie, double value, const char *message, bool *cancel) {
    void (^callback)(double) = (__bridge id)cookie;
    callback(value); // Never expose guest filenames to logs or events.
}
NSString *dsh_kernel_import(NSString *archive, NSString *root, void (^progress)(double)) {
    if (boot_attempted) return @"E_RESTART_REQUIRED";
    if (setlocale(LC_CTYPE, "en_US.UTF-8") == NULL) return @"E_UTF8_LOCALE";
    struct fakefsify_error error = {0};
    if (!fakefs_import(archive.fileSystemRepresentation, root.fileSystemRepresentation,
                      &error, (struct progress){(__bridge void *)progress, import_progress})) {
        // libarchive errors may include paths. Surface a stable code only.
        free(error.message);
        [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
        return @"E_ROOTFS_IMPORT";
    }
    return nil;
}
static BOOL selected_path(const char *value, NSArray<NSString *> *paths) {
    NSString *name = [NSString stringWithUTF8String:value ?: ""];
    while ([name hasPrefix:@"./"]) name = [name substringFromIndex:2];
    while ([name hasSuffix:@"/"]) name = [name substringToIndex:name.length - 1];
    for (NSString *path in paths)
        if ([name isEqualToString:path] || [name hasPrefix:[path stringByAppendingString:@"/"]]) return YES;
    return NO;
}
static BOOL append_archive(struct archive *writer, NSString *path, NSArray *paths, BOOL keep) {
    struct archive *reader = archive_read_new();
    archive_read_support_filter_gzip(reader); archive_read_support_filter_xz(reader);
    archive_read_support_format_tar(reader);
    BOOL ok = archive_read_open_filename(reader, path.fileSystemRepresentation, 65536) == ARCHIVE_OK;
    struct archive_entry *entry;
    int status = ARCHIVE_EOF;
    while (ok && (status = archive_read_next_header(reader, &entry)) == ARCHIVE_OK) {
        if (selected_path(archive_entry_pathname(entry), paths) != keep) continue;
        const char *target = archive_entry_hardlink(entry);
        if (keep && target && !selected_path(target, paths)) { ok = NO; break; }
        if (archive_write_header(writer, entry) != ARCHIVE_OK) { ok = NO; break; }
        char buffer[65536];
        la_ssize_t count;
        while ((count = archive_read_data(reader, buffer, sizeof(buffer))) > 0) {
            if (archive_write_data(writer, buffer, count) != count) { ok = NO; break; }
        }
        if (count < 0) ok = NO;
    }
    if (status != ARCHIVE_EOF) ok = NO;
    archive_read_free(reader);
    return ok;
}
NSString *dsh_kernel_preserve(NSString *archive, NSString *oldRoot, NSArray *paths, NSString *mergedArchive) {
    if (boot_attempted) return @"E_RESTART_REQUIRED";
    if (setlocale(LC_CTYPE, "en_US.UTF-8") == NULL) return @"E_UTF8_LOCALE";
    NSString *oldArchive = [mergedArchive stringByAppendingString:@".old.tar.gz"];
    struct fakefsify_error error = {0};
    if (!fakefs_export(oldRoot.fileSystemRepresentation, oldArchive.fileSystemRepresentation,
                       &error, (struct progress){0})) {
        free(error.message);
        [[NSFileManager defaultManager] removeItemAtPath:oldArchive error:nil];
        return @"E_KEEP_EXPORT";
    }
    struct archive *writer = archive_write_new();
    archive_write_set_format_pax_restricted(writer);
    BOOL ok = archive_write_open_filename(writer, mergedArchive.fileSystemRepresentation) == ARCHIVE_OK;
    if (ok) ok = append_archive(writer, archive, paths, NO) && append_archive(writer, oldArchive, paths, YES);
    if (archive_write_close(writer) != ARCHIVE_OK) ok = NO;
    archive_write_free(writer);
    [[NSFileManager defaultManager] removeItemAtPath:oldArchive error:nil];
    return ok ? nil : @"E_KEEP_MERGE";
}
static void *reap_children(void *unused) {
    current = init_task;
    init_task->thread = pthread_self();
    // PID 1 has no guest executable, CPU loop, shell or business logic.
    // Only this permanent host thread waits for/reaps its adopted children.
    for (;;) {
        @autoreleasepool {
            struct siginfo_ info = {0};
            while (do_wait(P_ALL_, 0, &info, NULL, WNOHANG_ | WEXITED_) == 0 && info.child.pid != 0) {
                @synchronized (exits) {
                    // Shell/PTY grandchildren are reaped too, but only native
                    // spawn callers need exit records. A burst of guest forks
                    // must not evict the current engine's completion status.
                    NSNumber *pid = @(info.child.pid);
                    if ([tracked_children containsObject:pid]) {
                        if (exits.count >= 256) [exits removeAllObjects];
                        exits[pid] = @(info.child.status);
                        [tracked_children removeObject:pid];
                    }
                }
                memset(&info, 0, sizeof(info));
            }
        }
        usleep(20000);
    }
    return NULL;
}
NSString *dsh_kernel_boot(NSString *root) {
    if (boot_attempted) return @"E_RESTART_REQUIRED";
    boot_attempted = YES;
    unsetenv("ISH_EXEC_TRACE"); unsetenv("ISH_SYSTRACE");
    if (setlocale(LC_CTYPE, "en_US.UTF-8") == NULL) return @"E_UTF8_LOCALE";
    extern const char *sock_tmp_prefix;
    sock_tmp_prefix = strdup([[NSTemporaryDirectory() stringByAppendingPathComponent:@"dsh-"] fileSystemRepresentation]);
    int err = mount_root(&fakefs, [[root stringByAppendingPathComponent:@"data"] fileSystemRepresentation]);
    if (err < 0) return @"E_MOUNT_ROOT";
    err = become_first_process();
    if (err < 0) return @"E_INIT";
    init_task = current;
    generic_mknodat(AT_PWD, "/dev/null", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_NULL_MINOR));
    generic_mknodat(AT_PWD, "/dev/zero", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_ZERO_MINOR));
    generic_mknodat(AT_PWD, "/dev/random", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_RANDOM_MINOR));
    generic_mknodat(AT_PWD, "/dev/urandom", S_IFCHR | 0666, dev_make(MEM_MAJOR, DEV_URANDOM_MINOR));
    generic_mknodat(AT_PWD, "/dev/ptmx", S_IFCHR | 0666, dev_make(TTY_ALTERNATE_MAJOR, DEV_PTMX_MINOR));
    if (do_mount(&procfs, "proc", "/proc", "", 0) < 0) return @"E_MOUNT_PROC";
    if (do_mount(&devptsfs, "devpts", "/dev/pts", "", 0) < 0) return @"E_MOUNT_DEVPTS";
    if (!write_guest_file("/etc/hosts", @"127.0.0.1 localhost\n::1 localhost\n")) return @"E_HOSTS";
    NSString *resolv = host_resolv_conf();
    if (!resolv) return @"E_NO_HOST_DNS";
    if (!write_guest_file("/etc/resolv.conf", resolv)) return @"E_RESOLV_CONF";
    feed_memory_status();
    memory_feed = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                          dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(memory_feed, DISPATCH_TIME_NOW, NSEC_PER_SEC, NSEC_PER_SEC / 10);
    dispatch_source_set_event_handler(memory_feed, ^{ feed_memory_status(); });
    dispatch_resume(memory_feed);
    exits = [NSMutableDictionary dictionary];
    tracked_children = [NSMutableSet set];
    pthread_t reaper;
    if (pthread_create(&reaper, NULL, reap_children, NULL) != 0) return @"E_REAPER_THREAD";
    pthread_detach(reaper);
    current = NULL;
    return nil;
}
static struct fd *output_fd(BOOL stderr_stream, void (^output)(NSString *, BOOL)) {
    int endpoints[2];
    if (pipe(endpoints) < 0) return NULL;
    int input = endpoints[0];
    [NSThread detachNewThreadWithBlock:^{
        @autoreleasepool {
            NSMutableData *line = [NSMutableData data];
            BOOL discard = NO;
            char bytes[4096];
            ssize_t count;
            while ((count = read(input, bytes, sizeof(bytes))) != 0) {
                if (count < 0) { if (errno == EINTR) continue; break; }
                for (ssize_t i = 0; i < count; i++) {
                    if (bytes[i] == '\n') {
                        if (!discard) {
                            @autoreleasepool {
                                output([[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding] ?: @"[invalid UTF-8]", stderr_stream);
                            }
                        }
                        [line setLength:0]; discard = NO;
                    } else if (!discard) {
                        if (line.length >= 16384) { [line setLength:0]; discard = YES; }
                        else [line appendBytes:&bytes[i] length:1];
                    }
                }
            }
            if (!discard && line.length) output([[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding] ?: @"[invalid UTF-8]", stderr_stream);
            close(input);
        }
    }];
    struct fd *fd = adhoc_fd_create(&realfs_fdops);
    if (!fd) { close(endpoints[1]); return NULL; }
    fd->real_fd = endpoints[1]; fd->stat.mode = S_IFIFO | 0600; fd->flags = O_WRONLY_;
    return fd;
}
void dsh_kernel_spawn(NSArray<NSString *> *argv, NSDictionary<NSString *, NSString *> *environment,
                      void (^output)(NSString *, BOOL), void (^started)(int, int)) {
    [NSThread detachNewThreadWithBlock:^{
        @autoreleasepool {
            if (!init_task || !argv.count) { started(-1, -EINVAL); return; }
            current = init_task;
            int err = become_new_init_child();
            if (err < 0) { current = NULL; started(-1, err); return; }
            current->thread = pthread_self();
            int pid = current->pid;
            @synchronized (exits) {
                [exits removeObjectForKey:@(pid)];
                [tracked_children addObject:@(pid)];
            }
            NSMutableData *args = [NSMutableData data], *env = [NSMutableData data];
            for (NSString *value in argv) { [args appendData:[value dataUsingEncoding:NSUTF8StringEncoding]]; [args appendBytes:"\0" length:1]; }
            [args appendBytes:"\0" length:1];
            for (NSString *key in environment) {
                NSString *value = [NSString stringWithFormat:@"%@=%@", key, environment[key]];
                [env appendData:[value dataUsingEncoding:NSUTF8StringEncoding]]; [env appendBytes:"\0" length:1];
            }
            [env appendBytes:"\0" length:1];
            err = do_execve(argv[0].UTF8String, (int)argv.count, args.bytes, env.bytes);
            if (err < 0) { started(-1, err); do_exit(127 << 8); }
            current->files->files[0] = generic_open("/dev/null", O_RDONLY_, 0);
            current->files->files[1] = output_fd(NO, output);
            current->files->files[2] = output_fd(YES, output);
            if (IS_ERR(current->files->files[0]) || !current->files->files[1] || !current->files->files[2]) {
                // do_exit expects valid file entries when it releases the table.
                if (IS_ERR(current->files->files[0])) current->files->files[0] = NULL;
                started(-1, -EMFILE); do_exit(127 << 8);
            }
            err = task_start(current);
            if (err < 0) { started(-1, err); do_exit(127 << 8); }
            current = NULL;
            started(pid, 0);
        }
    }];
}
int dsh_kernel_signal(int pid, int signal) {
    if (pid <= 1 || (signal != SIGTERM_ && signal != SIGKILL_ && signal != SIGINT_)) return -EINVAL;
    lock(&pids_lock);
    struct task *task = pid_get_task(pid);
    BOOL found = task != NULL;
    if (task) deliver_signal(task, signal, SIGINFO_NIL);
    unlock(&pids_lock);
    return found ? 0 : -ESRCH;
}
NSArray *dsh_kernel_processes(void) {
    NSMutableArray *items = [NSMutableArray array];
    if (!init_task) return items;
    lock(&pids_lock);
    for (int pid = 1; pid < MAX_PID; pid++) {
        struct task *task = pid_get_task_zombie(pid);
        if (task) [items addObject:@{@"pid":@(pid), @"zombie":@(task->zombie)}];
    }
    unlock(&pids_lock);
    return items;
}
NSNumber *dsh_kernel_exit_status(int pid) {
    if (!exits) return nil;
    @synchronized (exits) { return exits[@(pid)]; }
}
BOOL dsh_kernel_write(NSString *path, NSString *text) {
    if (!init_task) return NO;
    struct task *previous = current;
    current = init_task;
    BOOL result = write_guest_file(path.UTF8String, text);
    current = previous;
    return result;
}

// All access goes through fakefs/VFS so meta.db stays authoritative. These
// helpers are called by the serial runtime worker before guest children start.
int dsh_kernel_mode(NSString *path) {
    if (!init_task) return -EAGAIN;
    struct task *previous = current; current = init_task;
    struct statbuf st;
    int error = generic_statat(AT_PWD, path.UTF8String, &st, false);
    current = previous;
    return error < 0 ? error : (int)st.mode;
}
BOOL dsh_kernel_mkdir(NSString *path, int mode) {
    if (!init_task) return NO;
    struct task *previous = current; current = init_task;
    int error = generic_mkdirat(AT_PWD, path.UTF8String, mode & 0777);
    if (error == -EEXIST) {
        struct statbuf st;
        error = generic_statat(AT_PWD, path.UTF8String, &st, false);
        if (error == 0 && (st.mode & S_IFMT) != S_IFDIR) error = -ENOTDIR;
    }
    if (error == 0) error = generic_setattrat(AT_PWD, path.UTF8String, make_attr(mode, mode & 0777), false);
    current = previous; return error == 0;
}
BOOL dsh_kernel_unlink(NSString *path) {
    if (!init_task) return NO;
    struct task *previous = current; current = init_task;
    int error = generic_unlinkat(AT_PWD, path.UTF8String);
    current = previous; return error == 0 || error == -ENOENT;
}
BOOL dsh_kernel_write_mode(NSString *path, NSString *text, int mode) {
    if (!init_task || (mode != 0600 && mode != 0644)) return NO;
    struct task *previous = current; current = init_task;
    NSString *temporary = [path stringByAppendingFormat:@".dsh-%@", NSUUID.UUID.UUIDString];
    struct fd *fd = generic_open(temporary.UTF8String, O_WRONLY_ | O_CREAT_ | O_EXCL_, mode);
    BOOL ok = !IS_ERR(fd);
    if (ok) {
        NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
        NSUInteger offset = 0;
        while (offset < bytes.length) {
            ssize_t count = fd->ops->write(fd, bytes.bytes + offset, bytes.length - offset);
            if (count <= 0) { ok = NO; break; }
            offset += count;
        }
        fd_close(fd);
        if (ok) ok = generic_setattrat(AT_PWD, temporary.UTF8String, make_attr(mode, mode), false) == 0;
        if (ok) ok = generic_renameat(AT_PWD, temporary.UTF8String, AT_PWD, path.UTF8String) == 0;
    }
    if (!ok) generic_unlinkat(AT_PWD, temporary.UTF8String);
    current = previous;
    return ok && (dsh_kernel_mode(path) & 0777) == mode;
}
NSString *dsh_kernel_read_text(NSString *path, NSUInteger maxBytes) {
    if (!init_task) return nil;
    struct task *previous = current; current = init_task;
    struct fd *fd = generic_open(path.UTF8String, O_RDONLY_ | O_NONBLOCK_, 0);
    NSMutableData *data = [NSMutableData data];
    BOOL ok = !IS_ERR(fd);
    if (ok) {
        ok = fd->type == S_IFREG;
        char buffer[8192];
        while (ok) {
            ssize_t count = fd->ops->read(fd, buffer, sizeof(buffer));
            if (count < 0 || (NSUInteger)count > maxBytes - data.length) { ok = NO; break; }
            if (count == 0) break;
            [data appendBytes:buffer length:count];
        }
        fd_close(fd);
    }
    current = previous;
    return ok ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

int dsh_kernel_copy_out(NSString *path, NSString *destination, uint64_t maxBytes) {
    if (!init_task) return -EAGAIN;
    struct task *previous = current;
    current = init_task;
    struct fd *input = generic_open(path.UTF8String, O_RDONLY_ | O_NONBLOCK_, 0);
    current = previous;
    if (IS_ERR(input)) return (int)PTR_ERR(input);
    if (input->type != S_IFREG) { fd_close(input); return -EISDIR; }
    int output = open(destination.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (output < 0) { fd_close(input); return -errno; }
    int result = 0;
    uint64_t total = 0;
    char bytes[65536];
    current = init_task;
    for (;;) {
        ssize_t count = input->ops->read(input, bytes, sizeof(bytes));
        if (count < 0) { result = (int)count; break; }
        if (count == 0) break;
        if ((uint64_t)count > maxBytes - total) { result = -EFBIG; break; }
        total += count;
        ssize_t offset = 0;
        while (offset < count) {
            ssize_t wrote = write(output, bytes + offset, count - offset);
            if (wrote < 0 && errno == EINTR) continue;
            if (wrote <= 0) { result = -EIO; break; }
            offset += wrote;
        }
        if (result) break;
    }
    fd_close(input);
    current = previous;
    close(output);
    if (result) unlink(destination.fileSystemRepresentation);
    return result;
}
