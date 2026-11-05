// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/index/spot_anchor.dart.
import SwiftUI

private struct SettingsTargetKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var settingsTarget: String? {
        get { self[SettingsTargetKey.self] }
        set { self[SettingsTargetKey.self] = newValue }
    }
}

struct SettingsAnchorReady: PreferenceKey {
    static let defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) { value = nextValue() ?? value }
}

extension View {
    func settingAnchor(_ id: String) -> some View { modifier(SettingsSpotAnchor(id: id)) }
}

private struct SettingsSpotAnchor: ViewModifier {
    let id: String
    @Environment(\.settingsTarget) private var target
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.designTheme) private var theme
    @State private var highlight: Double = 0

    func body(content: Content) -> some View {
        content
            .background(theme.accentContainer.opacity(highlight))
            .id(id)
            .accessibilityIdentifier(id)
            .preference(key: SettingsAnchorReady.self, value: target == id ? id : nil)
            .task(id: target == id) {
                guard target == id else { highlight = 0; return }
                do {
                    try await Task.sleep(for: .milliseconds(240))
                    if reduceMotion {
                        highlight = 0.5
                        try await Task.sleep(for: .seconds(1))
                        highlight = 0
                    } else {
                        for opacity in [0.5, 0, 0.5, 0] {
                            withAnimation(.easeInOut(duration: 0.4)) { highlight = opacity }
                            try await Task.sleep(for: .milliseconds(400))
                        }
                    }
                } catch { highlight = 0 }
            }
    }
}
