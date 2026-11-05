// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/state/run_pulse.dart (estimateTokens and TokenRateMeter).
import Foundation

/// A transient estimate for animation and the activity strip's long press.
struct RunTokenRate {
    private var samples: [(time: Date, count: Double)] = []
    private var burst: Date?

    mutating func add(_ text: String, now: Date = .now) {
        let count = text.unicodeScalars.reduce(0.0) { count, rune in
            let code = rune.value
            if code <= 0x20 || code == 0x3000 { return count }
            let eastAsian = (0x3400...0x9FFF).contains(code) || (0xF900...0xFAFF).contains(code)
                || (0x3040...0x30FF).contains(code) || (0xAC00...0xD7A3).contains(code)
                || (0x20000...0x3FFFF).contains(code)
            return count + (eastAsian ? 0.6 : 0.3)
        }
        guard count > 0 else { return }
        if let last = samples.last, now.timeIntervalSince(last.time) <= 1.2 {
            samples.removeAll { now.timeIntervalSince($0.time) > 2.5 }
        } else {
            samples.removeAll(keepingCapacity: true)
            burst = now
        }
        samples.append((now, count))
    }

    func at(_ now: Date) -> Double {
        guard let last = samples.last?.time, let burst, now.timeIntervalSince(last) <= 1.2 else { return 0 }
        let floor = max(burst, now.addingTimeInterval(-2.5))
        let total = samples.reduce(0.0) { $0 + ($1.time >= floor ? $1.count : 0) }
        return total / max(0.5, now.timeIntervalSince(floor))
    }
}
