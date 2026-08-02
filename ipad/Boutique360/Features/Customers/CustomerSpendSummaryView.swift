import SwiftUI
import Charts

/// "Spend & history" panel for `CustomerDetailView`. Renders:
/// - 3 KPI tiles: lifetime spend, order count, avg order value
/// - 12-month bar chart of spend
/// - First / last order dates
///
/// Stateless — all math comes from `CustomerSpend.summarize`. Pass in the
/// orders the parent already loaded, no extra round-trip.
struct CustomerSpendSummaryView: View {
    @EnvironmentObject private var roles: StaffRoleContext
    let orders: [Order]

    private var summary: CustomerSpend.Summary {
        CustomerSpend.summarize(orders)
    }

    /// R4b — gated inside the view so any future call site inherits it.
    @ViewBuilder
    var body: some View {
        if RolePolicy.canSee(.spendPanel, role: roles.role) {
            panel
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spend & history").font(.headline)

            if summary.orderCount == 0 {
                Text("No completed orders yet — spend totals will appear here.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                kpiRow
                if summary.monthlyTotals.contains(where: { $0.total > 0 }) {
                    chart
                }
                footnote
            }
        }
        .padding(14)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var kpiRow: some View {
        HStack(spacing: 10) {
            kpi("Lifetime", Formatters.inr(summary.lifetimeSpend))
            kpi("Orders", "\(summary.orderCount)")
            kpi("Avg", Formatters.inr(summary.avgOrderValue))
        }
    }

    private func kpi(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 12 months")
                .font(.caption).foregroundStyle(.secondary)
            Chart(summary.monthlyTotals) { mt in
                BarMark(
                    x: .value("Month", mt.monthStart, unit: .month),
                    y: .value("Spend", mt.total)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(3)
            }
            .frame(height: 120)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 2)) { value in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                    AxisGridLine()
                }
            }
            // A11y §4: "Charts expose a text summary (total, top item, trend
            // direction) — the visual is hidden for the reader, the summary is
            // not." Without `children: .ignore`, SwiftUI Charts exposes each
            // BarMark separately and a reader walks 12 anonymous bars.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Spend by month, last 12 months")
            .accessibilityValue(chartAccessibilitySummary)
        }
    }

    /// Headline first (total, biggest month, direction), detail after — a
    /// reader shouldn't have to sit through twelve figures to learn the shape.
    private var chartAccessibilitySummary: String {
        let months = summary.monthlyTotals.filter { $0.total > 0 }
        guard !months.isEmpty else { return "No spend in the last 12 months." }

        let total = months.reduce(0) { $0 + $1.total }
        var parts = ["Total \(Formatters.inr(total)) across \(months.count) \(months.count == 1 ? "month" : "months")"]

        if let top = months.max(by: { $0.total < $1.total }) {
            parts.append("highest \(top.label) at \(Formatters.inr(top.total))")
        }

        // Trend: compare the most recent month against the mean of the rest.
        if months.count >= 2, let latest = months.last {
            let priorMean = months.dropLast().reduce(0) { $0 + $1.total } / Double(months.count - 1)
            let direction: String
            if Money.equalAtPaise(latest.total, priorMean) {
                direction = "level with"
            } else {
                direction = latest.total > priorMean ? "above" : "below"
            }
            parts.append("most recent month \(direction) the earlier average")
        }

        parts.append("by month: " + months.map { "\($0.label) \(Formatters.inr($0.total))" }
            .joined(separator: ", "))
        return parts.joined(separator: ". ") + "."
    }

    private var footnote: some View {
        Group {
            if let first = summary.firstOrderAt, let last = summary.lastOrderAt {
                Text("First order \(first.formatted(date: .abbreviated, time: .omitted)) · last \(last.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text("Excludes cancelled and returned orders.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
