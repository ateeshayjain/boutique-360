import SwiftUI

/// R2 — exception-first morning board. Pure renderer of MorningBoard.Board;
/// degradation map per spec: "—" only for tiles/lanes whose input failed,
/// real zeros for genuinely empty data.
struct MorningBoardView: View {
    @EnvironmentObject private var roles: StaffRoleContext
    let board: MorningBoard.Board
    let ordersById: [UUID: Order]
    // R4a — the Reminders section renders between the needs-you list and the
    // pipeline strip. It owns its own loading/empty states, so it is NOT
    // gated on `drafts.isEmpty` here.
    var drafts: [ReminderDrafts.Draft] = []
    var remindersLoading: Bool = false
    var onSendReminder: (ReminderDrafts.Draft) -> Void = { _ in }
    var onMarkReminderDone: (ReminderDrafts.Draft) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            tileRow
            if !boardBlocked, !board.needsYou.isEmpty {
                needsYouList
            }
            RemindersSectionView(drafts: drafts, isLoading: remindersLoading,
                                 onSend: onSendReminder, onMarkDone: onMarkReminderDone)
            pipelineStrip
        }
    }

    /// orders/jobCards failure means the board can't be trusted at all.
    private var boardBlocked: Bool {
        board.failed.contains(.orders) || board.failed.contains(.jobCards)
    }

    // MARK: - Tiles

    private var tileRow: some View {
        HStack(spacing: 12) {
            tile(title: "Today",
                 value: board.failed.contains(.appointments)
                    ? "— fittings · \(board.todayDeliveries) deliveries"
                    : "\(board.todayFittings) fittings · \(board.todayDeliveries) deliveries",
                 caption: "appointments + hand-overs",
                 tint: .blue)

            if RolePolicy.canSee(.moneyDueTile, role: roles.role) {
                tile(title: "Money due",
                     value: board.failed.contains(.payments) ? "—" : Formatters.inr(board.moneyDue.total),
                     caption: board.failed.contains(.payments)
                        ? "couldn't load payments"
                        : "\(board.moneyDue.orderCount) orders · oldest \(board.moneyDue.oldestDays)d",
                     tint: board.moneyDue.total > 0 ? .orange : .green)
            }

            tile(title: "At risk",
                 value: boardBlocked ? "—" : "\(board.atRiskCount)",
                 caption: boardBlocked ? "couldn't load orders"
                        : (board.atRiskCount == 0 ? "All on track" : "sorted below, worst first"),
                 tint: boardBlocked ? .gray : (board.atRiskCount > 0 ? .red : .green))
        }
    }

    private func tile(title: String, value: String, caption: String, tint: Color) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)   // a11y floor: shrinking a total is losing the total
                    .lineLimit(1)
                    .foregroundStyle(tint)
                Text(caption).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(caption)")
    }

    // MARK: - Needs you

    private var needsYouList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Needs you — worst first", systemImage: "flag.fill").font(.headline)
            GroupBox {
                VStack(spacing: 0) {
                    ForEach(board.needsYou.prefix(6)) { item in
                        if let order = ordersById[item.id] {
                            NavigationLink(value: order) { row(item) }
                                .buttonStyle(.plain)
                        } else {
                            row(item)
                        }
                    }
                    if board.needsYou.count > 6 {
                        Text("+ \(board.needsYou.count - 6) more in Orders")
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                }
            }
        }
    }

    private func row(_ item: MorningBoard.Item) -> some View {
        HStack(spacing: 10) {
            SlackBadge(verdict: item.verdict)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.customerName).font(.subheadline.weight(.medium))
                Text([item.orderNumber, item.garmentHint].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(actionLabel(item.action))
                .font(.caption.weight(.medium))
                .foregroundStyle(actionColor(item.action))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.customerName), \(item.orderNumber), \(actionLabel(item.action))")
    }

    private func actionLabel(_ a: MorningBoard.Action) -> String {
        switch a {
        case .chaseKarigar:              "Chase karigar"
        case .decideToday:               "Decide today"
        // R4b — the action itself still needs doing in assistant mode; only
        // the amount is withheld. Dropping the whole row would hide a
        // delivery the assistant is meant to hand over.
        case .deliverAndCollect(let v):
            RolePolicy.canSee(.paymentReminders, role: roles.role)
                ? "Deliver + collect \(Formatters.inr(v))"
                : "Deliver + collect balance"
        case .deliver:                   "Deliver"
        }
    }
    private func actionColor(_ a: MorningBoard.Action) -> Color {
        switch a {
        case .chaseKarigar:                .red
        case .decideToday:                 .orange
        case .deliverAndCollect, .deliver: .green
        }
    }

    // MARK: - Pipeline strip

    private var pipelineStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pipeline").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                lane("designing", count: board.failed.contains(.designs) ? nil : board.pipeline.designing, color: .purple)
                lane("to start", count: boardBlocked ? nil : board.pipeline.toStart, color: .orange)
                lane("with karigar", count: boardBlocked ? nil : board.pipeline.withKarigar, color: .teal)
                lane("trial / alter", count: board.failed.contains(.alterations) ? nil : board.pipeline.trialAlter, color: .yellow)
                lane("ready", count: boardBlocked ? nil : board.pipeline.ready, color: .green)
            }
        }
    }

    /// count == nil → the lane's input failed → "—".
    private func lane(_ label: String, count: Int?, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(count.map(String.init) ?? "—")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(color.opacity(0.16))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(label).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(minWidth: 44, maxWidth: .infinity)
        .layoutPriority(Double(max(count ?? 1, 1)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(count.map(String.init) ?? "unavailable")")
    }
}
