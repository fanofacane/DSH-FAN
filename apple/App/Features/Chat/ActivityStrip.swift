// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/widgets/{activity_strip,whale_tail}.dart.
import DSHClient
import SwiftUI

struct ActivityStrip: View {
    let activity: RunActivity
    var skew: TimeInterval = 0
    var rate: RunTokenRate = RunTokenRate()
    var progress: (done: Int, total: Int)?
    var previewLevel: Int?
    var open: (() -> Void)?
    @State private var showsStats = false
    @State private var presses = 0

    var body: some View {
        HStack(spacing: Space.sm) {
            ActivityWhale(activity: activity, rate: rate, previewLevel: previewLevel)
            LiveRunClock(since: activity.turnStart ?? activity.since, skew: skew) { now in
                HStack(spacing: Space.sm) {
                    titleAndDetail(now)
                    Spacer(minLength: 0)
                    clock(now)
                }
            }
            if let progress, progress.total > 0 {
                Rectangle().fill(DS.rule).frame(width: 1, height: 14)
                Text(verbatim: "\(progress.done)/\(progress.total)").font(.system(size: 12).monospacedDigit())
                DockProgress(fraction: Double(progress.done) / Double(progress.total))
            }
        }
        .foregroundStyle(activity.waitingForPerson ? DS.warn : DS.inkFaint)
        .padding(.leading, 9).padding(.trailing, 14)
        .frame(minHeight: RunLayout.dockHeight)
        .contentShape(Capsule())
        .glassCapsule()
        .gesture(LongPressGesture().exclusively(before: TapGesture()).onEnded { value in
            switch value {
            case .first: showStats()
            case .second: open?()
            }
        })
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("run-activity-strip")
        .accessibilityAddTraits(open == nil ? [] : .isButton)
        .accessibilityAction { open?() }
        .accessibilityAction(named: Text("Show step stats")) { showStats() }
        .sensoryFeedback(.selection, trigger: presses)
        .task(id: presses) {
            guard showsStats else { return }
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            showsStats = false
        }
    }

    private func titleAndDetail(_ now: Date) -> some View {
        let flavor = showsStats ? nil : ActivityCopy.flavor(activity, now: now)
        let detail = showsStats ? stats(now) : [activity.detail, flavor ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(spacing: Space.xs) {
            Text(verbatim: activity.title).type(.labelMedium)
                .foregroundStyle(activity.waitingForPerson ? DS.warn : DS.ink)
                .fixedSize(horizontal: true, vertical: false)
            if !detail.isEmpty {
                Text(verbatim: detail)
                    .font(activity.code && !showsStats ? Mono.font(12) : .system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(activity.code ? DS.inkMuted : DS.inkFaint)
                    .contentTransition(.opacity)
            }
        }
    }

    private func clock(_ now: Date) -> some View {
        let start: Date? = activity.turnStart ?? activity.since
        let time = start.map { RunFormat.clock(now.timeIntervalSince($0)) }
        return Text(verbatim: time ?? String(localized: "Not reported"))
            .font(.system(size: 12).monospacedDigit()).fixedSize()
    }

    private func stats(_ now: Date) -> String {
        let elapsed = activity.since.map { RunFormat.clock(now.timeIntervalSince($0)) } ?? String(localized: "Not reported")
        let speed = rate.at(now.addingTimeInterval(skew))
        let title = speed >= 1 ? String(localized: "About \(Int(speed.rounded())) tokens/s") : String(localized: "No text streaming")
        return [String(localized: "This step \(elapsed)"), title].joined(separator: " · ")
    }

    private func showStats() {
        showsStats = true
        presses += 1
    }
}

struct ActivityWhale: View {
    let activity: RunActivity
    let rate: RunTokenRate
    var previewLevel: Int?
    var height: CGFloat = 20
    @Environment(\.appReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var origin = Date.now
    @State private var level = 1
    @State private var lastChange = Date.distantPast

    var body: some View {
        Group {
            if reduceMotion || scenePhase != .active {
                if let previewLevel, previewLevel > 1, let sprite = Self.frames[previewLevel]?.first {
                    frame(sprite)
                } else {
                    WhaleTail(height: height, tint: tint)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let target = previewLevel ?? speedLevel(rate.at(context.date))
                    let phase = max(0, context.date.timeIntervalSince(origin))
                    let frames = Self.frames[max(2, level)] ?? []
                    if frames.isEmpty {
                        WhaleTail(height: height, tint: tint)
                    } else {
                        let speed = level == 0 ? 0.3 : level == 1 ? 0.5 : 1
                        let duration = level < 3 ? 0.030 : 0.020
                        let position = phase * speed / duration
                        let index = Int(position) % frames.count
                        let blend = position - position.rounded(.down)
                        ZStack {
                            frame(frames[index]).opacity(1 - blend)
                            frame(frames[(index + 1) % frames.count]).opacity(blend)
                        }
                        .onChange(of: context.date, initial: true) {
                            if target != level, context.date.timeIntervalSince(lastChange) >= 0.9 {
                                level = target
                                origin = context.date
                                lastChange = context.date
                            }
                        }
                    }
                }
            }
        }
        .frame(width: height * 1.25, height: height)
        .accessibilityHidden(true)
    }

    private var tint: Color { activity.waitingForPerson ? DS.warn : DS.whale }

    private func speedLevel(_ speed: Double) -> Int {
        if activity.waitingForPerson || activity.kind == .stopping { return 0 }
        if activity.kind != .thinking && activity.kind != .writing && activity.kind != .tool { return 1 }
        if speed <= 0 { return 1 }
        if speed >= (level == 4 ? 60 : 75) { return 4 }
        if speed >= (level >= 3 ? 24 : 30) { return 3 }
        return 2
    }

    private func frame(_ image: UIImage) -> some View {
        Image(uiImage: image).renderingMode(.template).resizable().scaledToFit().foregroundStyle(tint)
    }

    private static let frames: [Int: [UIImage]] = Dictionary(uniqueKeysWithValues: (2...4).map { level in
        let atlas = UIImage(named: "whale_\(level).png")?.cgImage
        let count = level == 4 ? 36 : 24
        let images = (0..<count).compactMap { index -> UIImage? in
            let rect = CGRect(x: index % 6 * 120, y: index / 6 * 96, width: 120, height: 96)
            return atlas?.cropping(to: rect).map { UIImage(cgImage: $0) }
        }
        return (level, images)
    })
}
