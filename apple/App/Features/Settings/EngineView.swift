// SPDX-License-Identifier: AGPL-3.0-or-later
// Local engine page in the Mist Glass style (原 Flutter 版 lib/ui/engine; reference:
// 原 Flutter 版 test/shell/goldens/engine_light.png).
import DSHRuntime
import SwiftUI

struct EngineView: View {
    @Environment(\.designTheme) private var theme
    @Environment(EngineModel.self) private var engine
    /// Pushed inside another navigation stack (Settings) instead of its own.
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }

    private var content: some View {
        @Bindable var engine = engine
        let phase = engine.status.phase
        return ZStack(alignment: .topLeading) {
            AppBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 56)
                    header.padding(.bottom, 22)
                    versions.padding(.bottom, 20)
                    actions.padding(.bottom, 24)
                    if let progress = engine.progress, phase == .installing {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(stepTitle(progress.step)).type(.bodyMedium).foregroundStyle(DS.inkMuted)
                            ProgressView(value: progress.fraction).tint(theme.accent)
                        }
                        .padding(16).glass(.card, radius: Radius.lg).padding(.bottom, 22)
                    }
                    if let code = engine.status.errorCode ?? engine.actionError {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Glyph(glyph: AppIcon.error, size: 16)
                            Text(errorText(code)).type(.bodyMedium)
                        }
                        .foregroundStyle(DS.danger)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.dangerContainer.opacity(0.7), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .padding(.bottom, 22)
                    }
                    if engine.safeModeOn { safeNotice.padding(.bottom, 22) }
                    SettingsGroup(header: "Startup") {
                        SettingsToggleRow(title: "Start when the app opens", isOn: $engine.autoStart)
                        SettingsToggleRow(title: "Safe mode automatically", subtitle: String(localized: "Turns on after repeated start failures"),
                                          isOn: Binding(get: { engine.status.autoSafe }, set: { engine.setAutoSafe($0) })).settingAnchor("engine-safe")
                        Button { engine.startSafe() } label: {
                            SettingsRow(title: "Start in safe mode", subtitle: String(localized: "Without plugins, to troubleshoot startup"))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canStart)
                    }
                    SettingsGroup(header: "Maintenance") {
                        if phase == .notInstalled || (phase == .error && engine.status.installedVersion == nil) {
                            Button { engine.install() } label: { SettingsRow(title: "Install runtime") }.buttonStyle(.plain)
                        }
                        Button { confirmReset = true } label: {
                            SettingsRow(title: "Reset runtime", subtitle: engine.status.installedVersion, titleColor: DS.danger) { EmptyView() }
                        }
                        .buttonStyle(.plain)
                        .disabled(engine.status.installedVersion == nil)
                    }
                    if engine.status.restartRequired {
                        Text("Close the app from the app switcher and open it again to finish.")
                            .type(.bodySmall).foregroundStyle(DS.warn).padding(.horizontal, 8).padding(.bottom, 16)
                    }
                    logCard
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, 40)
                .frame(maxWidth: Space.readingWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            GlassIconButton(glyph: embedded ? AppIcon.back : AppIcon.close, label: "Back") { dismiss() }
                .padding(.leading, 12).padding(.top, 4)
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("Reset the runtime?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset runtime", role: .destructive) { engine.reset() }
        } message: {
            Text("Chats and settings inside the engine are removed. The runtime is installed again from the app.")
        }
        .disabled(engine.busy)
    }

    private var canStart: Bool {
        let phase = engine.status.phase
        return (phase == .installed || (phase == .error && engine.status.installedVersion != nil)) && !engine.status.restartRequired
    }

    private var canStartNormally: Bool {
        let phase = engine.status.phase
        return (canStart || phase == .running || phase == .starting) && !engine.status.restartRequired
    }

    /// Without this, safe mode never ends: plain starts keep the current mode.
    private var safeNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Glyph(glyph: AppIcon.safeMode, size: 16)
                Text("Safe mode is on").font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(DS.warn)
            Text("Plugins and phone control stay off in safe mode, including after restarts. Start normally when you're done troubleshooting.")
                .type(.bodyMedium).foregroundStyle(DS.inkMuted)
            pill(DshGlyph.play, "Start normally", enabled: canStartNormally) { engine.startNormal() }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glass(.card, radius: Radius.lg)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Glyph(glyph: AppIcon.engine, size: 30).foregroundStyle(theme.accent)
                .frame(width: 62, height: 62)
                .overlay(Circle().strokeBorder(theme.accent, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 4) {
                Text("Local Engine").font(.system(size: 24, weight: .bold)).foregroundStyle(DS.ink)
                HStack(spacing: 6) {
                    Text(engine.status.phase.title)
                    if engine.status.phase == .running {
                        Text(verbatim: "·").foregroundStyle(DS.inkGhost)
                        Text(verbatim: "127.0.0.1:\(RuntimeEngine.port)")
                    }
                }
                .font(.system(size: 15)).foregroundStyle(DS.inkFaint)
            }
        }
        .padding(.leading, 4)
    }

    private var versions: some View {
        HStack(alignment: .top, spacing: 0) {
            stat(engine.status.dshVersion.map { "v" + $0 } ?? "—", "DSH")
            stat(engine.status.nodeVersion.map { "v" + $0 } ?? "—", "Node.js")
        }
        .padding(.leading, 8)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 20, weight: .semibold)).foregroundStyle(DS.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(verbatim: label).font(.system(size: 13)).foregroundStyle(DS.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        let phase = engine.status.phase
        let running = phase == .running || phase == .starting
        return HStack(spacing: 10) {
            pill(DshGlyph.play, "Start", enabled: canStart) { engine.start() }
            pill(AppIcon.stop, "Stop", enabled: running) { engine.stop() }
            pill(AppIcon.retry, "Restart", enabled: running && !engine.status.restartRequired) { engine.restart() }
        }
    }

    private func pill(_ glyph: DshGlyph, _ title: LocalizedStringKey, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Glyph(glyph: glyph, size: 18)
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(enabled ? DS.ink : DS.inkGhost)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(DS.surfaceHigh.opacity(enabled ? 0.9 : 0.45), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || engine.busy)
    }

    /// Dark terminal card with the recent engine log (already redacted).
    private var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Logs").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(argb: 0xFFE6E9F0))
                Text("\(engine.logs.count) lines").font(.system(size: 13)).foregroundStyle(Color(argb: 0xFF9A9EA9))
                Spacer()
                Button { UIPasteboard.general.string = engine.logs.map(\.line).joined(separator: "\n") } label: {
                    Glyph(glyph: AppIcon.copy, size: 18).foregroundStyle(Color(argb: 0xFFB6BBC5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Copy"))
            }
            if engine.logs.isEmpty {
                Text("No logs yet").font(Mono.font(13, scale: theme.readingScale)).foregroundStyle(Color(argb: 0xFF9A9EA9))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(engine.logs.suffix(80), id: \.seq) { entry in
                        Text(entry.line)
                            .font(Mono.font(12.5, scale: theme.readingScale))
                            .foregroundStyle(entry.stream == "stderr" ? Color(argb: 0xFFE69089)
                                             : entry.line.hasPrefix("[dsh-app]") ? Color(argb: 0xFF97B1F0) : Color(argb: 0xFFE6E9F0))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(argb: 0xFF12151C), in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private func stepTitle(_ step: String) -> LocalizedStringKey {
        switch step {
        case "verify": "Verifying package"
        case "extract": "Extracting"
        default: "Configuring"
        }
    }

    private func errorText(_ code: String) -> String {
        switch code {
        case "E_RESTART_REQUIRED": String(localized: "Close the app from the app switcher and open it again to finish.")
        case "EADDRINUSE": String(localized: "Port 3080 is in use by another app, such as an older DSH app. Close that app, then start the engine again.")
        case "ENOSPC": String(localized: "Not enough free storage to install the runtime.")
        case "ENOMEM": String(localized: "The engine ran out of memory.")
        case "E_START_TIMEOUT": String(localized: "The engine did not start in time.")
        default: String(localized: "Engine error: \(code)")
        }
    }
}

extension RuntimePhase {
    var title: LocalizedStringKey {
        switch self {
        case .notInstalled: "Not installed"
        case .installing: "Installing"
        case .installed: "Installed"
        case .starting: "Starting"
        case .running: "Running"
        case .stopping: "Stopping"
        case .error: "Error"
        }
    }
}
