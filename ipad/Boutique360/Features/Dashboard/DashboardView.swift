import SwiftUI

/// Today-focused dashboard. The single-owner's morning briefing:
/// "What needs my attention RIGHT NOW?"
struct DashboardView: View {
    @State private var boutique: Boutique?
    @State private var todaysAppointments: [Appointment] = []
    @State private var weekAppointments: [Appointment] = []
    @State private var openInquiries: Int = 0
    @State private var ordersInProgress: Int = 0
    @State private var paymentsOverdue: [Order] = []
    @State private var upcomingDates: [ImportantDate] = []
    @State private var dormantCustomers: [Customer] = []
    @State private var loading = true
    @State private var customers: [UUID: Customer] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    quickStatsGrid
                    todaySection
                    weekSection
                    upcomingDatesSection
                    paymentsOverdueSection
                    dormantSection
                }
            }
            .padding(32)
        }
        .navigationTitle("Dashboard")
        .task { await load() }
        .refreshable { await load() }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let b = boutique {
                Text(b.name).font(.system(size: 32, weight: .semibold, design: .serif))
                Text(greetingFor(date: Date()))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var quickStatsGrid: some View {
        LazyVGrid(columns: [.init(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            StatCard(label: "Today's fittings", value: "\(todaysAppointments.count)", icon: "calendar", tint: .blue)
            StatCard(label: "Open inquiries", value: "\(openInquiries)", icon: "envelope", tint: .indigo)
            StatCard(label: "Orders in progress", value: "\(ordersInProgress)", icon: "bag", tint: .orange)
            StatCard(label: "Payments overdue", value: "\(paymentsOverdue.count)", icon: "exclamationmark.triangle", tint: paymentsOverdue.isEmpty ? .green : .red)
        }
    }

    private var todaySection: some View {
        Group {
            if !todaysAppointments.isEmpty {
                listSection(title: "Today", systemImage: "sun.max") {
                    ForEach(todaysAppointments) { appt in
                        appointmentRow(appt)
                    }
                }
            }
        }
    }

    private var weekSection: some View {
        Group {
            if !weekAppointments.filter({ !Calendar.current.isDateInToday($0.scheduledAt) }).isEmpty {
                listSection(title: "Rest of this week", systemImage: "calendar") {
                    ForEach(weekAppointments.filter { !Calendar.current.isDateInToday($0.scheduledAt) }) { appt in
                        appointmentRow(appt)
                    }
                }
            }
        }
    }

    private var upcomingDatesSection: some View {
        Group {
            if !upcomingDates.isEmpty {
                listSection(title: "Important dates this month", systemImage: "gift") {
                    ForEach(upcomingDates) { d in
                        HStack {
                            Image(systemName: "gift")
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading) {
                                Text("\(customers[d.customerId]?.name ?? "Customer") · \(d.occasion)")
                                    .font(.subheadline.weight(.medium))
                                Text(d.date).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if d.recurring {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var paymentsOverdueSection: some View {
        Group {
            if !paymentsOverdue.isEmpty {
                listSection(title: "Payments overdue", systemImage: "exclamationmark.triangle.fill") {
                    ForEach(paymentsOverdue) { o in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(customers[o.customerId]?.name ?? "—").font(.subheadline.weight(.medium))
                                Text(o.orderNumber).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatINR(o.total))
                                .foregroundStyle(.red)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var dormantSection: some View {
        Group {
            if !dormantCustomers.isEmpty {
                listSection(title: "Haven't ordered in 90 days", systemImage: "person.crop.circle.badge.clock") {
                    ForEach(dormantCustomers.prefix(5)) { c in
                        HStack {
                            Text(c.name).font(.subheadline)
                            if c.vipStatus { Image(systemName: "crown.fill").foregroundStyle(.yellow).font(.caption) }
                            Spacer()
                            Text("Reach out").font(.caption2).foregroundStyle(.blue)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func listSection<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage).font(.headline)
            GroupBox {
                VStack(alignment: .leading, spacing: 0) { content() }
            }
        }
    }

    private func appointmentRow(_ appt: Appointment) -> some View {
        HStack {
            VStack {
                Text(appt.scheduledAt.formatted(.dateTime.hour().minute()))
                    .font(.subheadline.weight(.medium)).monospacedDigit()
            }
            .frame(width: 56)
            Image(systemName: appt.type.systemImage)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading) {
                Text(customers[appt.customerId]?.name ?? "—").font(.subheadline.weight(.medium))
                Text(appt.type.label).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if !Calendar.current.isDateInToday(appt.scheduledAt) {
                Text(appt.scheduledAt.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func greetingFor(date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        let greet = h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        return "\(greet) — \(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))"
    }

    private func formatINR(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "INR"; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "₹\(Int(v))"
    }

    private func load() async {
        loading = true; defer { loading = false }
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let weekEnd = cal.date(byAdding: .day, value: 7, to: todayStart)!
        let monthEnd = cal.date(byAdding: .day, value: 30, to: todayStart)!

        async let boutiqueRes: [Boutique] = (try? await SupabaseService.client.from("boutiques").select().limit(1).execute().value) ?? []
        async let weekAppts = (try? await AppointmentsService.list(from: todayStart, to: weekEnd)) ?? []
        async let openInq = (try? await InquiriesService.list()) ?? []
        async let activeOrders = (try? await OrdersService.list()) ?? []
        async let allCust = (try? await CustomersService.list()) ?? []
        async let dates: [ImportantDate] = await fetchUpcomingDates(until: monthEnd)

        let bRows = await boutiqueRes
        self.boutique = bRows.first
        let appts = await weekAppts
        self.todaysAppointments = appts.filter { cal.isDateInToday($0.scheduledAt) && $0.status == .scheduled }
        self.weekAppointments = appts.filter { $0.status == .scheduled }

        let inq = await openInq
        self.openInquiries = inq.filter { ![.delivered, .lost, .ready].contains($0.status) }.count

        let orders = await activeOrders
        self.ordersInProgress = orders.filter { [.pending, .confirmed, .packed, .shipped].contains($0.status) }.count
        // payments overdue: orders that should be confirmed/shipped/delivered but balance > 0
        self.paymentsOverdue = await filterOverdue(orders: orders)

        let custList = await allCust
        self.customers = Dictionary(uniqueKeysWithValues: custList.map { ($0.id, $0) })

        // dormant: no order in 90 days. Approximation: customers whose updated_at < 90d ago
        let ninetyAgo = cal.date(byAdding: .day, value: -90, to: now)!
        let recentCustomerIds = Set(orders.filter { $0.createdAt > ninetyAgo }.map(\.customerId))
        self.dormantCustomers = custList.filter { !recentCustomerIds.contains($0.id) && $0.updatedAt < ninetyAgo }

        self.upcomingDates = await dates
    }

    private func fetchUpcomingDates(until: Date) async -> [ImportantDate] {
        // Fetch all dates, filter client-side for "in next 30 days" considering recurrence
        let all: [ImportantDate] = (try? await SupabaseService.client.from("important_dates")
            .select()
            .execute()
            .value) ?? []
        let now = Date()
        return all.filter { d in
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            guard var parsed = f.date(from: d.date) else { return false }
            if d.recurring {
                // Align to current/next year
                let nowYear = Calendar.current.component(.year, from: now)
                let dComp = Calendar.current.dateComponents([.month, .day], from: parsed)
                var nextComp = DateComponents(year: nowYear, month: dComp.month, day: dComp.day)
                if let candidate = Calendar.current.date(from: nextComp), candidate >= Calendar.current.startOfDay(for: now) {
                    parsed = candidate
                } else {
                    nextComp.year = nowYear + 1
                    parsed = Calendar.current.date(from: nextComp) ?? parsed
                }
            }
            return parsed >= Calendar.current.startOfDay(for: now) && parsed <= until
        }.sorted { $0.date < $1.date }
    }

    private func filterOverdue(orders: [Order]) async -> [Order] {
        // Order has balance due AND placed > 7 days ago AND status != cancelled/returned
        var result: [Order] = []
        for o in orders where ![.cancelled, .returned, .pending].contains(o.status) {
            let days = Calendar.current.dateComponents([.day], from: o.placedAt ?? o.createdAt, to: Date()).day ?? 0
            guard days >= 7 else { continue }
            struct PaymentSum: Decodable { let amount: Double; let status: String }
            let payments: [PaymentSum] = (try? await SupabaseService.client.from("payments")
                .select("amount,status")
                .eq("order_id", value: o.id)
                .execute().value) ?? []
            let received = payments.filter { $0.status == "captured" }.reduce(0) { $0 + $1.amount }
            if received < o.total {
                result.append(o)
            }
        }
        return result
    }
}

private struct StatCard: View {
    let label: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                }
                Spacer()
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
            }
        }
    }
}
