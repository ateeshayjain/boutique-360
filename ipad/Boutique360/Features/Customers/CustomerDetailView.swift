import SwiftUI

struct CustomerDetailView: View {
    let customer: Customer

    @State private var measurements: [CustomerMeasurement] = []
    @State private var inquiries: [Inquiry] = []
    @State private var loading: Bool = true
    @State private var showAddMeasurement: Bool = false
    @State private var showAddInquiry: Bool = false
    @State private var showEdit: Bool = false
    @State private var refreshTrigger: Int = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                profileHeader
                quickActions
                measurementsSection
                inquiriesSection
            }
            .padding(24)
        }
        .navigationTitle(customer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEdit = true }
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
        .task(id: refreshTrigger) { await load() }
    }

    private var profileHeader: some View {
        HStack(spacing: 20) {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 72, height: 72)
                .overlay(Text(customer.initials).font(.title2.weight(.semibold)).foregroundStyle(Color.accentColor))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(customer.name).font(.title.weight(.semibold))
                    if customer.vipStatus {
                        Image(systemName: "crown.fill").foregroundStyle(.yellow)
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

    private func load() async {
        loading = true
        defer { loading = false }
        async let m = (try? MeasurementsService.listForCustomer(customer.id)) ?? []
        async let i = (try? InquiriesService.list(customerId: customer.id)) ?? []
        self.measurements = await m
        self.inquiries = await i
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
