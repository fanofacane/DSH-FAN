// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

public enum ComposerCompletion {
    public static func commandAllowed(_ name: String) -> Bool {
        !["export", "share", "share-code", "bot", "bots", "community", "forum", "star", "feedback"].contains(name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
    /// DSH's text grammar, not an uploaded attachment. A quoted folder keeps
    /// the quote open so the user can continue completing inside it.
    public static func mention(path: String, directory: Bool) -> String? {
        guard !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.value == 34 }) else { return nil }
        let text = path + (directory ? "/" : "")
        if text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil { return "@" + text }
        return "@\"" + text + (directory ? "" : "\"")
    }
    /// Completion at the end of the composer, including a partially quoted path.
    public static func fileRange(in text: String) -> Range<String.Index>? {
        guard let at = text.range(of: "@", options: .backwards),
              at.lowerBound == text.startIndex || text[text.index(before: at.lowerBound)].isWhitespace else { return nil }
        let suffix = text[at.upperBound...]
        if suffix.hasPrefix("\"") {
            guard !suffix.dropFirst().contains("\"") else { return nil }
        } else if suffix.contains(where: \.isWhitespace) { return nil }
        return at.lowerBound..<text.endIndex
    }
}
