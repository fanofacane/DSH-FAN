// SPDX-License-Identifier: AGPL-3.0-or-later
// DSH Go app/lib/ui/chat/balance_widgets.dart and app/lib/state/balance_state.dart.
import DSHClient
import SwiftUI

struct RunBalance: Equatable {
    let currency: String
    let paid: Decimal?
    let bonus: Decimal?
    var total: Decimal { (paid ?? 0) + (bonus ?? 0) }
    static let limits: [Double] = [0, 1, 5, 10, 20, 50]
    static let defaultLimit: Double = 5

    init(currency: String, paid: Decimal?, bonus: Decimal?) {
        self.currency = currency
        self.paid = paid
        self.bonus = bonus
    }

    init?(_ wallets: [AccountWallet]) {
        let values = wallets.compactMap { wallet -> (currency: String, value: Decimal, bonus: Bool)? in
            guard let currency = wallet.currency, !currency.isEmpty, let balance = wallet.balance,
                  let amount = Decimal(string: balance, locale: Locale(identifier: "en_US_POSIX")), !amount.isNaN else { return nil }
            return (currency, amount, wallet.bonus)
        }
        guard let currency = ["CNY", "USD"].first(where: { code in values.contains { $0.currency == code } })
                ?? values.first?.currency else { return nil }
        func total(_ bonus: Bool) -> Decimal? {
            let group = values.filter { $0.currency == currency && $0.bonus == bonus }
            return group.isEmpty ? nil : group.reduce(0) { $0 + $1.value }
        }
        self.init(currency: currency, paid: total(false), bonus: total(true))
    }

    func isLow(_ limit: Double) -> Bool { limit > 0 && total < Decimal(limit) }
    func money(_ amount: Decimal, decimals: Int = 2) -> String {
        let prefix = currency == "CNY" ? "¥" : currency == "USD" ? "$" : currency + " "
        return prefix + amount.formatted(.number.precision(.fractionLength(decimals)).locale(Locale(identifier: "en_US_POSIX")))
    }
    func thresholdLabel(_ limit: Double) -> String {
        if limit == 0 { return String(localized: "No reminder") }
        return String(localized: "Below \(money(Decimal(limit), decimals: 0))")
    }
}

/// Cache for the active local connection. The account grant stays in the engine.
@MainActor @Observable final class RunBalanceStore {
    private var generation: Int?
    private var balance: RunBalance?
    private var requested: Date?
    private var inFlight: Int?

    func value(for connection: ConnectionStore, isRemote: Bool) -> RunBalance? {
        guard !isRemote, connection.state == .ready, connection.generation == generation else { return nil }
        return balance
    }

    func refresh(_ connection: ConnectionStore, isRemote: Bool) async {
        let generation = connection.generation
        guard !isRemote, connection.state == .ready else { return }
        if self.generation != generation {
            self.generation = generation
            balance = nil
            requested = nil
        }
        guard inFlight != generation, requested.map({ Date.now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        inFlight = generation
        requested = .now
        defer { if inFlight == generation { inFlight = nil } }
        let wallets = try? await connection.accountAPI.getBalance(client: DeepSeekAccountPage.metadata)
        guard self.generation == generation, connection.generation == generation, connection.state == .ready else { return }
        if Task.isCancelled { requested = nil; return }
        balance = wallets.flatMap(RunBalance.init)
    }
}

struct RunBalanceCard: View {
    let balance: RunBalance
    @Binding var limit: Double
    @Environment(\.designTheme) private var theme

    var body: some View {
        RunPanelSection(title: "DeepSeek balance") {
            HStack(spacing: Space.sm) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    RunFigure(value: balance.money(balance.total), size: RunLayout.usageHeadline,
                              color: balance.isLow(limit) ? DS.warn : DS.ink)
                    Text(notes).type(.bodySmall).foregroundStyle(balance.isLow(limit) ? DS.warn : DS.inkFaint)
                }
                Spacer(minLength: 0)
                BalanceTopUp()
            }
            HStack {
                Text("Low balance alert").type(.bodyMedium)
                Spacer()
                Menu {
                    Picker("Reminder threshold", selection: $limit) {
                        ForEach(RunBalance.limits, id: \.self) { level in
                            Text(balance.thresholdLabel(level)).tag(level)
                        }
                    }
                } label: {
                    HStack(spacing: Space.xs) {
                        Text(balance.thresholdLabel(limit)).type(.bodyMedium)
                        Glyph(glyph: AppIcon.dropdown, size: 18)
                    }.foregroundStyle(theme.accent)
                }
            }
        }
    }

    private var notes: String {
        var parts: [String] = []
        if let paid = balance.paid { parts.append(String(localized: "Paid \(balance.money(paid))")) }
        if let bonus = balance.bonus, bonus > 0 { parts.append(String(localized: "Bonus \(balance.money(bonus))")) }
        if balance.isLow(limit) { parts.append(String(localized: "Balance low")) }
        return parts.joined(separator: " · ")
    }
}

struct LowBalanceBanner: View {
    let balance: RunBalance
    let limit: Double
    let dismiss: () -> Void
    @State private var dismissed = false

    var body: some View {
        HStack(spacing: Space.sm) {
            Glyph(glyph: AppIcon.balance, size: 18).foregroundStyle(DS.warn)
            let headline = Text("Only \(balance.money(balance.total)) left").bold().foregroundColor(DS.ink)
            let detail = Text(verbatim: " · " + balance.thresholdLabel(limit)).foregroundColor(DS.inkFaint)
            Text("\(headline)\(detail)").type(.bodySmall).lineLimit(1)
            Spacer(minLength: 0)
            BalanceTopUp()
            Button { dismissed = true; dismiss() } label: {
                Glyph(glyph: AppIcon.close, size: 18)
                    .foregroundStyle(DS.inkFaint).frame(width: 40, height: 40).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
        }
        .padding(.leading, Space.lg).padding(.trailing, Space.xxs)
        .frame(minHeight: 44)
        .glassCapsule()
        .sensoryFeedback(.selection, trigger: dismissed)
    }
}

private struct BalanceTopUp: View {
    @Environment(\.designTheme) private var theme
    var body: some View {
        Link(destination: URL(string: "https://platform.deepseek.com/top_up")!) {
            HStack(spacing: Space.xs) {
                Text("Top up").type(.label)
                Glyph(glyph: AppIcon.openLink, size: 16)
            }
            .foregroundStyle(theme.accent)
            .frame(minHeight: 40)
        }
    }
}
