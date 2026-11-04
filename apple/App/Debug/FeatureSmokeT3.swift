// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation
import UIKit

extension AppSession {
    func smokeT3(_ result: FeatureSmokeContext) async throws {
        let dependencies = result.dependencies
        self.transcript.newChat()
        let fixture = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        guard let bytes = fixture.pngData() else { throw DSHError("E_IMAGE_FIXTURE") }
        await self.transcript.send("只回复收到。", images: [PromptImage(mediaType: "image/png", data: bytes, name: "smoke.png")])
        try await smokeWait(seconds: 120) { !self.transcript.busy && self.transcript.items.contains { !$0.images.isEmpty } }
        guard let reference = self.transcript.items.first(where: { !$0.images.isEmpty })?.images.first, let id = self.transcript.currentSessionId,
              let decoded = UIImage(data: try await self.transcript.imageData(reference, sessionId: id)) else { throw DSHError("E_ATTACHMENT_ROUNDTRIP") }
        result.set("attachmentRoundTrip", true); result.set("realModelRequest", true); result.save()
        guard let library = dependencies.photoLibrary else { throw DSHError("E_PHOTO_SAVE") }
        try await PhotoWriter.save(decoded, library: library)
        result.set("savedToSimulatorPhotos", true)
        self.transcript.quote("first\nsecond")
        result.set("quote", self.transcript.composerInsertion == "> first\n> second\n\n")
    }
}
#endif
