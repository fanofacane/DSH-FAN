// SPDX-License-Identifier: AGPL-3.0-or-later
// Formatting from DSH Go app/lib/ui/chat/{run_info,usage_sheet}.dart.
import Foundation

public enum RunFormat {
    public static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite else { return String(localized: "Not reported") }
        if seconds < 0 { return String(localized: "0 s") }
        let millis = (seconds * 1000).rounded() // Durable timestamps have millisecond precision.
        if millis < 100 { return String(localized: "<0.1 s") }
        if millis < 10_000 {
            let value = decimal(millis / 1000, digits: 1)
            return String(localized: "\(value) s")
        }
        guard let total = Int(exactly: (millis / 1000).rounded()) else { return String(localized: "Not reported") }
        if total < 60 { return String(localized: "\(total) s") }
        if total < 3600 { return String(localized: "\(total / 60)m \(padded(total % 60))s") }
        return String(localized: "\(total / 3600)h \(padded(total / 60 % 60))m")
    }

    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(exactly: max(0, seconds).rounded(.down)) ?? 0
        let tail = padded(total % 60)
        if total < 3600 { return "\(total / 60):\(tail)" }
        return "\(total / 3600):\(padded(total / 60 % 60)):\(tail)"
    }

    public static func tokens(_ count: Int) -> String {
        let value = count.magnitude
        if value < 1000 { return String(count) }
        let sign = count < 0 ? "-" : ""
        if value < 999_500 {
            let thousands = Double(value) / 1000
            return sign + decimal(thousands, digits: thousands >= 100 ? 0 : 1) + "K"
        }
        return sign + decimal(Double(value) / 1_000_000, digits: 2) + "M"
    }

    public static func percent(_ fraction: Double) -> String {
        if fraction > 0, fraction < 0.01 { return "<1%" }
        return (Int(exactly: (fraction * 100).rounded()).map(String.init) ?? "—") + "%"
    }

    public static func cost(_ amount: Double) -> String {
        if amount < 0.01 { return String(localized: "Under ¥0.01") }
        let text = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), amount)
        return String(localized: "About ¥\(text)")
    }

    private static func padded(_ value: Int) -> String { value < 10 ? "0\(value)" : String(value) }

    private static func decimal(_ value: Double, digits: Int) -> String {
        let text = String(format: "%.*f", digits, value)
        guard digits > 0 else { return text }
        return text.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}

/// Model tokens at the published peak CNY rates, verified 2026-11-05.
/// https://api-docs.deepseek.com/zh-cn/quick_start/pricing/
/// Only the built-in official route is covered. Estimates use current peak
/// rates for historical turns too. Actual charges can vary by time and account.
public enum RunPricing {
    private struct Rate {
        let uncached: Double
        let cacheHit: Double
        let output: Double
    }
    private static let rates = [
        "deepseek-official/deepseek-flash": Rate(uncached: 2, cacheHit: 0.04, output: 8),
        "deepseek-official/deepseek-v4-pro": Rate(uncached: 9, cacheHit: 0.30, output: 27)
    ]

    public static func estimate(_ trace: TurnTrace) -> Double? {
        let requests = trace.spans.filter { $0.kind == .model && $0.seq >= 0 }.compactMap(\.model)
        guard !requests.isEmpty else { return nil }
        var total = 0.0
        for request in requests {
            guard let provider = request.provider, let model = request.model, let rate = rates[provider + "/" + model],
                  let usage = request.usage, let uncached = usage.uncachedInput, let output = usage.output else { return nil }
            total += ((Double(uncached) + Double(usage.cacheWrite ?? 0)) * rate.uncached
                      + Double(usage.cacheRead ?? 0) * rate.cacheHit + Double(output) * rate.output) / 1_000_000
        }
        return total
    }
    /// A partial history or a request billed at an unknown rate cannot
    /// establish a whole-session estimate.
    public static func sessionEstimate(_ turns: [TurnTrace], metrics: SessionMetrics) -> Double? {
        let billed = turns.filter { !$0.running || $0.steps > 0 }
        let totals = billed.compactMap(\.usage.total)
        guard let reported = metrics.total, !totals.isEmpty, totals.count == billed.count,
              metrics.turns == turns.filter({ !$0.running }).count,
              sumTokens(totals) == reported else { return nil }
        let amounts = billed.compactMap(estimate)
        return amounts.count == billed.count ? amounts.reduce(0, +) : nil
    }

}
