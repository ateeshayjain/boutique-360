import SwiftUI

/// Presented when an action needs a customer but the Design has none linked
/// (e.g. starting a virtual try-on from a reference-photo Design). Returns the
/// picked customer to the caller, which attaches it to the Design.
struct CustomerLinkSheet: View {
    let onPick: (Customer) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var customers: [Customer] = []
    @State private var search = ""
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading && customers.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = loadError, customers.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn't load customers", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(err)
                    } actions: {
                        Button("Retry") { Task { await load() } }.buttonStyle(.borderedProminent)
                    }
                } else if customers.isEmpty {
                    ContentUnavailableView(
                        "No customers",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Add a customer first, then link this design to them.")
                    )
                } else {
                    List(customers) { c in
                        Button {
                            onPick(c)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).font(.body)
                                if let p = c.phone { Text(p).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .accessibilityLabel("Link \(c.name)")
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Link a customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            // Server-side search (debounced by the user's typing cadence).
            .searchable(text: $search, prompt: "Search by name or phone")
            .onChange(of: search) { _, _ in Task { await load() } }
            .task { await load() }
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            let q = search.trimmingCharacters(in: .whitespaces)
            customers = try await CustomersService.list(searchQuery: q.isEmpty ? nil : q)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
