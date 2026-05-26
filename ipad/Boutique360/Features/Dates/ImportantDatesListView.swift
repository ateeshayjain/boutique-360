import SwiftUI

/// All upcoming important dates across customers, grouped by week.
/// Sidebar item; helps owner schedule birthday/anniversary outreach proactively.
struct ImportantDatesListView: View {
    @State private var dates: [(date: Date, importantDate: ImportantDate, customer: Customer?)] = []
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError, dates.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load dates", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(err)
                } actions: {
                    Button("Retry") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
            } else if dates.isEmpty {
                ContentUnavailableView(
                    "No upcoming dates",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Capture birthdays, anniversaries, and important events from each customer's profile.")
                )
            } else {
                List {
                    ForEach(groupedByWeek, id: \.weekStart) { group in
                        Section(header: Text(group.weekLabel)) {
                            ForEach(group.items.indices, id: \.self) { idx in
                                let item = group.items[idx]
                                HStack {
                                    Image(systemName: "gift.fill")
                                        .foregroundStyle(.purple)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.customer?.name ?? "—").font(.subheadline.weight(.medium))
                                        Text(item.importantDate.occasion).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text(item.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                            .font(.caption).monospacedDigit()
                                        Text("in \(daysFromNow(item.date)) days")
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Important dates")
        .task { await load() }
        .refreshable { await load() }
    }

    private var groupedByWeek: [(weekStart: Date, weekLabel: String, items: [(date: Date, importantDate: ImportantDate, customer: Customer?)])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: dates) { item in
            cal.dateInterval(of: .weekOfYear, for: item.date)?.start ?? item.date
        }
        return grouped.sorted { $0.key < $1.key }.map { (key, items) in
            let label: String
            if cal.isDate(key, equalTo: Date(), toGranularity: .weekOfYear) { label = "This week" }
            else if let next = cal.date(byAdding: .weekOfYear, value: 1, to: Date()), cal.isDate(key, equalTo: next, toGranularity: .weekOfYear) { label = "Next week" }
            else { label = "Week of \(key.formatted(.dateTime.day().month(.abbreviated)))" }
            return (weekStart: key, weekLabel: label, items: items)
        }
    }

    private func daysFromNow(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
    }

    private func load() async {
        loading = true; defer { loading = false }
        let now = Date()
        let cal = Calendar.current
        let until = cal.date(byAdding: .day, value: 90, to: now)!
        do {
            let all: [ImportantDate] = try await SupabaseService.client.from("important_dates")
                .select()
                .execute()
                .value
            let custs = (try? await CustomersService.list()) ?? []
            let custMap = Dictionary(uniqueKeysWithValues: custs.map { ($0.id, $0) })
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"

            var result: [(Date, ImportantDate, Customer?)] = []
            for d in all {
                guard var parsed = f.date(from: d.date) else { continue }
                if d.recurring {
                    let nowYear = cal.component(.year, from: now)
                    let dComp = cal.dateComponents([.month, .day], from: parsed)
                    var nextComp = DateComponents(year: nowYear, month: dComp.month, day: dComp.day)
                    if let candidate = cal.date(from: nextComp), candidate >= cal.startOfDay(for: now) {
                        parsed = candidate
                    } else {
                        nextComp.year = nowYear + 1
                        parsed = cal.date(from: nextComp) ?? parsed
                    }
                }
                if parsed >= cal.startOfDay(for: now) && parsed <= until {
                    result.append((parsed, d, custMap[d.customerId]))
                }
            }
            self.dates = result.sorted { $0.0 < $1.0 }
            self.loadError = nil
        } catch {
            self.loadError = error.localizedDescription
        }
    }
}
