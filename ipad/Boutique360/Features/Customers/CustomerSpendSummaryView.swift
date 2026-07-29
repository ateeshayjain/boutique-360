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
            // Accessibility: read totals aloud rather than the chart description.
            .accessibilityLabel("Spend by month, last 12 months")
            .accessibilityValue(
                summary.monthlyTotals
                    .filter { $0.total > 0 }
                    .map { "\($0.label) \(Formatters.inr($0.total))" }
                    .joined(separator: ", ")
            )
        }
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
