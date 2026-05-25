import SwiftUI

struct OrdersListView: View {
    @State private var orders: [Order] = []
    @State private var customers: [UUID: Customer] = [:]
    @State private var filter: OrderStatus? = nil       // nil = "All"
    @State private var loading: Bool = false
    @State private var showCreate: Bool = false
    @State private var loadError: String?

    var body: some View {
        Group {
            if loading && orders.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if orders.isEmpty {
                ContentUnavailableView {
                    Label("No orders yet", systemImage: "bag.badge.plus")
                } description: {
                    Text("Tap + to create your first order.")
                } actions: {
                    Button("New order") { showCreate = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    Section {
                        ForEach(filteredOrders) { o in
                            NavigationLink(value: o) {
                                OrderRow(order: o, customerName: customers[o.customerId]?.name ?? "—")
                            }
                            .swipeActions(edge: .trailing) {
                                ForEach(o.status.nextOptions.prefix(1), id: \.self) { next in
                                    Button {
                                        Task { await advance(o, to: next) }
                                    } label: {
                                        Label("Mark \(next.label)", systemImage: next.systemImage)
                                    }
                                    .tint(tintFor(next))
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load() }
            }
        }
        .navigationTitle("Orders")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Picker("Filter", selection: $filter) {
                    Text("All").tag(OrderStatus?.none)
                    ForEach(OrderStatus.allCases) { s in
                        Label(s.label, systemImage: s.systemImage).tag(OrderStatus?.some(s))
                    }
                }
                .pickerStyle(.menu)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreate = true
                } label: {
                    Label("New order", systemImage: "plus")
                }
            }
        }
        .navigationDestination(for: Order.self) { o in
            OrderDetailView(order: o, customerName: customers[o.customerId]?.name)
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                OrderCreateView { _ in
                    showCreate = false
                    Task { await load() }
                }
            }
            .presentationDetents([.large])
        }
        .task { await load() }
    }

    private var filteredOrders: [Order] {
        guard let f = filter else { return orders }
        return orders.filter { $0.status == f }
    }

    private func advance(_ order: Order, to status: OrderStatus) async {
        do {
            _ = try await OrdersService.updateStatus(order.id, to: status)
            await load()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            orders = try await OrdersService.list()
            let custIds = Set(orders.map(\.customerId))
            if !custIds.isEmpty {
                let all = try await CustomersService.list()
                customers = Dictionary(uniqueKeysWithValues: all.filter { custIds.contains($0.id) }.map { ($0.id, $0) })
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func tintFor(_ s: OrderStatus) -> Color {
        switch s {
        case .pending: .orange
        case .confirmed: .blue
        case .packed: .indigo
        case .shipped: .purple
        case .delivered: .green
        case .cancelled: .gray
        case .returned: .red
        }
    }
}

private struct OrderRow: View {
    let order: Order
    let customerName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: order.status.systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(customerName).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(order.orderNumber).font(.caption).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(order.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatINR(order.total)).font(.body.weight(.semibold)).monospacedDigit()
                Text(order.status.label).font(.caption2).foregroundStyle(tint)
            }
        }
        .padding(.vertical, 4)
    }

    private var tint: Color {
        switch order.status {
        case .pending: .orange; case .confirmed: .blue; case .packed: .indigo
        case .shipped: .purple; case .delivered: .green
        case .cancelled: .gray; case .returned: .red
        }
    }

    private func formatINR(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "INR"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "₹\(Int(v))"
    }
}
