import SwiftUI

/// "What should she wear next?" panel — Wave 6.
///
/// Read-only consumer of data the parent already has: customer, recent
/// inquiries (occasion + notes), recent orders (line descriptions ≈
/// garment types). No new DB calls. Single Gemini text round-trip.
struct StyleSuggestionsSheet: View {
    let customer: Customer
    let recentInquiries: [Inquiry]
    let recentOrderItems: [OrderItem]
    let upcomingOccasion: String?

    @Environment(\.dismiss) private var dismiss
    @State private var suggestions: [String] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("For", value: customer.name)
                    if let occ = upcomingOccasion {
                        LabeledContent("Occasion", value: occ)
                    }
                    if !recentOccasions.isEmpty {
                        LabeledContent("Recent occasions",
                                       value: recentOccasions.prefix(3).joined(separator: ", "))
                    }
                    if !recentGarments.isEmpty {
                        LabeledContent("Recent garments",
                                       value: recentGarments.prefix(3).joined(separator: ", "))
                    }
                } header: { Text("Context") }

                Section {
                    if loading {
                        HStack { ProgressView(); Text("Asking Gemini…").foregroundStyle(.secondary) }
                    } else if suggestions.isEmpty {
                        Text("Tap the button below to generate 3 suggestions.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { _, s in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "sparkle")
                                    .foregroundStyle(.purple)
                                Text(s)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    if let err = error {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                } header: { Text("Suggestions") }

                Section {
                    Button {
                        Task { await load() }
                    } label: {
                        HStack {
                            Label(suggestions.isEmpty ? "Generate" : "Regenerate", systemImage: "sparkles")
                            Spacer()
                            if loading { ProgressView() }
                        }
                    }
                    .disabled(loading || !Config.aiEnabled)
                    if !Config.aiEnabled {
                        Label("Add GEMINI_API_KEY to enable.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Suggest a look")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var recentOccasions: [String] {
        recentInquiries.compactMap { $0.occasion }.deduplicatedPreservingOrder()
    }

    private var recentGarments: [String] {
        recentOrderItems
            .compactMap { $0.lineDescription }
            .map { $0.split(separator: " ").prefix(3).joined(separator: " ") } // trim long descriptions
            .deduplicatedPreservingOrder()
    }

    @MainActor
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            suggestions = try await GeminiService.suggestStyles(
                customerName: customer.name,
                recentOccasions: recentOccasions,
                recentGarmentTypes: recentGarments,
                styleNotes: customer.notes,
                upcomingOccasion: upcomingOccasion
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension Array where Element == String {
    func deduplicatedPreservingOrder() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
