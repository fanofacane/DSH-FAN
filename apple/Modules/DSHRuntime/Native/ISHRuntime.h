// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// All blocking calls belong on a background worker. No API destroys the kernel.
NSString * _Nullable dsh_kernel_import(NSString *archive, NSString *root, void (^progress)(double));
// Merge only selected guest paths from a retired fakefs, before any kernel boot.
NSString * _Nullable dsh_kernel_preserve(NSString *archive, NSString *oldRoot,
                                        NSArray<NSString *> *paths, NSString *mergedArchive);
NSString * _Nullable dsh_kernel_boot(NSString *root);
void dsh_kernel_spawn(NSArray<NSString *> *argv, NSDictionary<NSString *, NSString *> *environment,
                      void (^output)(NSString *, BOOL), void (^started)(int, int));
int dsh_kernel_signal(int pid, int signal);
NSArray<NSDictionary<NSString *, NSNumber *> *> *dsh_kernel_processes(void);
NSNumber * _Nullable dsh_kernel_exit_status(int pid);
BOOL dsh_kernel_write(NSString *path, NSString *text);
BOOL dsh_kernel_write_mode(NSString *path, NSString *text, int mode);
BOOL dsh_kernel_mkdir(NSString *path, int mode);
int dsh_kernel_mode(NSString *path);
BOOL dsh_kernel_unlink(NSString *path);
NSString * _Nullable dsh_kernel_read_text(NSString *path, NSUInteger maxBytes);
// Stream a regular guest file through VFS into a caller-owned temporary file.
int dsh_kernel_copy_out(NSString *path, NSString *destination, uint64_t maxBytes);
NS_ASSUME_NONNULL_END
