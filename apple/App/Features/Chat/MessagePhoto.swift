// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHClient
import Photos
import SwiftUI

@MainActor enum PhotoWriter {
    static func save(_ image: UIImage, library: PHPhotoLibrary) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw DSHError("E_PHOTO_ACCESS") }
        guard let data = image.pngData() else { throw DSHError("E_IMAGE_FORMAT") }
        do {
            try await library.performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
        } catch { throw DSHError("E_PHOTO_SAVE_" + String((error as NSError).code)) }
    }
}

struct MessagePhoto: View {
    enum Source: Hashable { case attachment(MessageImageReference, String), web(URL), workspace(String, String) }
    @Environment(AppSession.self) private var chat
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.photoLibrary) private var photoLibrary
    let source: Source
    @State private var image: UIImage?
    @State private var error: String?
    @State private var saved = false
    @State private var saving = false
    @State private var allowedSource: Source?
    private var mayLoad: Bool {
        if case .web = source { return preferences.remoteImages || allowedSource == source }
        return true
    }
    var body: some View {
        Group {
            if !mayLoad {
                Button { allowedSource = source } label: { Label("Load external image", systemImage: "photo") }.padding(16)
            } else if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .contextMenu {
                        Button { Task { await save(image) } } label: { Label("Save image", systemImage: "square.and.arrow.down") }
                            .disabled(saving)
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("Image", image: Image(uiImage: image))) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
            } else if let error {
                Text("Request failed: \(error)").type(.bodySmall).foregroundStyle(DS.danger)
            } else { ProgressView().frame(height: 64) }
        }
        .task(id: "\(source.hashValue)-\(mayLoad)") {
            image = nil; error = nil
            guard mayLoad else { return }
            do {
                let data: Data
                switch source {
                case .attachment(let reference, let session): data = try await chat.transcript.imageData(reference, sessionId: session)
                case .workspace(let path, let session): data = try await chat.workspace.fileBytes(sessionId: session, path: path)
                case .web(let url):
                    // No engine cookie or credential is ever sent to image hosts.
                    let session = URLSession(configuration: .ephemeral)
                    defer { session.invalidateAndCancel() }
                    let (bytes, response) = try await session.data(from: url)
                    guard (response as? HTTPURLResponse)?.statusCode == 200, bytes.count <= 30 * 1024 * 1024 else { throw DSHError("E_IMAGE_UNAVAILABLE") }
                    data = bytes
                }
                try Task.checkCancellation()
                guard let decoded = UIImage(data: data) else { throw DSHError("E_IMAGE_FORMAT") }
                image = decoded
            } catch { if !Task.isCancelled { self.error = (error as? DSHError)?.code ?? "E_IMAGE_UNAVAILABLE" } }
        }
        .alert("Image saved", isPresented: $saved) { Button("OK") {} }
        .alert("Save image", isPresented: Binding(get: { image != nil && error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            if error == "E_PHOTO_ACCESS" { Text("Allow DSH to add photos in Settings.") }
            else { Text("Request failed: \(error ?? "E_PHOTO_SAVE")") }
        }
    }
    private func save(_ image: UIImage) async {
        saving = true; defer { saving = false }
        do {
            guard let photoLibrary else { throw DSHError("E_PHOTO_SAVE") }
            try await PhotoWriter.save(image, library: photoLibrary); saved = true
        }
        catch { self.error = (error as? DSHError)?.code ?? "E_PHOTO_SAVE" }
    }
}
