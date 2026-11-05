// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/ui/engine/{engine_screen,log_view}.dart and app/lib/ui/safe_mode/safe_mode_settings.dart.
import DSHRuntime
import SwiftUI

struct EngineView: View {
    @Environment(\.designTheme) private var theme
    @Environment(EngineModel.self) private var engine
    /// Pushed inside another navigation stack (Settings) instead of its own.
    var embedded = false
    @State private var confirmReset = false
    @State private var reviewLogs = false

    private var status: RuntimeStatus {
        #if DEBUG
        if let fixture = DebugEngineSettings.status { return fixture }
        #endif
        return engine.status
    }
    private var hasFixture: Bool {
        #if DEBUG
        DebugEngineSettings.status != nil
        #else
        false
        #endif
    }
    private var safeMode: Bool { status.safeState == "on" }

    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }

    private var content: some View {
        @Bindable var engine = engine
        let phase = status.phase
        return SettingsPage(title: "Local engine", showsTitle: false) {
            PageHero(title: Text("Local engine"),
                     subtitle: Text(verbatim: engineSubtitle),
                     stats: [(status.dshVersion.map { "v" + $0 } ?? "—", "DSH"),
                             (status.nodeVersion.map { "v" + $0 } ?? "—", "Node.js")]) {
                SettingsIcon(glyph: AppIcon.engine, tone: .identity(6), size: 62)
            } trailing: {
                StatusDot(tone: safeMode ? .warn : phase == .running ? .ok : phase == .error ? .error : .idle)
            }
            actions.padding(.bottom, 24)
            if let progress = engine.progress, phase == .installing {
                VStack(alignment: .leading, spacing: 8) {
                    Text(stepTitle(progress.step)).type(.bodyMedium).foregroundStyle(DS.inkMuted)
                    ProgressView(value: progress.fraction).tint(theme.accent)
                }
                .padding(16).glass(.card, radius: Radius.lg).padding(.bottom, 22)
            }
            if let code = status.errorCode ?? engine.actionError {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Glyph(glyph: AppIcon.error, size: 16)
                    Text(errorText(code)).type(.bodyMedium)
                }
                .foregroundStyle(DS.danger)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.dangerContainer.opacity(0.7), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .padding(.bottom, 22)
            }
            if safeMode { safeNotice.padding(.bottom, 22) }
            SettingsGroup(header: "Startup") {
                SettingsToggleRow(title: "Start when the app opens", isOn: $engine.autoStart)
                SafeModeSettingsRows(status: status)
            }
            SettingsGroup(header: "Maintenance") {
                if phase == .notInstalled || (phase == .error && status.installedVersion == nil) {
                    Button { engine.install() } label: { SettingsRow(title: "Install runtime") }.buttonStyle(.plain)
                }
                Button { confirmReset = true } label: {
                    SettingsRow(title: "Reset runtime", subtitle: status.installedVersion, titleColor: DS.danger) { EmptyView() }
                }
                .buttonStyle(.plain)
                .disabled(status.installedVersion == nil)
            }
            if status.restartRequired {
                Text("Close the app from the app switcher and open it again to finish.")
                    .type(.bodySmall).foregroundStyle(DS.warn).padding(.horizontal, 8).padding(.bottom, 16)
            }
            logCard
        }
        .confirmationDialog("Reset the runtime?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset runtime", role: .destructive) { engine.reset() }
        } message: {
            Text("Chats and settings inside the engine are removed. The runtime is installed again from the app.")
        }
        .disabled(engine.busy || hasFixture)
        .sheet(isPresented: $reviewLogs) { DiagnosticReviewSheet(snapshot: engine.logs.map { RuntimeLogs.redact($0.line) }.joined(separator: "\n")) }
    }

    private var engineSubtitle: String {
        let title = String(localized: status.phase.titleResource)
        return status.phase == .running ? title + " · 127.0.0.1:\(RuntimeEngine.port)" : title
    }

    private var canStart: Bool {
        let phase = status.phase
        return (phase == .installed || (phase == .error && status.installedVersion != nil)) && !status.restartRequired
    }

    private var canStartNormally: Bool {
        let phase = status.phase
        return (canStart || phase == .running || phase == .starting) && !status.restartRequired
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

    private var actions: some View {
        let phase = status.phase
        let running = phase == .running || phase == .starting
        return HStack(spacing: 10) {
            pill(DshGlyph.play, "Start", enabled: canStart) { engine.start() }
            pill(AppIcon.stop, "Stop", enabled: running) { engine.stop() }
            pill(AppIcon.retry, "Restart", enabled: running && !status.restartRequired) { engine.restart() }
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
                Button { reviewLogs = true } label: {
                    Glyph(glyph: AppIcon.share, size: 18).foregroundStyle(Color(argb: 0xFFB6BBC5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Export diagnostics"))
            }
            if engine.logs.isEmpty {
                Text("No logs yet").font(Mono.font(13, scale: theme.readingScale)).foregroundStyle(Color(argb: 0xFF9A9EA9))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(engine.logs.suffix(80), id: \.seq) { entry in
                        Text(RuntimeLogs.redact(entry.line))
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

struct SafeModeSettingsRows: View {
    @Environment(EngineModel.self) private var engine
    let status: RuntimeStatus

    private var isSafe: Bool { status.safeState == "on" }
    private var canRun: Bool {
        guard !status.restartRequired, status.installedVersion != nil else { return false }
        return status.phase == .installed || status.phase == .error || (isSafe && status.phase == .running)
    }

    var body: some View {
        SettingsToggleRow(glyph: AppIcon.autoSwitch, title: "Safe mode automatically",
                          subtitle: String(localized: "Turns on after repeated start failures"),
                          isOn: Binding(get: { status.autoSafe }, set: { engine.setAutoSafe($0) }))
            .settingAnchor("engine-safe")
        Button {
            if isSafe { engine.startNormal() } else { engine.startSafe() }
        } label: {
            SettingsRow(glyph: AppIcon.safeMode, title: isSafe ? "Start normally" : "Start in safe mode",
                        subtitle: isSafe ? String(localized: "Turn safe mode off and start the engine.")
                                         : String(localized: "Without plugins, to troubleshoot startup"))
        }
        .buttonStyle(SettingsPressStyle())
        .disabled(!canRun)
    }
}
