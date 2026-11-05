// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/activity_copy.dart (slot rotation and narration).
import DSHClient
import Foundation

enum ActivityCopy {
    static func flavor(_ activity: RunActivity, now: Date) -> String? {
        let start = activity.since ?? activity.turnStart
        let elapsed = start.map { max(0, now.timeIntervalSince($0)) } ?? 0
        let slot = Int(exactly: (elapsed / 4).rounded(.down)) ?? 0
        let seed = Self.seed(start) ^ Self.seed(activity.turnStart)
        func phrase(_ pool: Pool) -> String { rotate(seed: seed, slot: slot) { _ in pool } }

        switch activity.kind {
        case .tool, .approval, .question, .stopping: return nil
        case .compaction: return phrase(compaction)
        case .retry: return phrase(activity.rateLimited ? rateLimit : retry)
        default: break
        }
        if let narration = activity.narration { return narration }

        let isRare = activity.firstStep && activity.turnStart != nil && mix(Self.seed(activity.turnStart), 0x5EED) % 150 == 0
        func pool(_ window: Int) -> Pool {
            let local = now.addingTimeInterval(Double(window) * 4 - elapsed)
            if window == 0 {
                if let tool = activity.lastTool, let pool = after(tool) { return pool }
                if activity.lastTool != nil, let milestone = milestones[activity.toolsDone] { return [milestone] }
                if activity.firstStep {
                    if let holiday = holiday(local) { return holiday }
                    if !isRare, Calendar.current.isDateInWeekend(local) { return weekend }
                }
            }
            if isRare { return rare }
            switch activity.kind {
            case .waiting: return waiting
            case .writing: return writing
            default:
                if window >= 75 { return longThinking }
                if window >= 15 { return deepThinking }
                if window >= 8 { return moreThinking }
                return Calendar.current.component(.hour, from: local) < 6 ? thinking + night : thinking
            }
        }
        if slot > 0, let start = activity.turnStart, let reminder = reminder(now.timeIntervalSince(start)) { return reminder }
        return rotate(seed: seed, slot: slot, pool: pool)
    }

    static func narration(_ text: String) -> String? {
        guard let last = text.split(separator: "\n").last(where: { $0.hasPrefix("⏵") }) else { return nil }
        let clean = last.dropFirst().prefix { $0 != "⏵" }.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
        var line = String(String.UnicodeScalarView(clean)).trimmingCharacters(in: .whitespacesAndNewlines)
        if let end = line.range(of: #"[。．!?！？;；]|\.(?=\s|$|[A-Z][a-z])"#, options: .regularExpression) {
            line = String(line[..<end.upperBound])
        }
        var columns = 0
        if let boundary = line.firstIndex(where: {
            columns += $0.unicodeScalars.first.map { $0.value >= 0x2E80 ? 2 : 1 } ?? 1
            return columns > 80
        }) {
            let head = line[..<boundary]
            line = head.lastIndex(where: { " ，、,;；".contains($0) }).map { String(head[..<$0]) } ?? String(head)
        }
        line = line.replacingOccurrences(of: #"[。．.!！,，、;；]+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }

    private static func seed(_ date: Date?) -> UInt32 {
        UInt32(truncatingIfNeeded: Int64(exactly: ((date?.timeIntervalSince1970 ?? 0) * 1000).rounded()) ?? 0)
    }

    private static func mix(_ seed: UInt32, _ slot: Int) -> UInt32 {
        var value = (seed &* 0x9E3779B1) ^ (UInt32(truncatingIfNeeded: slot) &* 0x85EBCA6B)
        value = (value ^ (value >> 15)) &* 0x2545F491
        value = (value ^ (value >> 13)) &* 0x9E3779B1
        return value ^ (value >> 16)
    }

    private static func rotate(seed: UInt32, slot: Int, pool: (Int) -> Pool) -> String {
        func lines(_ window: Int) -> [String] {
            var used: Set<String> = []
            return pool(window).map { String(localized: $0) }.filter { used.insert($0).inserted }
        }
        func direct(_ window: Int, _ words: [String]) -> String {
            let index = words.count <= 2 ? Int(mix(seed, 0)) + window : Int(mix(seed, window))
            return words[index % words.count]
        }
        let words = lines(slot)
        guard slot % 2 != 0, words.count > 2 else { return direct(slot, words) }
        let previous = direct(slot - 1, lines(slot - 1))
        let next = direct(slot + 1, lines(slot + 1))
        let index = Int(mix(seed, slot)) % words.count
        return (words[index...] + words[..<index]).first { $0 != previous && $0 != next } ?? words[index]
    }

    private static func after(_ span: TraceSpan) -> Pool? {
        let command = ToolRow(id: "", name: span.toolName ?? "", arguments: span.arguments ?? "").args["command"]?.string ?? ""
        func matches(_ pattern: String) -> Bool { command.range(of: pattern, options: .regularExpression) != nil }
        let test = matches(#"\b(flutter test|dart test|npm (run )?test|pnpm (run )?test|yarn test|pytest|go test|cargo test|jest|vitest|gradlew? test|mvn test)\b"#)
        if span.failed { return test ? testFail : fail }
        if test { return testPass }
        if matches(#"\bgit\s+push\b"#) { return gitPush }
        if matches(#"\bgit\s+commit\b"#) { return gitCommit }
        if matches(#"\b(npm (i|install|ci)|pnpm (i|install|add)|yarn (install|add)|pip3? install|flutter pub get|dart pub get|cargo fetch|apt(-get)? install)\b"#) {
            return install
        }
        return nil
    }

    private static func holiday(_ date: Date) -> Pool? {
        let solar = Calendar.current.dateComponents([.month, .day], from: date)
        let lunarDay = Calendar(identifier: .chinese).dateComponents([.month, .day, .year], from: date)
        if lunarDay.month == 1, let day = lunarDay.day, day <= 7, let year = lunarDay.year {
            let animal = String(localized: zodiac[(max(1, year) - 1) % 12])
            return lunar + ["Wishing you a happy Year of the \(animal)"]
        }
        return holidays[(solar.month ?? 0) * 100 + (solar.day ?? 0)]
    }

    private static func reminder(_ elapsed: TimeInterval) -> String? {
        guard let hours = Int(exactly: (elapsed / 3600).rounded(.down)) else { return nil }
        if hours > 0, elapsed.truncatingRemainder(dividingBy: 3600) < 8 {
            return String(localized: "Still here after \(hours) hours")
        }
        if (1800..<1808).contains(elapsed) { return String(localized: "Half an hour. Time for some water?") }
        if (600..<608).contains(elapsed) { return String(localized: "Ten minutes already") }
        return nil
    }
}
