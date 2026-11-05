// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/widgets/live_clock.dart.
import SwiftUI

private struct RunClockKey: EnvironmentKey { static let defaultValue: Date? = nil }
extension EnvironmentValues {
    var runClockOverride: Date? {
        get { self[RunClockKey.self] }
        set { self[RunClockKey.self] = newValue }
    }
}

/// Keep one-second updates inside the clock's own subtree.
struct LiveRunClock<Content: View>: View {
    let since: Date?
    var skew: TimeInterval = 0
    @ViewBuilder let content: (Date) -> Content
    @Environment(\.runClockOverride) private var fixedNow
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if let fixedNow {
            content(fixedNow.addingTimeInterval(-skew))
        } else if let since, scenePhase == .active {
            TimelineView(.periodic(from: since.addingTimeInterval(skew), by: 1)) { context in
                content(context.date.addingTimeInterval(-skew))
            }
        } else {
            content(.now.addingTimeInterval(-skew))
        }
    }
}
