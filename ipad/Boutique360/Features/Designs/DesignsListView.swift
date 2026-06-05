import SwiftUI

/// HIG-aligned designs gallery. Grid on iPad with cover thumbnails.
/// PencilKit sketch canvas comes in Plan 4 — for now, designs are text + ref images.
struct DesignsListView: View {
    @EnvironmentObject private var ctx: BoutiqueContext
    @State private var designs: [Design] = []
    @State private var customers: [UUID: Customer] = [:]
    @State private var filter: DesignStatus? = nil
    @State private var search: String = ""
    @State private var loading = false
    @State private var showCreate = false
    @State private var loadError: String?
    @State private var newReferenceDesign: Design?

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    var body: some View {
        Group {
            if loading && designs.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError, designs.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load designs", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(err)
                } actions: {
                    Button("Retry") { Task { await load() } }.buttonStyle(.borderedProminent)
                }
            } else if filtered.isEmpty {
                ContentUnavailableView {
                    Label("No designs yet", systemImage: "pencil.and.scribble")
                } description: {
                    Text("Capture a design concept — measurements, fabric, notes. Sketch canvas arrives with Plan 4.")
                } actions: {
                    Button("New design") { showCreate = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filtered) { d in
                            NavigationLink(value: d) {
                                DesignCard(design: d, customerName: customers[d.customerId ?? UUID()]?.name)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("Designs")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search design, garment, or customer")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Picker("Filter", selection: $filter) {
                    Text("All").tag(DesignStatus?.none)
                    ForEach(DesignStatus.allCases) { Text($0.label).tag(DesignStatus?.some($0)) }
                }
                .pickerStyle(.menu)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showCreate = true } label: { Label("New design", systemImage: "plus") }
                    Button { Task { await startFromPhoto() } } label: {
                        Label("From inspo photo", systemImage: "photo.badge.plus")
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
            }
        }
        .navigationDestination(for: Design.self) { d in
            DesignDetailView(design: d, customerName: customers[d.customerId ?? UUID()]?.name)
        }
        .sheet(item: $newReferenceDesign) { d in
            NavigationStack {
                ReferenceStudioView(design: d) { _ in Task { await load() } }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                DesignFormView(mode: .create) { _ in
                    showCreate = false
                    Task { await load() }
                }
            }
            .presentationDetents([.large])
        }
        .task { await load() }
    }

    private var filtered: [Design] {
        var result = designs
        if let f = filter { result = result.filter { $0.status == f } }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            result = result.filter { d in
                if d.name.lowercased().contains(q) { return true }
                if let g = d.garmentType?.lowercased(), g.contains(q) { return true }
                if let o = d.occasion?.lowercased(), o.contains(q) { return true }
                if let cid = d.customerId, let name = customers[cid]?.name.lowercased(), name.contains(q) { return true }
                return false
            }
        }
        return result
    }

    /// Create a draft Design seeded for a reference photo, then open the studio.
    /// (Reference upload needs a design.id, so the row must exist first.)
    private func startFromPhoto() async {
        guard let bid = ctx.boutiqueId else { return }
        let name = "Inspo — \(Date().formatted(date: .abbreviated, time: .omitted))"
        do {
            let d = try await DesignsService.create(NewDesign(
                boutique_id: bid,
                customer_id: nil,
                name: name,
                status: DesignStatus.draft.rawValue,
                garment_type: nil,
                occasion: nil,
                notes_md: nil,
                created_by_staff_id: nil))
            newReferenceDesign = d
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            designs = try await DesignsService.list()
            let custIds = Set(designs.compactMap(\.customerId))
            if !custIds.isEmpty {
                let all = try await CustomersService.list()
                customers = Dictionary(uniqueKeysWithValues: all.filter { custIds.contains($0.id) }.map { ($0.id, $0) })
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct DesignCard: View {
    let design: Design
    let customerName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(LinearGradient(colors: [Color(.tertiarySystemBackground), Color(.secondarySystemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: iconFor(design.garmentType))
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
            }
            .frame(height: 140)

            VStack(alignment: .leading, spacing: 4) {
                Text(design.name).font(.subheadline.weight(.medium)).lineLimit(1)
                if let n = customerName {
                    Text(n).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(design.status.label)
                        .font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(tint(design.status).opacity(0.15))
                        .foregroundStyle(tint(design.status))
                        .clipShape(Capsule())
                    if let g = design.garmentType {
                        Text(g).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    private func iconFor(_ garment: String?) -> String {
        switch garment?.lowercased() {
        case "blouse": "tshirt"
        case "lehenga": "figure.dress"
        case "saree": "scarf"
        case "kurti": "tshirt"
        case "suit": "person.crop.rectangle.stack"
        default: "scissors"
        }
    }

    private func tint(_ s: DesignStatus) -> Color {
        switch s {
        case .draft: .gray
        case .rendered: .indigo
        case .shared_with_customer: .purple
        case .approved: .blue
        case .in_production: .orange
        case .delivered: .green
        case .archived: .secondary
        }
    }
}
