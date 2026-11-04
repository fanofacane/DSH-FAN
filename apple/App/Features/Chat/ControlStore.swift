// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import Foundation
import Observation

@MainActor @Observable final class ControlStore {
    private let shared: PermissionSessionState
    var state = SessionControlState()
    var error: String?
    private(set) var permissionPresets: [PermissionPreset] {
        get { shared.permissionPresets }
        set { shared.permissionPresets = newValue }
    }
    private(set) var enginePermissionDefault: String {
        get { shared.enginePermissionDefault }
        set { shared.enginePermissionDefault = newValue }
    }
    static let iosDefaultPreset = "danger-full-access"
    var permissionPreset: String? {
        get { shared.permissionPreset }
        set { shared.permissionPreset = newValue; prefs.set(newValue, forKey: "chat.permissionPreset") }
    }
    private let prefs = UserDefaults.standard
    private var controlTask: Task<Void, Never>?
    private let context: SessionContext
    private var generation: Int { context.generation }
    private func api() throws -> ControlAPI { ControlAPI(client: try context.requireClient()) }
    init(context: SessionContext) {
        self.context = context; shared = context.permissionState
        // The iOS sandbox already confines the engine; preserve the iOS default preset.
        if prefs.object(forKey: "chat.permissionPreset") == nil { prefs.set(Self.iosDefaultPreset, forKey: "chat.permissionPreset") }
        permissionPreset = prefs.string(forKey: "chat.permissionPreset")
    }
    var projection: SessionProjection { context.currentSessionId.flatMap { state.values[$0] } ?? SessionProjection() }
    func resetFeed() { controlTask?.cancel(); controlTask = nil; state = SessionControlState() }
    func loadPermissions(_ client: DSHClient) async {
        if let presets = try? await client.permissionPresets() { permissionPresets = presets.options; enginePermissionDefault = presets.defaultPreset }
    }
    func startControl(_ client: DSHClient, generation: Int) {
        controlTask?.cancel(); state = SessionControlState(); error = nil
        controlTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let frames = try await ControlAPI(client: client).follow()
                    for try await item in frames {
                        guard let self, !Task.isCancelled, self.generation == generation else { return }
                        self.state.apply(item); self.error = nil
                    }
                } catch {
                    guard let self, !Task.isCancelled, self.generation == generation else { return }
                    self.error = appErrorCode(error)
                }
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            }
        }
    }
    func changeGoal(_ operation: GoalOperation, goal: GoalState, objective: String? = nil) async throws {
        guard let id = context.currentSessionId else { throw DSHError("E_NO_SESSION") }
        try await api().changeGoal(operation, agentId: id, ref: goal,
            objective: objective?.trimmingCharacters(in: .whitespacesAndNewlines))
        // The control stream remains authoritative, including stale-revision errors.
    }
}

/// Shared values are readable through SessionContext; only this store file can write them.
@MainActor @Observable final class PermissionSessionState {
    fileprivate(set) var permissionPresets: [PermissionPreset] = []
    fileprivate(set) var enginePermissionDefault: String = ""
    fileprivate(set) var permissionPreset: String? = nil
}
