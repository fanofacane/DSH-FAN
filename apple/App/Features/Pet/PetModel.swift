// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/pets/{pet_state,pet_signals,pet_prefs}.dart and ui/pets/pet_stage.dart.
import Observation
import SwiftUI

@MainActor @Observable final class PetModel {
    let packs: [PetPack]
    private let defaults: UserDefaults
    var preferences: PetPreferences { didSet { preferences.save(to: defaults) } }
    private(set) var expression: PetExpression = .idle
    private(set) var bubble: PetBubbleState?
    private(set) var target: String?
    private(set) var playID = 0
    private(set) var animationName = "idle"
    private(set) var hidden = false
    private(set) var roamOffset: CGFloat = 0
    private(set) var mirrored = false
    @ObservationIgnored private var nextRoam = Date.now.addingTimeInterval(120)
    var outsideError: String?
    var composerVisible = false
    var foreground = true
    var carrying = false
    var reducesMotion = false
    var outsideSnoozedUntil: Date? {
        didSet { defaults.set(outsideSnoozedUntil, forKey: "pet.outsideSnoozedUntil") }
    }

    @ObservationIgnored private var mood = PetMood(now: .now)
    @ObservationIgnored private var previousFocus: String?
    @ObservationIgnored private var previousRuns: Set<String> = []
    @ObservationIgnored private var generation: Int?
    @ObservationIgnored private var tier = 0
    @ObservationIgnored private var reactionUntil: Date?
    @ObservationIgnored private var nextIdle = Date.distantFuture
    @ObservationIgnored private var taps: [Date] = []

    var pack: PetPack? { packs.first { $0.id == preferences.packID } }
    var enabled: Bool { pack != nil }
    var visible: Bool { enabled && !hidden }
    var outsideSnoozed: Bool { outsideSnoozedUntil.map { $0 > .now } ?? false }

    init(defaults: UserDefaults = .standard, packs: [PetPack] = PetPack.catalog()) {
        self.defaults = defaults
        self.packs = packs
        let fallback = packs.first(where: { $0.id == "deepy-whale" }) ?? packs.first
        var preferences = PetPreferences(defaults: defaults, defaultPack: fallback?.id)
        if preferences.packID != PetPreferences.none && !packs.contains(where: { $0.id == preferences.packID }) {
            preferences.packID = fallback?.id ?? PetPreferences.none
        }
        self.preferences = preferences
        hidden = preferences.hiddenUntil.map { $0 > .now } ?? false
        outsideSnoozedUntil = defaults.object(forKey: "pet.outsideSnoozedUntil") as? Date
        animationName = pack?.animationName(for: .idle, tier: 0, random: false) ?? "idle"
        nextIdle = .now.addingTimeInterval(pack?.idleDelay() ?? 120)
    }

    func select(_ id: String) {
        guard id == PetPreferences.none || packs.contains(where: { $0.id == id }) else { return }
        preferences.packID = id
        preferences.hiddenUntil = nil
        hidden = false
        reactionUntil = nil
        play(pack?.animationName(for: expression, tier: tier) ?? "idle")
    }

    func hide() {
        preferences.hiddenUntil = .now.addingTimeInterval(3600)
        hidden = true
        dismissBubble()
    }

    func unhide() {
        preferences.hiddenUntil = nil
        hidden = false
        touch()
    }

    func dismissBubble() { mood.dismissBubble(); bubble = nil }
    func touch() {
        mood.touch(at: .now)
        if roamOffset != 0 { roamOffset = 0; mirrored = false }
    }

    func tap(leftHalf: Bool) {
        touch()
        guard !reducesMotion, expression != .sleeping, expression != .waking else { return }
        let now = Date.now
        taps.removeAll { now.timeIntervalSince($0) > 1.1 }
        taps.append(now)
        let reaction = taps.count >= 3 ? "tickle" : leftHalf ? "tapLeft" : "tapRight"
        guard let pack, let name = pack.reactions[reaction], let animation = pack.animation(name) else { return }
        reactionUntil = now.addingTimeInterval(animation.total)
        play(name)
    }

    func run(with chat: AppSession) async {
        while !Task.isCancelled {
            tick(chat, now: .now)
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        }
    }

