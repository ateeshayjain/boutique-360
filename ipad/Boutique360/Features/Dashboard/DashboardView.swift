import SwiftUI

/// Today-focused dashboard. The single-owner's morning briefing:
/// "What needs my attention RIGHT NOW?"
struct DashboardView: View {
    @EnvironmentObject private var roles: StaffRoleContext
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
    @State private var todayRevenue: Double = 0
    @State private var todayCashRevenue: Double = 0
    @State private var todayUpiRevenue: Double = 0
    @State private var todayNewCustomers: Int = 0
    @State private var todayNewOrders: Int = 0
    @State private var loadFailed: Bool = false        // H1: surface stale-data banner
    @State private var lastRefreshAt: Date?
    // R2: exception-first morning board.
    @State private var board: MorningBoard.Board?
    @State private var ordersById: [UUID: Order] = [:]
    // R4a: auto-drafted reminders. `loading` already tracks load() being in
    // flight — no second flag needed.
    @State private var reminderDrafts: [ReminderDrafts.Draft] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                if loadFailed { staleDataBanner }
                // Asks once, owner-only, self-hiding once a GSTIN exists.
                GSTINPromptCard()
                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    if let board {
                        MorningBoardView(
                            board: board,
                            ordersById: ordersById,
                            drafts: visibleDrafts,
                            remindersLoading: loading,
                            onSendReminder: { draft in
                                WhatsAppShareHelper.open(phone: draft.whatsappTarget,
                                                         message: draft.message)
                            },
                            onMarkReminderDone: { draft in
                                Task { await markReminderDone(draft) }
                            }
                        )
                    }
                    if RolePolicy.canSee(.revenueTile, role: roles.role) {
                        todaysRevenueCard
                    }
                    quickStatsGrid
                    todaySection
                    weekSection
                    upcomingDatesSection
                    if RolePolicy.canSee(.paymentReminders, role: roles.role) {
                        paymentsOverdueSection
                    }
                    dormantSection
                }
            }
            .padding(32)
        }
        .navigationTitle("Dashboard")
        // R2: needs-you rows push straight into the order (same pattern as
        // OrdersListView).
        .navigationDestination(for: Order.self) { o in
            OrderDetailView(order: o, customerName: customers[o.customerId]?.name)
        }
        .task { await load(); await primeNotifications() }
        .refreshable { await load() }
        // H4 fix: re-fetch when the app returns from background.
        .onReceive(NotificationCenter.default.publisher(for: .appDidForeground)) { _ in
            Task { await load() }
        }
    }

    /// R4b — payment reminders carry a rupee amount in the message body, so
    /// an assistant must not see them at all. Filtering here (rather than
    /// inside RemindersSectionView) means the section's header count is
    /// computed from the filtered list — no "5 reminders" above three rows.
    private var visibleDrafts: [ReminderDrafts.Draft] {
        RolePolicy.canSee(.paymentReminders, role: roles.role)
            ? reminderDrafts
            : reminderDrafts.filter { $0.kind != .payment }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let b = boutique {
                Text(b.name)
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(greetingFor(date: Date()))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var todaysRevenueCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Today", systemImage: "indianrupeesign.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Spacer()
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(Formatters.inr(todayRevenue))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)   // a11y floor: shrinking a total is losing the total
                        .lineLimit(1)
                    Spacer()
                    HStack(spacing: 14) {
                        revenueSplit("Cash", todayCashRevenue, icon: "banknote", tint: .green)
                        revenueSplit("UPI", todayUpiRevenue, icon: "qrcode", tint: .blue)
                    }
                }
                Divider()
                HStack(spacing: 24) {
                    miniMetric("New orders", "\(todayNewOrders)", icon: "bag.badge.plus")
                    miniMetric("New customers", "\(todayNewCustomers)", icon: "person.badge.plus")
                    Spacer()
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's revenue \(Formatters.inr(todayRevenue)), \(todayNewOrders) new orders, \(todayNewCustomers) new customers")
    }

    private func revenueSplit(_ label: String, _ value: Double, icon: String, tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2).foregroundStyle(tint)
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            Text(Formatters.inr(value))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
    }

    private func miniMetric(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// H1 fix: when the load partly or wholly failed, owners must know the
    /// numbers below are not authoritative — otherwise ₹0 revenue + 0 appointments
    /// looks like a normal quiet day instead of "Supabase unreachable."
    private var staleDataBanner: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Couldn't reach server").font(.subheadline.weight(.semibold))
                    Text("Figures below may be stale" + (lastRefreshAt.map { " — last refreshed \($0.formatted(.relative(presentation: .named)))" } ?? "") + ". Pull to retry.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var quickStatsGrid: some View {
        LazyVGrid(columns: [.init(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
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
                            if c.vipStatus {
                                Image(systemName: "crown.fill").foregroundStyle(.yellow).font(.caption)
                                    .accessibilityLabel("VIP")
                            }
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

    /// First-time: ask permission. Every time: refresh schedule from DB so
    /// new/edited appointments get reminders. iOS de-dupes by identifier.
    private func primeNotifications() async {
        let status = await NotificationsService.authorizationStatus()
        if status == .notDetermined {
            _ = await NotificationsService.requestAuthorization()
        }
        await NotificationsService.refresh()
    }

    private func greetingFor(date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        let greet = h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        return "\(greet) — \(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))"
    }

    private func formatINR(_ v: Double) -> String { Formatters.inr(v) }

    private func load() async {
        loading = true; defer { loading = false }
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        // L5 fix: guard the Calendar arithmetic instead of force-unwrapping.
        let weekEnd = cal.date(byAdding: .day, value: 7, to: todayStart) ?? now
        let monthEnd = cal.date(byAdding: .day, value: 30, to: todayStart) ?? now

        // M4 fix: read boutique from BoutiqueContext (already RLS-validated).
        // R4a: if the context hasn't finished loading yet (Dashboard's task can
        // win the race against BoutiqueContext.refresh() right after sign-in),
        // refresh it first. Otherwise the boutique NAME is nil and every
        // reminder draft gets signed "— Boutique" — and unlike a blank header,
        // that fallback would be SENT to a customer.
        if BoutiqueContext.shared.boutique == nil {
            await BoutiqueContext.shared.refresh()
        }
        self.boutique = BoutiqueContext.shared.boutique

        // Fan out 5 reads in parallel, then merge results + track failures.
        // Each task returns (result, failed) so the caller doesn't need Sendable closures.
        async let weekApptsFut: ([Appointment], Bool) = {
            do { return (try await AppointmentsService.list(from: todayStart, to: weekEnd), false) }
            catch { return ([], true) }
        }()
        async let openInqFut: ([Inquiry], Bool) = {
            do { return (try await InquiriesService.list(), false) }
            catch { return ([], true) }
        }()
        async let activeOrdersFut: ([Order], Bool) = {
            do { return (try await OrdersService.list(), false) }
            catch { return ([], true) }
        }()
        async let allCustFut: ([Customer], Bool) = {
            do { return (try await CustomersService.list(), false) }
            catch { return ([], true) }
        }()
        async let datesFut: [ImportantDate] = fetchUpcomingDates(until: monthEnd)

        let (weekAppts, f1) = await weekApptsFut
        let (openInq, f2) = await openInqFut
        let (activeOrders, f3) = await activeOrdersFut
        let (allCust, f4) = await allCustFut
        let dates = await datesFut
        var anyFailed = f1 || f2 || f3 || f4
        self.todaysAppointments = weekAppts.filter { cal.isDateInToday($0.scheduledAt) && $0.status == .scheduled }
        self.weekAppointments = weekAppts.filter { $0.status == .scheduled }
        self.openInquiries = openInq.filter { ![.delivered, .lost, .ready].contains($0.status) }.count
        self.ordersInProgress = activeOrders.filter { [.pending, .confirmed, .packed, .shipped].contains($0.status) }.count

        self.customers = Dictionary(uniqueKeysWithValues: allCust.map { ($0.id, $0) })

        // ── R2: morning-board inputs + shared payments fetch.
        var failures: Set<MorningBoard.Input> = []
        if f1 { failures.insert(.appointments) }
        if f3 { failures.insert(.orders) }

        let bid = BoutiqueContext.shared.boutiqueId

        var jobCardsByOrder: [UUID: JobCard] = [:]
        var latestEventByCard: [UUID: JobCardEvent] = [:]
        if let bid {
            do {
                let cards = try await JobCardsService.forOrders(activeOrders.map(\.id), boutiqueId: bid)
                jobCardsByOrder = Dictionary(cards.compactMap { c in c.orderId.map { ($0, c) } },
                                             uniquingKeysWith: { a, _ in a })
                do {
                    let evs = try await JobCardEventsService.forJobCards(cards.map(\.id), boutiqueId: bid)
                    latestEventByCard = Dictionary(evs.map { ($0.jobCardId, $0) },
                                                   uniquingKeysWith: { a, _ in a })
                } catch { failures.insert(.events) }
            } catch { failures.insert(.jobCards) }
        } else { failures.insert(.jobCards) }

        var openAlterations: [Alteration] = []
        if let bid {
            do { openAlterations = try await AlterationsService.listOpen(boutiqueId: bid) }
            catch { failures.insert(.alterations) }
        } else { failures.insert(.alterations) }

        var designingCount = 0
        do {
            let designs = try await DesignsService.list()
            designingCount = designs.filter {
                [.draft, .rendered, .shared_with_customer].contains($0.status)
            }.count
        } catch { failures.insert(.designs) }

        // Shared payments fetch: ONE query for the union candidate set,
        // consumed by both the board's moneyDue and the overdue section.
        var receivedByOrder: [UUID: Double] = [:]
        let nonCancelled = activeOrders.filter { ![.cancelled, .returned].contains($0.status) }
        if !nonCancelled.isEmpty {
            do {
                let sums = try await PaymentsService.capturedSumsForOrders(nonCancelled.map(\.id))
                for p in sums { receivedByOrder[p.order_id, default: 0] += p.amount }
            } catch { failures.insert(.payments) }
        }

        // Overdue section: same candidate filters + threshold as before,
        // now applied to the shared payment sums (behavior unchanged).
        self.paymentsOverdue = failures.contains(.payments)
            ? []
            : filterOverdue(orders: activeOrders, receivedByOrder: receivedByOrder)
        if failures.contains(.payments) { anyFailed = true }

        anyFailed = anyFailed || !failures.isEmpty

        let todayFittings = weekAppts.filter { cal.isDateInToday($0.scheduledAt) && $0.status == .scheduled }.count
        self.board = MorningBoard.build(
            orders: activeOrders,
            jobCardsByOrder: jobCardsByOrder,
            latestEventByCard: latestEventByCard,
            openAlterations: openAlterations,
            designingCount: designingCount,
            todaysAppointments: todayFittings,
            customersById: self.customers,
            receivedByOrder: receivedByOrder,
            failures: failures
        )
        self.ordersById = Dictionary(uniqueKeysWithValues: activeOrders.map { ($0.id, $0) })

        await loadTodayMetrics(orders: activeOrders, customers: allCust, todayStart: todayStart, anyFailed: &anyFailed)

        // dormant: no order in 90 days. Approximation: customers whose updated_at < 90d ago
        // L5 fix: guard the Calendar arithmetic.
        let ninetyAgo = cal.date(byAdding: .day, value: -90, to: now) ?? now
        let recentCustomerIds = Set(activeOrders.filter { $0.createdAt > ninetyAgo }.map(\.customerId))
        self.dormantCustomers = allCust.filter { !recentCustomerIds.contains($0.id) && $0.updatedAt < ninetyAgo }

        self.upcomingDates = dates

        // ── R4a: one new query (the dedup log). Caller's contract — if it
        // fails we build NO drafts, because without dedup the owner
        // re-sends messages already sent. Must run BEFORE loadFailed is
        // assigned so a failure reaches the stale-data banner.
        let todayKey = Formatters.postgresDate.string(from: now)
        let tomorrowKey = Formatters.postgresDate.string(
            from: cal.date(byAdding: .day, value: 1, to: todayStart) ?? now)
        // Drafts are only built when we know the boutique's real name: these
        // messages get SENT, and one signed "— Boutique" is worse than no
        // reminder at all. Same "better silent than wrong" rule as the
        // degraded-input suppressions.
        if let bid, let boutiqueName = self.boutique?.name, !boutiqueName.isEmpty {
            do {
                let logged = try await RemindersService.loggedKeys(
                    boutiqueId: bid, from: todayKey, to: tomorrowKey)
                self.reminderDrafts = ReminderDrafts.build(
                    appointments: weekAppts,
                    orders: activeOrders,
                    jobCardsByOrder: jobCardsByOrder,
                    latestEventByCard: latestEventByCard,
                    receivedByOrder: receivedByOrder,
                    customersById: self.customers,
                    logged: logged,
                    failedInputs: failures,
                    boutiqueName: boutiqueName,
                    today: now)
            } catch {
                self.reminderDrafts = []
                anyFailed = true
            }
        } else {
            self.reminderDrafts = []
            if bid != nil { anyFailed = true }   // name missing ⇒ surface the banner
        }

        self.loadFailed = anyFailed
        self.lastRefreshAt = Date()
    }

    /// R4a — record that a reminder was handled. Optimistic: the row leaves
    /// the list immediately; a failed insert surfaces via ErrorBus and the
    /// draft returns on the next refresh (the log is the source of truth).
    @MainActor
    private func markReminderDone(_ draft: ReminderDrafts.Draft) async {
        guard let bid = BoutiqueContext.shared.boutiqueId else { return }
        reminderDrafts.removeAll { $0.id == draft.id }
        do {
            try await RemindersService.markDone(boutiqueId: bid, kind: draft.kind,
                                                subjectId: draft.subjectId,
                                                forDate: draft.forDate)
        } catch {
            ErrorBus.shared.report("Couldn't save that reminder as done: \(error.localizedDescription)")
        }
    }

    private func fetchUpcomingDates(until: Date) async -> [ImportantDate] {
        // Audit-fix: use Service layer instead of inline SupabaseService.client call.
        // Defense-in-depth boutique_id filter still applied inside the Service.
        guard let bid = BoutiqueContext.shared.boutiqueId else { return [] }
        let all: [ImportantDate] = (try? await ImportantDatesService.listForBoutique(bid)) ?? []
        let now = Date()
        return all.filter { d in
            guard var parsed = Formatters.postgresDate.date(from: d.date) else { return false }
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

    /// "How am I doing today?" — single most-asked question at end of day.
    /// Sums payments captured today (split cash vs UPI), counts new customers
    /// and new orders created since local midnight.
    private func loadTodayMetrics(orders: [Order], customers: [Customer], todayStart: Date, anyFailed: inout Bool) async {
        do {
            // Audit-fix: through Service layer instead of inline SDK call.
            let payments = try await PaymentsService.capturedSinceMidnight()
            var total = 0.0, cash = 0.0, upi = 0.0
            for p in payments {
                total += p.amount
                switch (p.method ?? "").lowercased() {
                case "cash":             cash += p.amount
                case "upi", "razorpay":  upi += p.amount
                default: break
                }
            }
            self.todayRevenue = total
            self.todayCashRevenue = cash
            self.todayUpiRevenue = upi
        } catch {
            anyFailed = true
            self.todayRevenue = 0; self.todayCashRevenue = 0; self.todayUpiRevenue = 0
        }
        self.todayNewCustomers = customers.filter { $0.createdAt >= todayStart }.count
        self.todayNewOrders = orders.filter { $0.createdAt >= todayStart }.count
    }

    /// H5 fix (R2-refactored): overdue = candidate orders (not cancelled/
    /// returned/pending, ≥7 days old) whose received < total. Payment sums
    /// now arrive from load()'s single shared fetch — same candidate filters
    /// and threshold as before, one fewer query.
    private func filterOverdue(orders: [Order], receivedByOrder: [UUID: Double]) -> [Order] {
        orders.filter { ![.cancelled, .returned, .pending].contains($0.status) }
            .filter { (Calendar.current.dateComponents([.day], from: $0.placedAt ?? $0.createdAt, to: Date()).day ?? 0) >= 7 }
            .filter { (receivedByOrder[$0.id] ?? 0) < $0.total }
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
                    Text(value)
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
