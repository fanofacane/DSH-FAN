// SPDX-License-Identifier: AGPL-3.0-or-later
// First launch in the Mist Glass style (原 Flutter 版 lib/ui/onboarding; references:
// 原 Flutter 版 test/shell/goldens/welcome_light.png, setup_40_light.png).
import DSHRuntime
import SwiftUI

/// First launch: welcome → prepare the local engine → API key.
struct OnboardingView: View {
    @Environment(\.designTheme) private var theme
    @Environment(EngineModel.self) private var engine
    @Environment(AppSession.self) private var chat
    let onFinish: () -> Void
    @State private var started = false

    var body: some View {
        ZStack {
            AppBackdrop()
            if !started {
                welcome.transition(.opacity)
            } else if engine.status.phase != .running || chat.connection.state != .ready {
                SetupProgressView(step: 0)
            } else {
                VStack(spacing: 0) {
                    StepBar(step: 1).padding(.top, 24)
                    ScrollView { KeySetupCard(onSaved: onFinish).padding(Space.gutter).padding(.top, 40) }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: started)
        .onChange(of: chat.connection.models.isEmpty) { _, empty in if !empty && started { onFinish() } }
        .onChange(of: chat.connection.state) { _, state in
            // An existing install whose engine already holds a key skips the key step.
            if state == .ready && !chat.connection.models.isEmpty && started { onFinish() }
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(RadialGradient(colors: [theme.accent.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 130))
                    .frame(width: 260, height: 260)
                BrandMark(size: 92)
            }
            Text(verbatim: "DSH FAN").font(.system(size: 18, weight: .semibold)).tracking(5).foregroundStyle(DS.inkFaint)
                .padding(.top, 6)
            Text("Put a DeepSeek agent\nin your pocket")
                .font(.system(size: 34, weight: .light)).foregroundStyle(DS.ink)
                .multilineTextAlignment(.center).lineSpacing(6)
                .padding(.top, 14)
            Text("The engine runs on this iPhone. Only model requests leave it.")
                .type(.bodyMedium).foregroundStyle(DS.inkFaint).multilineTextAlignment(.center)
                .padding(.top, 14).padding(.horizontal, 32)
            Spacer()
            Button {
                started = true
                engine.prepareOnLaunch(force: true)
            } label: {
                Text("Get started").font(.system(size: 17, weight: .semibold)).foregroundStyle(DS.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            Text("Anytime, anywhere. Just go!").type(.bodySmall).foregroundStyle(DS.inkFaint).padding(.top, 18).padding(.bottom, 24)
        }
    }
}

/// Two-segment progress bar at the top of the setup flow.
struct StepBar: View {
    @Environment(\.designTheme) private var theme
    let step: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<2) { index in
                Capsule().fill(index <= step ? theme.accent : DS.rule).frame(width: 58, height: 4)
            }
        }
    }
}

/// Installing / starting the engine: ring progress (setup_40 golden).
struct SetupProgressView: View {
    @Environment(EngineModel.self) private var engine
    var step: Int? = nil
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 0) {
            if let step { StepBar(step: step).padding(.top, 24) }
            Spacer()
            ProgressRing(fraction: fraction)
                .frame(width: 168, height: 168)
            Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(DS.ink).padding(.top, 44)
            Text(subtitle).type(.body).foregroundStyle(DS.inkMuted).multilineTextAlignment(.center)
                .padding(.top, 6).padding(.horizontal, 32)
            if let detail { Text(detail).font(.system(size: 14)).foregroundStyle(DS.inkFaint).padding(.top, 10).monospacedDigit() }
            Spacer()
            if engine.status.phase == .error || engine.actionError != nil || engine.status.restartRequired {
                MistButton(title: "Engine details", kind: .secondary) { showDetails = true }
                    .padding(.horizontal, 48).padding(.bottom, 16)
            }
            HStack(spacing: 6) {
                Glyph(glyph: AppIcon.lock, size: 16)
                Text("Everything stays on this device")
            }
            .font(.system(size: 14)).foregroundStyle(DS.inkFaint)
            Button("View logs") { showDetails = true }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.inkMuted)
                .padding(.top, 18).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showDetails) { EngineView() }
    }

    /// nil = indeterminate (starting).
    private var fraction: Double? {
        guard engine.status.phase == .installing, let progress = engine.progress else { return nil }
        switch progress.step {
        case "verify": return 0.3 * progress.fraction
        case "extract": return 0.3 + 0.65 * progress.fraction
        default: return 0.95 + 0.05 * progress.fraction
        }
    }

    private var title: LocalizedStringKey {
        if engine.status.restartRequired { return "Restart needed" }
        switch engine.status.phase {
        case .error: return "The engine could not start"
        case .installing, .notInstalled: return "Preparing the runtime"
        default: return "Starting the engine"
        }
    }

    private var subtitle: LocalizedStringKey {
        if engine.status.restartRequired { return "Close the app from the app switcher and open it again to finish." }
        switch engine.status.phase {
        case .error: return "Open the details to retry."
        case .installing, .notInstalled: return "The first setup takes a minute or two"
        default: return "This usually takes under a minute."
        }
    }

    private var detail: String? {
        guard engine.status.phase == .installing, let progress = engine.progress, progress.step == "verify", progress.total > 0 else { return nil }
        return "\(progress.done / 1_048_576) / \(progress.total / 1_048_576) MB"
    }
}

/// Thin ring with a large light percentage; spins when indeterminate.
struct ProgressRing: View {
    @Environment(\.designTheme) private var theme
    let fraction: Double?
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [theme.accent.opacity(0.10), .clear], center: .center, startRadius: 0, endRadius: 84))
            Circle().stroke(DS.rule, lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction ?? 0.28)
                .stroke(LinearGradient(colors: [theme.accent.opacity(0.45), theme.accent], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90 + (fraction == nil && spin ? 360 : 0)))
                .animation(fraction == nil ? .linear(duration: 1.2).repeatForever(autoreverses: false) : .easeOut(duration: 0.3),
                           value: fraction == nil ? (spin ? 1 : 0) : fraction ?? 0)
            if let fraction {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int((fraction * 100).rounded()))").font(.system(size: 48, weight: .light)).monospacedDigit()
                    Text(verbatim: "%").font(.system(size: 18, weight: .medium)).foregroundStyle(DS.inkMuted)
                }
                .foregroundStyle(DS.ink)
            } else {
                WhaleTail(height: 34).opacity(0.5)
            }
        }
        .onAppear { spin = true }
    }
}

/// Returning launches: the same ring while the engine starts.
struct EnginePreparingView: View {
    var body: some View {
        ZStack {
            AppBackdrop()
            SetupProgressView()
        }
    }
}
