// SPDX-License-Identifier: AGPL-3.0-or-later
// The pet standing on the composer: state machine and placement, following
// 原 Flutter 版 lib/ui/pets/pet_stage.dart and 原 Flutter 版 lib/pets/pet_state.dart (states, tiers,
// minimum display, auto return, idle pool, sleep/wake, tap reactions).
import Observation
import SwiftUI

@MainActor
@Observable
final class PetModel {

    var enabled: Bool { didSet { prefs.set(enabled, forKey: "pet.enabled") } }
    /// Body height in points: small 22 / standard 30 / large 40.
    var bodyHeight: CGFloat { didSet { prefs.set(Double(bodyHeight), forKey: "pet.bodyHeight") } }
    /// Foot position along the composer (share of its width).
    let position: CGFloat = 0.25

    private(set) var animationName = "idle"
    /// Bumped to restart a one-shot animation of the same name.
    private(set) var playID = 0
    let pack = PetPack.deepyWhale

    private enum Mode: Equatable { case state(String), oneShot(String, until: Date) }
    private var mode = Mode.state("idle")
    private var stateSince = Date()
    private var lastActivity = Date()
    private var nextIdleTrick = Date().addingTimeInterval(Double.random(in: 45...300))
    private var wasBusy = false
    private var holdUntil = Date.distantPast
    private var taps: [Date] = []
    private let prefs = UserDefaults.standard
    private var ticker: Task<Void, Never>?

    init() {
        enabled = prefs.object(forKey: "pet.enabled") as? Bool ?? true
        bodyHeight = CGFloat(prefs.object(forKey: "pet.bodyHeight") as? Double ?? 30)
    }

    /// Drives the pet from the chat state until the view disappears.
    func run(with chat: AppSession) {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick(chat)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }
    func stop() { ticker?.cancel(); ticker = nil }

    // MARK: State machine

    private func desiredState(_ chat: AppSession) -> String {
        if chat.requests.currentApproval != nil || chat.requests.currentQuestion != nil { return "notification" }
        guard chat.transcript.busy else { return "idle" }
        let running = chat.transcript.items.flatMap(\.tools).filter { $0.result == nil }.count
        let draft = chat.transcript.items.last { $0.state == .streaming }
        if running > 0 { return tiered("working", count: running) }
        if let draft, draft.text.isEmpty, !draft.reasoning.isEmpty { return "thinking" }
        if draft != nil { return "working" }
        return "thinking"
    }

    private func tiered(_ state: String, count: Int) -> String {
        guard let tiers = pack?.tiers[state] else { return state }
        return tiers.first { count >= $0.min }.map { "anim:" + $0.anim } ?? state
    }

    private func tick(_ chat: AppSession) {
        guard let pack else { return }
        let now = Date()
        // One-shots (wake, reactions, idle tricks) finish first.
        if case .oneShot(_, let until) = mode, now < until { return }

        var target = desiredState(chat)
        if chat.transcript.busy || target != "idle" { lastActivity = now }
        // Turn finished: celebrate, or show the error, for their auto-return time.
        if wasBusy && !chat.transcript.busy {
            let failed = chat.transcript.items.last?.role == .notice
            let state = failed ? "error" : "attention"
            holdUntil = now.addingTimeInterval(pack.autoReturn[state] ?? 5)
            mode = .state(state); stateSince = now; play(state); wasBusy = false
            return
        }
        wasBusy = chat.transcript.busy
        if now < holdUntil && target == "idle" { return }

        if case .state(let current) = mode {
            // Respect minimum display before switching away.
            if current != target, let min = pack.minDisplay[current], now.timeIntervalSince(stateSince) < min { return }
            if current == "sleeping" && target != "idle" {
                startOneShot(pack.states["waking"]?.first ?? "waking", seconds: pack.wake, now: now)
                mode = .oneShot("waking", until: now.addingTimeInterval(pack.wake)); stateSince = now
                return
            }
            if target == "idle" {
                if current == "sleeping" { return }
                if now.timeIntervalSince(lastActivity) > pack.sleepAfter { target = "sleeping" }
                else if now >= nextIdleTrick, let trick = pack.idlePool.randomElement() {
                    nextIdleTrick = now.addingTimeInterval(Double.random(in: 45...300))
                    startOneShot(trick.anim, seconds: trick.ms / 1000, now: now)
                    return
                }
            }
            if current != target { mode = .state(target); stateSince = now; play(target) }
        } else {
            mode = .state(target); stateSince = now; play(target)
        }
    }

    private func play(_ state: String) {
        let name = state.hasPrefix("anim:") ? String(state.dropFirst(5)) : (pack?.states[state]?.first ?? "idle")
        animationName = name; playID += 1
    }

    private func startOneShot(_ name: String, seconds: Double, now: Date) {
        mode = .oneShot(name, until: now.addingTimeInterval(seconds))
        animationName = name; playID += 1
    }

    /// Tap reactions: left / right half, three quick taps tickle.
    func tapped(leftHalf: Bool) {
        guard let pack else { return }
        let now = Date()
        lastActivity = now
        taps = taps.filter { now.timeIntervalSince($0) < 1.1 } + [now]
        let key = taps.count >= 3 ? "tickle" : leftHalf ? "tapLeft" : "tapRight"
        if taps.count >= 3 { taps = [] }
        guard let name = pack.reactions[key], let animation = pack.animation(name) else { return }
        startOneShot(name, seconds: animation.total, now: now)
        stateSince = now
    }
}

/// Stands the pet on the top edge of the composer it overlays.
struct PetPerch: View {
    @Environment(PetModel.self) private var pet
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            if pet.enabled, let pack = pet.pack, let animation = pack.animation(pet.animationName) {
                let s = pack.scale(bodyHeight: pet.bodyHeight, displayScale: displayScale)
                let left = (pack.anchorX - pack.contentBox.minX) * s, right = (pack.contentBox.maxX - pack.anchorX) * s
                let footX = min(max(geometry.size.width * pet.position, 16 + left), geometry.size.width - 16 - right)
                PetSpriteView(animation: animation, scale: s, canvas: pack.canvas)
                    .id(pet.playID)
                    .frame(width: pack.canvas.width * s, height: pack.canvas.height * s)
                    .contentShape(Rectangle().inset(by: 0))
                    .onTapGesture { location in pet.tapped(leftHalf: location.x < pack.anchorX * s) }
                    .offset(x: footX - pack.anchorX * s, y: -pack.baseline * s)
                    .accessibilityLabel(Text("Deepy the whale"))
                    .accessibilityAddTraits(.isButton)
            }
        }
        .frame(height: 0, alignment: .topLeading)
    }
}
