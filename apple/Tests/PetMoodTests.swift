// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go: app/test/pets/{pet_mood_test,pet_parts_test}.dart.
import Foundation
import Testing
@testable import DSH

struct PetMoodTests {
    private let start = Date(timeIntervalSince1970: 1000)
    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    @Test func workingTierStepsDownAfterHoldingAndApprovalTakesPriority() {
        var mood = PetMood(now: start)
        var signal = PetSignal(activity: .working, focus: "a", runs: ["a", "b", "c"])
        mood.advance(signal, now: at(1))
        #expect(mood.expression == .working && mood.tier == 3)
        signal.runs = ["a"]
        mood.advance(signal, now: at(2))
        mood.advance(signal, now: at(6.99))
        #expect(mood.tier == 3)
        mood.advance(signal, now: at(7))
        #expect(mood.tier == 1)
        signal.requests = [PetEvent(id: "q", kind: .question, session: "b", at: at(7))]
        mood.advance(signal, now: at(7))
        #expect(mood.expression == .notification && mood.target == "b" && mood.bubble?.id == "q")
        signal.requests = []
        mood.advance(signal, now: at(7.1))
        #expect(mood.bubble == nil)
    }

    @Test func touchingWakesThePetAndAnErrorInterruptsTheYawn() {
        var mood = PetMood(now: start)
        mood.advance(.init(), now: at(61))
        #expect(mood.expression == .sleeping)
        mood.touch(at: at(62))
        mood.advance(.init(), now: at(62))
        #expect(mood.expression == .waking)
        let failed = PetEvent(id: "f", kind: .failed, session: "a", at: at(62.5))
        mood.advance(.init(), events: [failed], now: at(62.5))
        #expect(mood.expression == .error && mood.bubble?.id == "f")
        mood.advance(.init(quiet: true), now: at(63))
        #expect(mood.expression == .error && mood.bubble == nil)
    }

    @Test func finishWaitsForTheNextRoundAndMergesUnseenConversations() {
        var mood = PetMood(now: start)
        let finish = PetEvent(id: "f", kind: .done, session: "a", at: at(1))
        mood.advance(.init(), events: [finish], now: at(1))
        #expect(mood.expression == .idle && mood.bubble == nil)
        mood.advance(.init(activity: .thinking, focus: "a"), now: at(2))
        mood.advance(.init(), now: at(4))
        #expect(mood.bubble == nil)
        let later = [
            PetEvent(id: "b", kind: .done, session: "b", at: at(5)),
            PetEvent(id: "c", kind: .done, session: "c", at: at(5.2)),
        ]
        mood.advance(.init(), events: later, now: at(5.2))
        mood.advance(.init(), now: at(7))
        #expect(mood.expression == .attention && mood.bubble?.sessions == ["b", "c"])
    }

    @Test func petPreferencesMigrateAndPersist() throws {
        let suite = "DSHPetTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "pet.enabled")
        defaults.set(40.0, forKey: "pet.bodyHeight")
        defaults.set(-0.5, forKey: "pet.position")
        var preferences = PetPreferences(defaults: defaults, defaultPack: "example")
        #expect(preferences.packID == PetPreferences.none)
        #expect(preferences.size == .large && preferences.position == 0)
        preferences.packID = "another"
        preferences.outside = true
        preferences.outsideDisplay = .always
        preferences.position = 0.8
        preferences.quiet = true
        preferences.hiddenUntil = at(3600)
        preferences.save(to: defaults)
        #expect(PetPreferences(defaults: defaults, defaultPack: "example") == preferences)
    }
}
