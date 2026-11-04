// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation

extension AppSession {
    func smokeT7(_ result: FeatureSmokeContext) async throws {
        for scratch in self.workspace.state.items where scratch.path.hasPrefix("/tmp/ios-workspace-") && scratch.title == "iOS Workspace Smoke" {
            try await self.workspace.removeWorkspace(scratch.id)
        }
        let fixtureName = "ios-workspace-" + UUID().uuidString.lowercased().prefix(8)
        let directory = try await self.connection.workspaceAPI.createDirectory(path: "/tmp", name: fixtureName)
        let listing = try await self.connection.workspaceAPI.listDirectory(path: directory)
        guard listing.path == directory else { throw DSHError("E_DIRECTORY_LIST") }
        let record = try await self.workspace.registerWorkspace(directory)
        try await smokeWait { self.workspace.state.items.contains { $0.id == record.id } }
        try await self.workspace.renameWorkspace(record.id, title: "iOS Workspace Smoke")
        try await smokeWait { self.workspace.state.items.contains { $0.id == record.id && $0.title == "iOS Workspace Smoke" } }
        self.workspace.chooseWorkspace(record.id)
        let session = try await self.transcript.ensureSession()
        await self.sessionList.refreshSessions()
        try await smokeWait { self.workspace.state.items.contains { $0.id == record.id && $0.sessionIds.contains(session) } }
        guard self.sessionList.sessions.contains(where: { $0.id == session && $0.cwd == directory }) else { throw DSHError("E_WORKSPACE_SESSION") }
        try await self.workspace.removeWorkspace(record.id)
        try await smokeWait { !self.workspace.state.items.contains { $0.id == record.id } }
        let kept = try await self.connection.workspaceAPI.listDirectory(path: directory)
        guard kept.path == directory else { throw DSHError("E_WORKSPACE_REMOVAL_DELETED_DIRECTORY") }
        self.transcript.newChat()
        result.set("directoryBrowse", true); result.set("createRenameRemove", true)
        result.set("sessionWorkspaceAndCwd", true); result.set("directoryKept", true)
    }
}
#endif
