// SPDX-License-Identifier: AGPL-3.0-or-later
// Widget extension: "Ask DSH" widgets (home + lock screen), a Control Center
// control (iOS 18+), and the Live Activity for a running turn.
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct DSHWidgetBundle: WidgetBundle {
    var body: some Widget {
        AskWidget()
        TurnLiveActivity()
        if #available(iOS 18.0, *) { AskControl() }
    }
}

// MARK: Ask DSH widget

struct AskEntry: TimelineEntry { let date: Date }

struct AskProvider: TimelineProvider {
    func placeholder(in context: Context) -> AskEntry { AskEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (AskEntry) -> Void) { completion(AskEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AskEntry>) -> Void) {
        completion(Timeline(entries: [AskEntry(date: .now)], policy: .never))
    }
}

struct AskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AskDSH", provider: AskProvider()) { _ in AskWidgetView() }
            .configurationDisplayName("Ask DSH")
            .description("Start a new chat with the agent on this iPhone.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct AskWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack { AccessoryWidgetBackground(); Image(systemName: "sparkles").font(.title2) }
            case .accessoryRectangular:
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    VStack(alignment: .leading) {
                        Text(verbatim: "DSH").font(.headline)
                        Text("Ask anything").font(.caption)
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").foregroundStyle(DesignTheme().accent)
                        Text(verbatim: "DSH").font(.system(size: 15, weight: .semibold)).tracking(0.6).foregroundStyle(DS.ink)
                    }
                    Spacer(minLength: 0)
                    Text("Ask anything").font(.system(size: family == .systemMedium ? 22 : 18, weight: .light)).foregroundStyle(DS.ink)
                    HStack {
                        Text("Message DSH…").font(.system(size: 13)).foregroundStyle(DS.inkFaint).lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.onAccent)
                            .frame(width: 26, height: 26).background(DesignTheme().accent, in: Circle())
                    }
                    .padding(.leading, 12).padding(.trailing, 4).frame(height: 34)
                    .background(DS.surfaceLow.opacity(0.9), in: Capsule())
                }
            }
        }
        .widgetURL(DSHLink.ask)
        .containerBackground(for: .widget) {
            LinearGradient(colors: [DS.backdropTop, DS.backdropBottom], startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: Control Center (iOS 18)

@available(iOS 18.0, *)
struct AskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "AskDSHControl") {
            ControlWidgetButton(action: OpenAskIntent()) {
                Label("Ask DSH", systemImage: "sparkles")
            }
        }
        .displayName("Ask DSH")
    }
}

/// Opens the app on a new chat.
@available(iOS 18.0, *)
struct OpenAskIntent: AppIntent {
    static let title: LocalizedStringResource = "Open DSH"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult & OpensIntent { .result(opensIntent: OpenURLIntent(DSHLink.ask)) }
}

// MARK: Live Activity

struct TurnLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DSHActivityAttributes.self) { context in
            LockScreenTurnView(context: context)
                .activityBackgroundTint(DS.backdropTop)
                .widgetURL(URL(string: "dshapp://open"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: phaseIcon(context.state.phase)).foregroundStyle(phaseTint(context.state.phase)).font(.title3)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.title).font(.headline).lineLimit(1)
                        Text(phaseTitle(context.state.phase)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.detail.isEmpty {
                        Text(context.state.detail).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: phaseIcon(context.state.phase)).foregroundStyle(phaseTint(context.state.phase))
            } compactTrailing: {
                Text(phaseShort(context.state.phase)).font(.caption2).foregroundStyle(phaseTint(context.state.phase))
            } minimal: {
                Image(systemName: phaseIcon(context.state.phase)).foregroundStyle(phaseTint(context.state.phase))
            }
            .widgetURL(URL(string: "dshapp://open"))
        }
    }
}

struct LockScreenTurnView: View {
    let context: ActivityViewContext<DSHActivityAttributes>
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: phaseIcon(context.state.phase))
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(phaseTint(context.state.phase))
                .frame(width: 44, height: 44).background(DesignTheme().accentContainer, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(DS.ink).lineLimit(1)
                Text(phaseTitle(context.state.phase)).font(.system(size: 14)).foregroundStyle(DS.inkMuted)
                if !context.state.detail.isEmpty {
                    Text(context.state.detail).font(.system(size: 12, design: .monospaced)).foregroundStyle(DS.inkFaint).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: "DSH").font(.system(size: 12, weight: .semibold)).tracking(0.6).foregroundStyle(DS.inkFaint)
        }
        .padding(16)
    }
}

private func phaseIcon(_ phase: DSHActivityAttributes.ContentState.Phase) -> String {
    switch phase {
    case .thinking: "brain"
    case .working: "terminal"
    case .waiting: "hand.raised.fill"
    case .replying: "text.bubble"
    case .done: "checkmark.circle.fill"
    case .failed: "exclamationmark.triangle.fill"
    }
}

private func phaseTint(_ phase: DSHActivityAttributes.ContentState.Phase) -> Color {
    switch phase {
    case .waiting: DS.warn
    case .done: DS.success
    case .failed: DS.danger
    default: DesignTheme().accent
    }
}

private func phaseTitle(_ phase: DSHActivityAttributes.ContentState.Phase) -> LocalizedStringKey {
    switch phase {
    case .thinking: "Thinking…"
    case .working: "Running tools…"
    case .waiting: "Waiting for you"
    case .replying: "Replying…"
    case .done: "Done"
    case .failed: "Failed"
    }
}

private func phaseShort(_ phase: DSHActivityAttributes.ContentState.Phase) -> LocalizedStringKey {
    switch phase {
    case .thinking: "Think"
    case .working: "Run"
    case .waiting: "Wait"
    case .replying: "Reply"
    case .done: "Done"
    case .failed: "Failed"
    }
}