    private func tick(_ chat: AppSession, now: Date) {
        let generation = chat.connection.generation
        if self.generation != generation {
            self.generation = generation
            previousFocus = nil
            previousRuns = []
            mood = PetMood(now: now)
            reactionUntil = nil
        }
        let hiddenNow = preferences.hiddenUntil.map { $0 > now } ?? false
        if hidden != hiddenNow { hidden = hiddenNow }
        if let until = outsideSnoozedUntil, until <= now { outsideSnoozedUntil = nil }
        guard let pack else { return }

        let signal = snapshot(chat, now: now)
        let events = completions(chat, signal: signal, now: now)
        mood.advance(signal, events: events, now: now, timings: PetTimings(minimum: pack.minDisplay,
                                                                           autoReturn: pack.autoReturn,
                                                                           sleep: pack.sleepAfter, wake: pack.wake))
        if bubble != mood.bubble { bubble = mood.bubble }
        if target != mood.target { target = mood.target }
        if expression != mood.expression || tier != mood.tier {
            expression = mood.expression
            tier = mood.tier
            reactionUntil = nil
            roamOffset = 0; mirrored = false
            play(pack.animationName(for: expression, tier: tier))
            if expression == .idle { nextIdle = now.addingTimeInterval(pack.idleDelay()) }
        } else if let until = reactionUntil, until <= now {
            reactionUntil = nil
            play(pack.animationName(for: expression, tier: tier))
        } else if expression == .idle, reactionUntil == nil, now >= nextRoam,
                  visible, foreground, composerVisible, !reducesMotion, let roaming = pack.roaming {
            nextRoam = now.addingTimeInterval(pack.idleDelay())
            let offset = roamOffset == 0 ? CGFloat.random(in: 0.08...0.2) * (Bool.random() ? 1 : -1) : 0
            mirrored = !pack.facesFront && offset < roamOffset
            withAnimation(.easeInOut(duration: 1.2)) { roamOffset = offset }
            reactionUntil = now.addingTimeInterval(pack.animation(roaming)?.total ?? 1.2)
            play(roaming)
        } else if expression == .idle, reactionUntil == nil, now >= nextIdle,
                  visible, foreground, composerVisible, !reducesMotion {
            nextIdle = now.addingTimeInterval(pack.idleDelay())
            let sum = pack.idlePool.reduce(0.0) { $0 + $1.weight }
            guard sum > 0 else { return }
            var draw = Double.random(in: 0..<sum)
            for idle in pack.idlePool {
                draw -= idle.weight
                if draw < 0 {
                    reactionUntil = now.addingTimeInterval(idle.duration)
                    play(idle.name)
                    break
                }
            }
        }
    }

    private func snapshot(_ chat: AppSession, now: Date) -> PetSignal {
        let focus = chat.transcript.currentSessionId
        let running = chat.transcript.draft?.tools.filter { $0.result == nil } ?? []
        let activity: PetSignal.Activity = chat.transcript.busy
            ? ((!running.isEmpty || !(chat.transcript.draft?.text.isEmpty ?? true)) ? .working : .thinking) : .idle
        let compact = chat.transcript.traceFold.compactionStart != nil
        let title: (String) -> String? = { id in chat.transcript.sessions.first { $0.id == id }?.title }
        let approvals = chat.requests.approvals.map { PetEvent(id: $0.id, kind: .approval, session: $0.sessionId,
                                                             title: title($0.sessionId), at: now) }
        let questions = chat.requests.questions.map { PetEvent(id: $0.id, kind: .question, session: $0.sessionId,
                                                             title: title($0.sessionId), at: now) }
        return PetSignal(activity: activity, focus: focus, viewing: foreground && composerVisible,
                         runs: chat.requests.runningSessions, subagents: running.filter { $0.name == "subagent" }.count,
                         requests: approvals + questions, compacting: compact, carrying: carrying, quiet: preferences.quiet)
    }

    private func completions(_ chat: AppSession, signal: PetSignal, now: Date) -> [PetEvent] {
        defer {
            previousFocus = signal.activity == .idle ? nil : signal.focus
            previousRuns = signal.runs
        }
        var completions = previousRuns.subtracting(signal.runs).filter { $0 != signal.focus }
            .map { id in PetEvent(id: UUID().uuidString, kind: .done, session: id,
                                  title: chat.transcript.sessions.first { $0.id == id }?.title, at: now) }
        if let id = signal.focus, previousFocus == id, signal.activity == .idle {
            let reason = chat.transcript.events.reversed().compactMap { event -> String? in
                if case .turnEnded(_, _, let reason) = event { return reason }
                return nil
            }.first
            let failed: Bool
            if case .failed = chat.transcript.committed.last?.state { failed = true } else { failed = false }
            let kind: PetEvent.Kind = failed ? .failed : reason == "completed" ? .done : .stopped
            completions.append(PetEvent(id: UUID().uuidString, kind: kind, session: id,
                                        title: chat.transcript.currentTitle, at: now))
        }
        return completions
    }

    private func play(_ name: String) {
        animationName = name
        playID += 1
    }
}
