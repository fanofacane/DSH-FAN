// SPDX-License-Identifier: AGPL-3.0-or-later
#if DEBUG
import DSHClient
import Foundation

extension AppSession {
    func smokeT5(_ result: FeatureSmokeContext) async throws {
        let initial = try await self.connection.accountAPI.getState()
        if initial.status == "credential-stored" {
            result.set("existingAccountKept", true)
        } else {
            var observedWatch = false
            let observer = Task { @MainActor in
                do { for try await _ in try await self.connection.accountAPI.watch() { observedWatch = true } } catch {}
            }
            defer { observer.cancel() }
            _ = try await self.connection.accountAPI.startSignIn(client: DeepSeekAccountPage.metadata, callbackOrigin: "http://127.0.0.1:3080")
            var current = AccountState()
            let end = Date().addingTimeInterval(30)
            while Date() < end {
                current = try await self.connection.accountAPI.getState()
                let attempt = current.attempt
                if attempt.phase == "waiting-browser" { break }
                if ["failed", "expired"].contains(attempt.phase ?? "") { throw DSHError("E_ACCOUNT_SIGNIN_" + (attempt.errorCode ?? "FAILED")) }
                try await Task.sleep(nanoseconds: 150_000_000)
            }
            let attempt = current.attempt
            guard let attemptId = attempt.id,
                  let text = attempt.authorizeUrl, let url = URL(string: text),
                  url.scheme == "https", url.host == "platform.deepseek.com" else { throw DSHError("E_ACCOUNT_AUTH_URL") }
            let cancelled = try await self.connection.accountAPI.cancelSignIn(attemptId: attemptId)
            guard cancelled.attempt.phase == "cancelled" else { throw DSHError("E_ACCOUNT_CANCEL") }
            result.set("watchObserved", observedWatch)
            result.set("authorizationPrepared", true); result.set("cancelled", true)
            result.set("userSignedIn", false)
        }
    }
}
#endif
