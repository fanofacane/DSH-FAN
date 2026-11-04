// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation
import DSHRuntime

extension AppSession {
    func smokeT15(_ result: FeatureSmokeContext) async throws {
        let dependencies = result.dependencies
        let runtime = dependencies.runtime, preferences = dependencies.preferences
        let original = try await runtime.replyPreferences()
        let marker = "IOS-PREF-" + UUID().uuidString
        let updated = original + "\nWhen the user asks for the iOS preference verification word, reply with exactly: " + marker + "\n"
        try await runtime.saveReplyPreferences(updated, expected: original)
        do {
            guard try await runtime.replyPreferences() == updated else { throw DSHError("E_PREFERENCES_ROUNDTRIP") }
            do {
                try await runtime.saveReplyPreferences("stale", expected: original)
                throw DSHError("E_PREFERENCES_CAS")
            } catch let error as RuntimeError { guard error.code == "E_PREFERENCES_CHANGED" else { throw error } }
            self.transcript.newChat(); await self.transcript.send("What is the iOS preference verification word? Do not use tools.")
            try await smokeWait(seconds: 120) { !self.transcript.busy && self.transcript.items.contains { $0.role == .assistant && $0.state == .done } }
            guard self.transcript.items.contains(where: { $0.role == .assistant && $0.text.contains(marker) }) else { throw DSHError("E_PREFERENCES_NOT_LOADED") }
            try await runtime.saveReplyPreferences(original, expected: updated)
        } catch { try? await runtime.saveReplyPreferences(original, expected: updated); throw error }
        let oldPalette = preferences.palette, oldAppearance = preferences.appearance, oldScale = preferences.textScale, oldImages = preferences.remoteImages
        defer {
            preferences.palette = oldPalette; preferences.appearance = oldAppearance; preferences.textScale = oldScale; preferences.remoteImages = oldImages
        }
        preferences.palette = "teal"; preferences.appearance = "dark"; preferences.textScale = 1.2; preferences.remoteImages = false
        guard preferences.colorScheme == .dark, preferences.scale == 1.2, !preferences.remoteImages,
              UserDefaults.standard.string(forKey: "ui.palette") == "teal" else { throw DSHError("E_APP_PREFERENCES") }
        preferences.palette = oldPalette; preferences.appearance = oldAppearance; preferences.textScale = oldScale; preferences.remoteImages = oldImages
        do { _ = try DiagnosticExport.writeReviewed("Synthetic diagnostic fixture", reviewed: false); throw DSHError("E_REVIEW_BYPASSED") }
        catch let error as DSHError { guard error.code == "E_DIAGNOSTICS_REVIEW" else { throw error } }
        let export = try DiagnosticExport.writeReviewed("Synthetic diagnostic fixture", reviewed: true)
        defer { try? FileManager.default.removeItem(at: export) }
        guard try String(contentsOf: export, encoding: .utf8) == "Synthetic diagnostic fixture" else { throw DSHError("E_EXPORT_ROUNDTRIP") }
        result.set("realModelReadPreferences", true); result.set("preferencesRestored", true)
        result.set("appearancePersistence", true); result.set("reviewedSyntheticExport", true)
    }
}
#endif
