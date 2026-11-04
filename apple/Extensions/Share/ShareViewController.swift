// SPDX-License-Identifier: AGPL-3.0-or-later
// Share extension: saves shared text, links and images to the App Group inbox.
// The app moves them into a new chat's composer the next time it opens.
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Task { await model.collect(items) }
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum State { case collecting, saved(text: Bool, images: Int), failed }
    @Published var state = State.collecting

    func collect(_ items: [NSExtensionItem]) async {
        var texts: [String] = []
        var images: [Data] = []
        for item in items {
            if let text = item.attributedContentText?.string, !text.isEmpty { texts.append(text) }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier), images.count < 4,
                   let data = await Self.loadImage(provider) {
                    images.append(data)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                          let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    texts.append(url.absoluteString)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    texts.append(text)
                }
            }
        }
        var seen = Set<String>()
        let text = texts.filter { seen.insert($0).inserted }.joined(separator: "\n")
        guard let directory = SharedInbox.directory, !(text.isEmpty && images.isEmpty) else { state = .failed; return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let id = UUID().uuidString
            var names: [String] = []
            for (index, data) in images.enumerated() {
                let name = "\(id)-\(index).jpg"
                try data.write(to: directory.appendingPathComponent(name), options: .atomic)
                names.append(name)
            }
            let item = SharedInboxItem(text: String(text.prefix(16384)), images: names, created: Date())
            try JSONEncoder().encode(item).write(to: directory.appendingPathComponent("\(id).json"), options: .atomic)
            state = .saved(text: !text.isEmpty, images: images.count)
        } catch {
            state = .failed
        }
    }

    /// JPEG, longest side ≤ 2048 px, like the app's photo picker.
    private static func loadImage(_ provider: NSItemProvider) async -> Data? {
        let raw = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier)
        let image: UIImage?
        switch raw {
        case let url as URL: image = UIImage(contentsOfFile: url.path)
        case let data as Data: image = UIImage(data: data)
        case let value as UIImage: image = value
        default: image = nil
        }
        guard let image else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 2048 ? 2048 / longest : 1
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.85)
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel
    let done: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            switch model.state {
            case .collecting:
                ProgressView()
            case .saved(let text, let images):
                Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(DS.success)
                Text("Saved for DSH").font(.system(size: 18, weight: .semibold)).foregroundStyle(DS.ink)
                Text(summary(text: text, images: images)).font(.system(size: 14)).foregroundStyle(DS.inkMuted)
                    .multilineTextAlignment(.center)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(DS.warn)
                Text("Nothing to share").font(.system(size: 18, weight: .semibold)).foregroundStyle(DS.ink)
            }
            Button(action: done) {
                Text("Done").font(.system(size: 16, weight: .semibold)).foregroundStyle(DS.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(DesignTheme().accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(DS.backdropTop, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.25))
    }

    private func summary(text: Bool, images: Int) -> String {
        let what = [text ? String(localized: "text") : nil, images > 0 ? String(localized: "\(images) image(s)") : nil]
            .compactMap { $0 }.joined(separator: " + ")
        return String(localized: "Open DSH to continue with the \(what) in a new chat.")
    }
}
