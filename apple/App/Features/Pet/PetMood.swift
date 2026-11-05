// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/pets/{pet_mood,pet_state,pet_signals}.dart.
import Foundation

enum PetExpression: String {
    case idle, thinking, working, juggling, carrying, attention, sweeping, notification, error, sleeping, waking

    var priority: Int {
        switch self {
        case .error: 8
        case .notification: 7
        case .sweeping: 6
        case .attention: 5
        case .carrying, .juggling: 4
        case .working: 3
        case .thinking: 2
        case .idle, .waking: 1
        case .sleeping: 0
        }
    }

    var minimum: TimeInterval {
        switch self {
        case .attention: 5.2
        case .error: 4.8
        case .sweeping: 5.6
        case .notification, .carrying: 3.2
        case .working, .thinking: 1
        default: 0
        }
    }

    var autoReturn: TimeInterval {
        switch self {
        case .sweeping: 300
        default: minimum
        }
    }
}

struct PetSignal {
    enum Activity { case idle, thinking, working, stopping }
    var activity: Activity = .idle
    var focus: String?
    var viewing = true
    var runs: Set<String> = []
    var subagents = 0
    var requests: [PetEvent] = []
    var compacting = false
    var carrying = false
    var quiet = false
}

struct PetEvent: Equatable, Identifiable {
    enum Kind: String {
        case done, failed, stopped, approval, question
        var waits: Bool { self == .approval || self == .question }
        var rank: Int {
            switch self {
            case .stopped: 0
            case .done: 1
            case .failed: 2
            case .approval, .question: 3
            }
        }
        var duration: TimeInterval { waits ? 8 : self == .failed ? 6 : 4 }
    }
    let id: String
    let kind: Kind
    let session: String
    var title: String?
    let at: Date
}

struct PetBubbleState: Equatable, Identifiable {
    let event: PetEvent
    let shownAt: Date
    var until: Date
    var sessions: Set<String>
    var id: String { event.id }

    init(_ event: PetEvent, now: Date) {
        self.event = event
        shownAt = now
        until = now.addingTimeInterval(event.kind.duration)
        sessions = [event.session]
    }
}

struct PetTimings {
    var minimum: [String: Double] = [:]
    var autoReturn: [String: Double] = [:]
    var sleep: TimeInterval = 60
    var wake: TimeInterval = 1.5

    func minimum(_ state: PetExpression) -> TimeInterval { minimum[state.rawValue] ?? state.minimum }
    func returnAfter(_ state: PetExpression) -> TimeInterval { autoReturn[state.rawValue] ?? state.autoReturn }
}

/// Level signals and edges enter here together. Clock and inputs are explicit
/// so waiting, priority, and expiry rules can be tested without a view or engine.
struct PetMood {
    private(set) var expression: PetExpression = .idle
    private(set) var tier = 0
    private(set) var bubble: PetBubbleState?
    private(set) var target: String?
    private var since: Date
    private var lastBusy: Date
    private var lastTouch: Date
    private var compactSince: Date?
    private var wakingUntil: Date?
    private var lower: (tier: Int, since: Date)?
    private var flash: (expression: PetExpression, until: Date)?
    private var held: [PetEvent] = []
    private var queued: PetBubbleState?
    private var requestsSince: [String: Date] = [:]
    private var runsSince: [String: Date] = [:]
    private var unseen: [String: PetEvent] = [:]

    init(now: Date) {
        since = now
        lastBusy = now
        lastTouch = now
    }

    mutating func touch(at time: Date) { lastTouch = time }
    mutating func dismissBubble() { bubble = nil }

