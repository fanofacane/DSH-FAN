// SPDX-License-Identifier: AGPL-3.0-or-later
// DEBUG golden harness. DSH Go: app/test/shell/golden_harness.dart.
#if DEBUG
import SwiftUI

/// Hosts the real page at the golden's logical viewport, independently of the
/// device's safe area. The fitted viewport is also displayed on the simulator.
struct DebugPageCapture: UIViewControllerRepresentable {
    let name: String
    let size: CGSize
    let scheme: ColorScheme
    let content: AnyView

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller(name: name, size: size, content: content)
        controller.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.host.rootView = content
    }

    final class Controller: UIViewController {
        let host: UIHostingController<AnyView>
        private let name: String
        private let size: CGSize
        private var captured = false

        init(name: String, size: CGSize, content: AnyView) {
            host = UIHostingController(rootView: content)
            self.name = name
            self.size = size
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

        override func viewDidLoad() {
            super.viewDidLoad()
            host.safeAreaRegions = []
            host.view.backgroundColor = .clear
            addChild(host)
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            host.view.bounds = CGRect(origin: .zero, size: size)
            host.view.center = CGPoint(x: view.bounds.midX, y: size.height / 2)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !captured else { return }
            captured = true
            Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(700))
                    try self?.capture()
                } catch {
                    // Failed captures leave no ready marker and time out in the caller.
                    NSLog("DSH debug page capture failed: %@", String(describing: error))
                }
            }
        }

        private func capture() throws {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            format.opaque = true
            let rendered = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                host.view.layer.render(in: renderer.cgContext)
            }
            guard let data = rendered.pngData() else { throw CocoaError(.fileWriteUnknown) }
            let documents = URL.documentsDirectory
            try data.write(to: documents.appendingPathComponent("screen-full.png"), options: .atomic)
            try Data(name.utf8).write(to: documents.appendingPathComponent("screen-ready.txt"), options: .atomic)
        }
    }
}
#endif
