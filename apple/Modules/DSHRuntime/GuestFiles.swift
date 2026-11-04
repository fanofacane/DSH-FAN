// SPDX-License-Identifier: AGPL-3.0-or-later
// Guest filesystem access through the mounted VFS. fakefs keeps metadata in
// meta.db, so host writes into rootfs/data would be invisible to the guest.
// Only valid after boot, from a RuntimeLaunchHook (runtime worker).
import Foundation
import ish

public enum GuestFiles {
    public static func mkdir(_ path: String, mode: Int32) -> Bool { dsh_kernel_mkdir(path, mode) }
    public static func write(_ path: String, _ text: String, mode: Int32) -> Bool { dsh_kernel_write_mode(path, text, mode) }
    /// Permission bits, or a negative value when the path does not exist.
    public static func mode(_ path: String) -> Int32 { dsh_kernel_mode(path) }
    /// True when removed or already absent.
    public static func unlink(_ path: String) -> Bool { dsh_kernel_unlink(path) }
    public static func readText(_ path: String, maxBytes: Int) -> String? { dsh_kernel_read_text(path, UInt(maxBytes)) }
}
