import SwiftUI

struct CustomersListView: View {
    @State private var customers: [Customer] = []
    @State private var query: String = ""
    @State private var loading: Bool = false
    @State private var loadError: String?
    @State private var showAddSheet: Bool = false

    var body: some View {
        Group {
            if loading && customers.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError, customers.isEmpty {
                ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(err))
            } else if customers.isEmpty {
                ContentUnavailableView {
                    Label("No customers yet", systemImage: "person.crop.circle.badge.plus")
                } description: {
                    Text("Tap + to add your first customer.")
                } actions: {
                    Button("Add customer") { showAddSheet = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List(filteredCustomers) { c in
                    NavigationLink(value: c) {
                        CustomerRow(customer: c)
                    }
                }
                .searchable(text: $query, prompt: "Search by name, phone, email")
                .refreshable { await load() }
            }
        }
        .navigationTitle("Customers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .navigationDestination(for: Customer.self) { c in
            CustomerDetailView(customer: c)
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                CustomerFormView(mode: .create) { _ in
                    showAddSheet = false
                    Task { await load() }
                }
            }
            .presentationDetents([.large])
        }
        .task { await load() }
    }

    private var filteredCustomers: [Customer] {
        guard !query.isEmpty else { return customers }
        let q = query.lowercased()
        return customers.filter {
            $0.name.lowercased().contains(q)
            || ($0.phone ?? "").contains(q)
            || ($0.email ?? "").lowercased().contains(q)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            customers = try await CustomersService.list()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct CustomerRow: View {
    let customer: Customer
    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(Text(customer.initials).font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(customer.name).font(.body.weight(.medium))
                    if customer.vipStatus {
                        Image(systemName: "crown.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(customer.displayPhone).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !customer.tags.isEmpty {
                Text(customer.tags.first ?? "")
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
