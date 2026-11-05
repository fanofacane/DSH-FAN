// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/settings/{about_page,font_licenses}.dart.
import SwiftUI

struct AboutPage: View {
    @Environment(EngineModel.self) private var engine

    var body: some View {
        SettingsPage(title: "About DSH Fan") {
            SettingsGroup {
                InfoRow(label: "Version", value: version).settingAnchor("app-version")
                if let dsh = engine.status.dshVersion { InfoRow(label: "DSH", value: dsh) }
                if let node = engine.status.nodeVersion { InfoRow(label: "Node.js", value: node) }
                SettingsLink(title: "Open-source licenses") { OpenSourceLicensesPage() }
                    .settingAnchor("open-source-licenses")
            }
            SettingsGroup(header: "Open source") {
                Link(destination: URL(string: "https://github.com/fanofacane/dsh-fan")!) {
                    SettingsRow(title: "Source repository", subtitle: "github.com/fanofacane/dsh-fan") {
                        Glyph(glyph: .arrowSquareOut, size: 18).foregroundStyle(DS.inkFaint)
                    }
                }.buttonStyle(SettingsPressStyle())
                InfoRow(label: "License", value: "AGPL-3.0-or-later")
            }
            VStack(spacing: Space.sm) {
                BrandMark(size: 18).opacity(0.35)
                Text("DSH Fan is an independent iOS project informed by DSH Go and iSH.")
                    .settingsType(.bodySmall).foregroundStyle(DS.inkFaint)
                    .multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.horizontal, Space.sm)
        }
    }

    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

struct OpenSourceLicensesPage: View {
    private var files: [URL] {
        guard let directory = Bundle.main.url(forResource: "Licenses", withExtension: nil) else { return [] }
        return (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                             options: .skipsHiddenFiles))?.sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
    }

    var body: some View {
        SettingsPage(title: "Open-source licenses") {
            SettingsGroup {
                ForEach(files, id: \.self) { file in
                    NavigationLink {
                        LicenseTextPage(file: file)
                    } label: {
                        SettingsRow(title: "", verbatim: file.lastPathComponent) { SettingsChevron() }
                    }.buttonStyle(SettingsPressStyle())
                }
            }
        }
    }
}

private struct LicenseTextPage: View {
    let file: URL
    @State private var license: String?
    var body: some View {
        SettingsPage(title: "License", subtitle: LocalizedStringKey(file.lastPathComponent)) {
            if let license {
                Text(verbatim: license).settingsType(.bodySmall).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(Space.lg).glass(.card)
            } else {
                Text("Couldn’t read this license.").settingsType(.bodyMedium).foregroundStyle(DS.inkFaint)
            }
        }.task { license = try? String(contentsOf: file, encoding: .utf8) }
    }
}
