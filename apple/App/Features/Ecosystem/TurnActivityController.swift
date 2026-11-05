// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/lib/pets/pet_overlay_*.dart. ActivityKit replaces the Android overlay.
import ActivityKit
import SwiftUI

@MainActor final class TurnActivityController {
    private typealias Turn = Activity<DSHActivityAttributes>
    private typealias State = DSHActivityAttributes.ContentState
    private var activity: Turn?
    private var last: State?
    private var retryAfter = Date.distantPast
    private var wasBusy = false
    private var running = false

    func run(with chat: AppSession, pet: PetModel, preferences: AppPreferences) async {
        guard !running else { return }
        running = true
        defer { running = false }
        activity = Turn.activities.first { $0.activityState == .active || $0.activityState == .stale }
        last = activity?.content.state
        while !Task.isCancelled {
            await tick(chat, pet: pet, showTurn: preferences.showLiveActivity)
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }

    private func tick(_ chat: AppSession, pet: PetModel, showTurn: Bool) async {
        let busy = showTurn && chat.transcript.busy
        defer { wasBusy = busy }
        if let activity, activity.activityState == .dismissed || activity.activityState == .ended {
            if activity.activityState == .dismissed && last?.pet != nil {
                pet.outsideSnoozedUntil = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))
            }
            self.activity = nil
            last = nil
            retryAfter = .now.addingTimeInterval(15)
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let showPet = pet.preferences.outside && pet.visible && !pet.outsideSnoozed
            && (pet.preferences.outsideDisplay == .always || chat.hasRunningTasks || pet.bubble != nil)
        let artwork = showPet ? pet.pack.map { pack in
            State.Pet(pack: pack.id, animation: pack.animationName(for: pet.expression, tier: 0, random: false))
        } : nil
        if busy || artwork != nil {
            var state = busy ? turnState(chat) : State(phase: .idle, detail: "", tools: 0)
            state.pet = artwork
            if let activity {
                guard state != last else { return }
                last = state
                await activity.update(.init(state: state, staleDate: nil))
            } else if pet.foreground, Date.now >= retryAfter {
                do {
                    // Keep private chat titles, message text and tool arguments off the Lock Screen.
                    activity = try Turn.request(attributes: DSHActivityAttributes(title: "DSH Fan"),
                                                content: .init(state: state, staleDate: nil))
                    last = state
                    pet.outsideError = nil
                } catch {
                    retryAfter = .now.addingTimeInterval(15)
                    if artwork != nil { pet.outsideError = "E_LIVE_ACTIVITY" }
                }
            }
        } else if let activity {
            self.activity = nil
            last = nil
            if wasBusy {
                let failed = chat.transcript.items.last?.role == .notice
                let final = State(phase: failed ? .failed : .done, detail: "", tools: 0)
                await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(4)))
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func turnState(_ chat: AppSession) -> State {
        let calls = chat.transcript.items.flatMap(\.tools).filter { $0.result == nil }
        if chat.requests.currentApproval != nil || chat.requests.currentQuestion != nil {
            return State(phase: .waiting, detail: "", tools: calls.count)
        }
        if !calls.isEmpty { return State(phase: .working, detail: "", tools: calls.count) }
        if let draft = chat.transcript.draft, !draft.text.isEmpty { return State(phase: .replying, detail: "", tools: 0) }
        return State(phase: .thinking, detail: "", tools: 0)
    }
}