    mutating func advance(_ signal: PetSignal, events: [PetEvent] = [], now: Date, timings: PetTimings = .init()) {
        let active = signal.runs.union(signal.activity == .idle ? [] : [signal.focus].compactMap { $0 })
        runsSince = Dictionary(uniqueKeysWithValues: active.map { ($0, runsSince[$0] ?? now) })
        let previousRequests = requestsSince
        requestsSince = Dictionary(signal.requests.map { ($0.id, requestsSince[$0.id] ?? now) },
                                   uniquingKeysWith: min)
        let requestIDs = Set(requestsSince.keys)
        if let bubble, bubble.until <= now || (bubble.event.kind.waits && !requestIDs.contains(bubble.id)) {
            self.bubble = nil
        }
        if let queued, now.timeIntervalSince(queued.shownAt) > 10
            || (queued.event.kind.waits && !requestIDs.contains(queued.id)) {
            self.queued = nil
        }
        if bubble == nil, let queued {
            bubble = PetBubbleState(queued.event, now: now)
            self.queued = nil
        }
        if let flash, flash.until <= now { self.flash = nil }

        for event in events {
            switch event.kind {
            case .done: held.append(event)
            case .stopped: held.removeAll { $0.session == event.session }
            case .failed: handle(event, signal: signal, now: now, timings: timings)
            case .approval, .question: break // Requests arrive in the level snapshot.
            }
        }
        for request in signal.requests where previousRequests[request.id] == nil {
            if !(signal.viewing && signal.focus == request.session) && !signal.quiet { offer(request, now: now) }
        }
        let ripe = held.filter { !active.contains($0.session) && now.timeIntervalSince($0.at) >= 1.5 }
        held.removeAll { active.contains($0.session) || now.timeIntervalSince($0.at) >= 1.5 }
        for event in ripe { handle(event, signal: signal, now: now, timings: timings) }
        if signal.viewing, let focus = signal.focus { unseen.removeValue(forKey: focus) }
        if signal.quiet { bubble = nil; queued = nil }
        target = signal.requests.min { (requestsSince[$0.id] ?? now) < (requestsSince[$1.id] ?? now) }?.session
            ?? unseen.values.max { ($0.kind.rank, $0.at) < ($1.kind.rank, $1.at) }?.session
            ?? runsSince.max { $0.value < $1.value }?.key ?? signal.focus

        compactSince = signal.compacting ? (compactSince ?? now) : nil
        let sweeping = compactSince.map { now.timeIntervalSince($0) < timings.returnAfter(.sweeping) } ?? false
        let (desired, desiredTier) = candidate(signal, sweeping: sweeping, active: active)
        settle(desired, tier: desiredTier, now: now, timings: timings)
    }

    private func candidate(_ signal: PetSignal, sweeping: Bool, active: Set<String>) -> (PetExpression, Int) {
        if flash?.expression == .error { return (.error, 0) }
        if !signal.requests.isEmpty { return (.notification, 0) }
        if sweeping { return (.sweeping, 0) }
        if flash?.expression == .attention { return (.attention, 0) }
        if signal.carrying { return (.carrying, 0) }
        if signal.subagents > 0 { return (.juggling, min(2, signal.subagents)) }
        if signal.activity == .working || active.contains(where: { $0 != signal.focus }) {
            return (.working, min(3, max(1, active.count)))
        }
        if signal.activity == .stopping, [.working, .thinking, .juggling].contains(expression) { return (expression, tier) }
        if signal.activity != .idle { return (.thinking, 0) }
        return (.idle, 0)
    }

    private mutating func settle(_ desired: PetExpression, tier desiredTier: Int, now: Date, timings: PetTimings) {
        if desired != .idle { lastBusy = now }
        let sleep = desired == .idle && now.timeIntervalSince(max(lastBusy, lastTouch)) >= timings.sleep
        if expression == .sleeping && !sleep { wakingUntil = now.addingTimeInterval(timings.wake) }
        if desired.priority >= PetExpression.notification.priority || sleep { wakingUntil = nil }
        let next: PetExpression = sleep ? .sleeping : (wakingUntil ?? .distantPast) > now ? .waking : desired
        let nextTier = next == desired ? desiredTier : 0
        if next == expression && nextTier < tier {
            if lower?.tier != nextTier { lower = (nextTier, now) }
            if let lower, now.timeIntervalSince(lower.since) < 5 { return }
        } else if next != expression && expression != .waking && next.priority <= expression.priority
                    && now.timeIntervalSince(since) < timings.minimum(expression) {
            return
        }
        if next != expression { since = now }
        expression = next
        tier = nextTier
        lower = nil
    }

    private mutating func handle(_ event: PetEvent, signal: PetSignal, now: Date, timings: PetTimings) {
        let expression: PetExpression = event.kind == .failed ? .error : .attention
        if flash?.expression != .error || expression == .error {
            flash = (expression, now.addingTimeInterval(timings.returnAfter(expression)))
        }
        if !(signal.viewing && signal.focus == event.session) {
            unseen[event.session] = event
            if !signal.quiet { offer(event, now: now) }
        }
    }

    private mutating func offer(_ event: PetEvent, now: Date) {
        let proposed = PetBubbleState(event, now: now)
        guard let current = bubble else { bubble = proposed; return }
        if current.event.kind == event.kind && now.timeIntervalSince(current.shownAt) < 2 {
            if !current.sessions.contains(event.session) {
                bubble?.sessions.insert(event.session)
                bubble?.until = proposed.until
            }
        } else if event.kind.rank >= current.event.kind.rank {
            if event.kind.rank > current.event.kind.rank { queued = current }
            bubble = proposed
        } else {
            queued = proposed
        }
    }
}
