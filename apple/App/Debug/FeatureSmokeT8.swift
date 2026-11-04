// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation
import UIKit
import QuickLook

extension AppSession {
    func smokeT8(_ result: FeatureSmokeContext) async throws {
        guard self.transcript.canSend else { throw DSHError(self.connection.keyConfigured ? "E_CANNOT_SEND" : "E_NEEDS_USER_KEY") }
        let name = "ios-files-" + UUID().uuidString.lowercased().prefix(8)
        let directory = try await self.connection.workspaceAPI.createDirectory(path: "/tmp", name: name)
        self.workspace.chooseDirectory(directory)
        await self.transcript.send("请严格使用 write 工具在当前工作目录创建 sample.txt，内容为 alpha 和 beta 两行；然后使用 edit 工具把 beta 改为 gamma；再用 write 工具创建 sample.html，内容为 <html><body><h1>DSH preview</h1></body></html>。不要使用 bash，不要执行其他操作，最后只回复完成。")
        try await smokeWait(seconds: 180) { !self.transcript.busy && self.transcript.items.contains { $0.role == .assistant && $0.state == .done } }
        guard let id = self.transcript.currentSessionId else { throw DSHError("E_NO_SESSION") }
        let listing = try await self.connection.filesAPI.list(workspaceFileScopeId: id, path: ".")
        let entries = listing.entries
        guard entries.contains(where: { $0.name == "sample.html" }) else { throw DSHError("E_FILE_LIST") }
        let page = try await self.connection.filesAPI.read(workspaceFileScopeId: id, path: "sample.txt", offset: 1, limit: 50)
        guard page?.contains("gamma") == true else { throw DSHError("E_FILE_TEXT") }
        let bytes = try await self.workspace.fileBytes(sessionId: id, path: "sample.txt")
        guard String(data: bytes, encoding: .utf8)?.contains("gamma") == true else { throw DSHError("E_FILE_BINARY") }
        let changes = self.transcript.items.flatMap(\.tools).flatMap(\.textChanges)
        guard changes.contains(where: { $0.before?.contains("beta") == true && $0.after.contains("gamma") }) else { throw DSHError("E_CHANGE_EXCERPT") }
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 240, height: 120)).pdfData { context in
            context.beginPage(); ("DSH preview" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-smoke.pdf")
        try pdf.write(to: url)
        result.set("nativePDFPreview", QLPreviewController.canPreview(url as NSURL))
        try FileManager.default.removeItem(at: url)
        result.set("fileListReadBytes", true); result.set("realModel", true); result.set("reportedDiff", true)
    }
}
#endif
