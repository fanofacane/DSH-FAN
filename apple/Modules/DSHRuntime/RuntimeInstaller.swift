// SPDX-License-Identifier: AGPL-3.0-or-later
import CryptoKit
import Foundation
import ish

/// A stable error code; UI maps codes to localized text and never shows raw engine output.
public struct RuntimeError: Error, Equatable, Sendable {
    public let code: String
    public init(_ code: String) { self.code = code }
}

final class RuntimeInstaller {
    let base: URL
    let root: URL
    let manifest: [String: Any]
    private let assets: URL
    private let fm = FileManager.default
    var pendingURL: URL { base.appendingPathComponent("pending-operation.json") }
    private var installedURL: URL { base.appendingPathComponent("installed.json") }
    private var retired: URL { base.appendingPathComponent("retired-rootfs", isDirectory: true) }
    var version: String { manifest["runtimeVersion"] as? String ?? "" }
    var installedVersion: String? {
        guard fm.fileExists(atPath: root.appendingPathComponent("meta.db").path),
              let data = try? Data(contentsOf: installedURL),
              let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return record["runtimeVersion"] as? String
    }
    var current: Bool { !version.isEmpty && installedVersion == version }
    var pending: Bool { fm.fileExists(atPath: pendingURL.path) }

    init(assets: URL = Bundle.main.bundleURL.appendingPathComponent("runtime", isDirectory: true)) throws {
        base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("DSHRuntime", isDirectory: true)
        root = base.appendingPathComponent("rootfs", isDirectory: true)
        self.assets = assets
        manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: assets.appendingPathComponent("manifest.json"))) as? [String: Any] ?? [:]
        guard manifest["abi"] as? String == "ios-arm64", !version.isEmpty else { throw RuntimeError("E_MANIFEST") }
        try fm.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try excludeBackup(base)
    }
    private func excludeBackup(_ path: URL) throws {
        var url = path, values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    func availableBytes() throws -> Int64 {
        let values = try base.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let capacity = values.volumeAvailableCapacityForImportantUsage else { throw RuntimeError("E_STORAGE_UNAVAILABLE") }
        return capacity
    }
    func deferOperation(_ operation: String, keep: [String]) throws {
        // Written before stop. It survives termination, but contains no credentials.
        let data = try JSONSerialization.data(withJSONObject: ["operation": operation, "keep": keep])
        try data.write(to: pendingURL, options: .atomic)
    }
    func reset(keep: [String]) throws {
        // Only called while the kernel has never booted in this App process.
        try stageRetired(keep: keep)
        try? fm.removeItem(at: installedURL)
        if pending { try fm.removeItem(at: pendingURL) }
    }
    func discardKept() throws {
        if fm.fileExists(atPath: retired.path) { try fm.removeItem(at: retired) }
        let record = base.appendingPathComponent("retired-keep.json")
        if fm.fileExists(atPath: record.path) { try fm.removeItem(at: record) }
    }
    private func stageRetired(keep: [String]) throws {
        if fm.fileExists(atPath: retired.path) {
            if !keep.isEmpty { return } // Resume an interrupted install with retained data.
            try fm.removeItem(at: retired) // An explicit reset that keeps nothing wins.
        }
        if fm.fileExists(atPath: root.path) {
            if keep.isEmpty { try fm.removeItem(at: root) }
            else { try fm.moveItem(at: root, to: retired) }
        }
        let data = try JSONSerialization.data(withJSONObject: keep)
        try data.write(to: base.appendingPathComponent("retired-keep.json"), options: .atomic)
    }
    func finishPending(progress: @escaping (String, Int64, Int64) -> Void) throws {
        guard pending else { return }
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: pendingURL)) as? [String: Any]
        guard let operation = value?["operation"] as? String, ["reset", "install"].contains(operation),
              let keep = value?["keep"] as? [String] else { throw RuntimeError("E_PENDING_OPERATION") }
        try stageRetired(keep: operation == "install" ? ["root"] : keep)
        try? fm.removeItem(at: installedURL)
        try install(progress: progress)
        try fm.removeItem(at: pendingURL)
    }
    func install(progress: @escaping (String, Int64, Int64) -> Void) throws {
        if current { return }
        let uncompressed = (manifest["uncompressedBytes"] as? NSNumber)?.int64Value ?? 0
        guard uncompressed > 0,
              let filename = manifest["rootfs"] as? String, filename == "rootfs-ios-arm64.tar.xz",
              let expected = manifest["rootfsSha256"] as? String else { throw RuntimeError("E_MANIFEST") }
        // fakefs + staging/merge/archive overhead. A retained tree needs extra room.
        let keepExists = fm.fileExists(atPath: retired.path) || installedVersion != nil
        let required = uncompressed * (keepExists ? 4 : 115) / (keepExists ? 1 : 100)
        guard try availableBytes() >= required else { throw RuntimeError("ENOSPC") }
        let archive = assets.appendingPathComponent(filename)
        let total = (manifest["rootfsBytes"] as? NSNumber)?.int64Value ?? 0
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        var hash = SHA256(), done: Int64 = 0
        progress("verify", 0, total)
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hash.update(data: data); done += Int64(data.count); progress("verify", done, total)
        }
        guard done == total, hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected else { throw RuntimeError("E_HASH_MISMATCH") }
        if installedVersion != nil { try stageRetired(keep: ["root"]) }
        let staging = base.appendingPathComponent("installing-rootfs", isDirectory: true)
        let merged = base.appendingPathComponent("merged.tar")
        defer { try? fm.removeItem(at: merged); try? fm.removeItem(at: staging) }
        try? fm.removeItem(at: staging)
        var input = archive
        if fm.fileExists(atPath: retired.path) {
            let keep = try JSONSerialization.jsonObject(with: Data(contentsOf: base.appendingPathComponent("retired-keep.json"))) as? [String] ?? []
            if !keep.isEmpty {
                if let error = dsh_kernel_preserve(archive.path, retired.path, keep, merged.path) { throw RuntimeError(error) }
                input = merged
            }
        }
        progress("extract", 0, 1000)
        if let error = dsh_kernel_import(input.path, staging.path, { fraction in
            progress("extract", Int64(fraction * 1000), 1000)
        }) { throw RuntimeError(error) }
        progress("configure", 0, 1)
        try excludeBackup(staging)
        if fm.fileExists(atPath: root.path) { try fm.removeItem(at: root) }
        try fm.moveItem(at: staging, to: root)
        try JSONSerialization.data(withJSONObject: ["runtimeVersion": version]).write(to: installedURL, options: .atomic)
        try? fm.removeItem(at: retired)
        try? fm.removeItem(at: base.appendingPathComponent("retired-keep.json"))
        progress("configure", 1, 1)
    }
    static func keepPaths(_ groups: [String]) throws -> [String] {
        guard groups.allSatisfy({ ["uiAndSkills", "pluginsAndSettings"].contains($0) }) else { throw RuntimeError("E_RESET_KEEP") }
        return (groups.contains("uiAndSkills") ? ["root/.dsh/dsh-fan", "root/.dsh/skills", "root/.agents/skills", "root/.agents/AGENTS.md"] : []) +
            (groups.contains("pluginsAndSettings") ? ["root/.dsh/profiles", "root/.dsh/cordis.patch.yml", "root/.dsh/.env"] : [])
    }
}
