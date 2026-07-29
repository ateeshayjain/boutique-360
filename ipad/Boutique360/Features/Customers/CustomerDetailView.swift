import SwiftUI

struct CustomerDetailView: View {
    @EnvironmentObject private var roles: StaffRoleContext
    let customer: Customer

    @State private var measurements: [CustomerMeasurement] = []
    @State private var inquiries: [Inquiry] = []
    @State private var orders: [Order] = []
    @State private var profile: CustomerProfile?
    @State private var dates: [ImportantDate] = []
    @State private var timeline: [CustomerTimelineEvent] = []
    @State private var showFullTimeline: Bool = false
    @State private var loading: Bool = true
    @State private var showAddMeasurement: Bool = false
    @State private var showAddInquiry: Bool = false
    @State private var showAddDate: Bool = false
    @State private var showEditStyle: Bool = false
    @State private var showEdit: Bool = false
    @State private var showSuggestStyles: Bool = false
    @State private var refreshTrigger: Int = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                profileHeader
                quickActions
                journeySection
                styleSection
                datesSection
                // Wave 2: per-customer spend report. Pure-render over the
                // already-loaded `orders` array — no extra DB call.
                CustomerSpendSummaryView(orders: orders)
                ordersSection
                measurementsSection
                inquiriesSection
            }
            .padding(24)
        }
        .navigationTitle(customer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showEdit = true } label: { Label("Edit details", systemImage: "pencil") }
                    Button { showEditStyle = true } label: { Label("Edit style profile", systemImage: "person.crop.rectangle") }
                    Button { showAddDate = true } label: { Label("Add important date", systemImage: "calendar.badge.plus") }
                    Button { showAddMeasurement = true } label: { Label("New measurement", systemImage: "ruler") }
                    Button { showAddInquiry = true } label: { Label("New inquiry", systemImage: "envelope.badge.fill") }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                CustomerFormView(mode: .edit(customer)) { _ in
                    showEdit = false
                    refreshTrigger += 1
                }
            }
        }
        .sheet(isPresented: $showAddMeasurement) {
            NavigationStack {
                MeasurementFormView(customerId: customer.id) {
                    showAddMeasurement = false
                    Task { await load() }
                }
            }
        }
        .sheet(isPresented: $showAddInquiry) {
            NavigationStack {
                InquiryFormView(customerId: customer.id) { _ in
                    showAddInquiry = false
                    Task { await load() }
                }
            }
        }
        .sheet(isPresented: $showEditStyle) {
            NavigationStack {
                CustomerStyleProfileView(customer: customer) {
                    showEditStyle = false
                    Task { await load() }
                }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showAddDate) {
            NavigationStack {
                ImportantDateFormView(customerId: customer.id) {
                    showAddDate = false
                    Task { await load() }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSuggestStyles) {
            // Wave 6: Pass the inquiries we've already loaded as the
            // history signal; upcomingOccasion = nearest important date's
            // occasion if present (best free signal we have).
            StyleSuggestionsSheet(
                customer: customer,
                recentInquiries: inquiries,
                recentOrderItems: [],   // not loaded at this level — skip for now
                upcomingOccasion: dates.sorted(by: { $0.date < $1.date }).first?.occasion
            )
            .presentationDetents([.medium, .large])
        }
        .task(id: refreshTrigger) { await load() }
    }

    private var profileHeader: some View {
        HStack(spacing: 20) {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 72, height: 72)
                .overlay(
                    Text(customer.initials)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(customer.name)
                        .font(.title.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    if customer.vipStatus {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("VIP customer")
                    }
                }
                if let p = customer.phone { Label(p, systemImage: "phone").font(.subheadline) }
                if let e = customer.email { Label(e, systemImage: "envelope").font(.subheadline) }
                if !customer.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(customer.tags, id: \.self) { tag in
                            Text(tag).font(.caption2)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color(.tertiarySystemBackground))
                                .clipShape(Capsule())
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Tags: \(customer.tags.joined(separator: ", "))")
                }
            }
            Spacer()
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button { showAddMeasurement = true } label: {
                Label("Measurements", systemImage: "ruler")
            }.buttonStyle(.bordered)
            Button { showAddInquiry = true } label: {
                Label("New inquiry", systemImage: "envelope.badge.fill")
            }.buttonStyle(.borderedProminent)
            // Wave 6: Gemini-powered next-look suggestions.
            // Hidden when AI is off — pointless without a key.
            if Config.aiEnabled {
                Button { showSuggestStyles = true } label: {
                    Label("Suggest a look", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .tint(.purple)
            }
            if customer.consentWhatsapp, customer.whatsappTarget != nil {
                Button {
                    WhatsAppShareHelper.open(
                        phone: customer.whatsappTarget,
                        message: "Namaste \(customer.name.split(separator: " ").first.map(String.init) ?? customer.name)! "
                    )
                } label: {
                    Label("WhatsApp", systemImage: "message.fill")
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }
        }
    }

    /// Unified chronological feed — replaces the "where is this customer in
    /// their journey?" question with a single answer. Shows the latest 6
    /// events inline; tap "See all" for the full history sheet.
    private var journeySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Journey").font(.headline)
                Spacer()
                if timeline.count > 6 {
                    Button("See all (\(timeline.count))") { showFullTimeline = true }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }
            if loading && timeline.isEmpty {
                ProgressView()
            } else if timeline.isEmpty {
                Text("Activity will appear here as inquiries, designs, orders, and payments happen.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                GroupBox {
                    VStack(spacing: 0) {
                        ForEach(Array(timeline.prefix(6))) { ev in
                            timelineRow(ev)
                            if ev.id != timeline.prefix(6).last?.id {
                                Divider().padding(.leading, 36)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showFullTimeline) {
            NavigationStack {
                List(timeline) { ev in
                    timelineRow(ev).padding(.vertical, 4)
                }
                .listStyle(.plain)
                .navigationTitle("\(customer.name) — full journey")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showFullTimeline = false }
                    }
                }
            }
        }
    }

    private func timelineRow(_ ev: CustomerTimelineEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ev.kind.systemImage)
                .foregroundStyle(ev.kind.tint)
                .frame(width: 24, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ev.title)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let s = ev.subtitle {
                    Text(s).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(ev.at.formatted(.relative(presentation: .named)))
                .font(.caption2).foregroundStyle(.tertiary)
                .accessibilityLabel(ev.at.formatted(date: .abbreviated, time: .shortened))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var ordersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Orders").font(.headline)
            if loading && orders.isEmpty {
                ProgressView()
            } else if orders.isEmpty {
                Text("No orders yet. Convert an inquiry to create one.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(orders) { o in
                    NavigationLink(value: o) {
                        orderRow(o)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationDestination(for: Order.self) { o in
            OrderDetailView(order: o, customerName: customer.name)
        }
    }

    private func orderRow(_ o: Order) -> some View {
        HStack(spacing: 12) {
            Image(systemName: o.status.systemImage)
                .foregroundStyle(orderColor(o.status))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(o.orderNumber).font(.subheadline.weight(.medium))
                Text(o.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                // R4b — per-order value is the same data the spend panel
                // aggregates, so it rides on the same surface.
                if RolePolicy.canSee(.spendPanel, role: roles.role) {
                    Text(Formatters.inr(o.total))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                Text(o.status.label)
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(orderColor(o.status).opacity(0.18))
                    .foregroundStyle(orderColor(o.status))
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func orderColor(_ s: OrderStatus) -> Color {
        switch s {
        case .pending:   .orange
        case .confirmed: .blue
        case .packed:    .indigo
        case .shipped:   .purple
        case .delivered: .green
        case .cancelled: .gray
        case .returned:  .red
        }
    }

    private var measurementsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Measurements").font(.headline)
            if loading && measurements.isEmpty {
                ProgressView()
            } else if measurements.isEmpty {
                Text("None yet. Tap Measurements above to add.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(measurements) { m in
                    measurementCard(m)
                }
            }
        }
    }

    private func measurementCard(_ m: CustomerMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(m.garmentType.capitalized).font(.subheadline.weight(.medium))
                Spacer()
                Text(m.takenAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            let pairs = m.measurementsJson.sorted { $0.key < $1.key }
            FlowLayout(spacing: 8) {
                ForEach(pairs, id: \.key) { k, v in
                    Text("\(k.replacingOccurrences(of: "_", with: " ")): \(String(format: "%.1f", v))\"")
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var inquiriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Inquiries").font(.headline)
            if inquiries.isEmpty {
                Text("None yet. Tap New inquiry above.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(inquiries) { i in
                    inquiryRow(i)
                }
            }
        }
    }

    private func inquiryRow(_ i: Inquiry) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(i.inquiryNumber).font(.subheadline.weight(.medium))
                if let o = i.occasion { Text(o).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            StatusBadge(status: i.status)
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Style profile").font(.headline)
                Spacer()
                Button("Edit") { showEditStyle = true }.font(.caption).buttonStyle(.borderless)
            }
            if let p = profile {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        if let persona = p.stylePersona.flatMap(StylePersona.init(rawValue:)) {
                            Label(persona.label, systemImage: persona.systemImage)
                                .font(.subheadline.weight(.medium))
                        }
                        HStack(spacing: 16) {
                            if let bt = p.bodyType { profileChip("Body", bt.capitalized) }
                            if let st = p.skinTone { profileChip("Skin", st.capitalized) }
                            if let bb = p.budgetBand { profileChip("Budget", bb.capitalized) }
                        }
                        if !p.colorPalette.isEmpty {
                            metaRow("Colors", p.colorPalette.joined(separator: ", "))
                        }
                        if !p.fabricPreferences.isEmpty {
                            metaRow("Loves", p.fabricPreferences.joined(separator: ", "))
                        }
                        if !p.avoidFabrics.isEmpty {
                            metaRow("Avoid", p.avoidFabrics.joined(separator: ", "))
                        }
                        if let notes = p.styleNotesMd, !notes.isEmpty {
                            Text(notes).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("Capture style preferences to power AI recommendations and personalized outreach.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func profileChip(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline)
        }
    }
    private func metaRow(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.subheadline)
        }
    }

    private var datesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Important dates").font(.headline)
                Spacer()
                Button {
                    showAddDate = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add important date")
            }
            if dates.isEmpty {
                Text("Anniversaries, birthdays, festivals to remember.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(dates) { d in
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading) {
                            Text(d.occasion).font(.subheadline.weight(.medium))
                            Text(d.date).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if d.recurring {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        async let m = (try? MeasurementsService.listForCustomer(customer.id)) ?? []
        async let i = (try? InquiriesService.list(customerId: customer.id)) ?? []
        async let o = (try? OrdersService.list(customerId: customer.id)) ?? []
        async let p = (try? CustomerProfilesService.get(customerId: customer.id)) ?? nil
        async let d = (try? ImportantDatesService.listForCustomer(customer.id)) ?? []
        self.measurements = await m
        self.inquiries = await i
        self.orders = await o
        self.profile = await p
        self.dates = await d
        // Build timeline AFTER the source data is hydrated. The aggregator
        // re-queries authoritative sources so a stale local cache can't
        // produce an inconsistent feed.
        self.timeline = await CustomerTimelineService.fetch(customerId: customer.id, customer: customer)
    }
}

struct StatusBadge: View {
    let status: InquiryStatus
    var body: some View {
        Text(status.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    private var color: Color {
        switch status {
        case .new: .blue
        case .consulting: .indigo
        case .measurements: .purple
        case .quoted: .orange
        case .confirmed: .green
        case .in_production: .yellow
        case .ready: .mint
        case .delivered: .gray
        case .lost: .red
        }
    }
}

// Minimal FlowLayout for chip-like measurement display.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxWidth { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxWidth, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
