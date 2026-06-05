import SwiftUI

/// Embedded in OrderDetailView. Captures multi-round alteration cycles for bridal/bespoke orders.
struct AlterationsSectionView: View {
    let orderId: UUID

    @State private var alterations: [Alteration] = []
    @State private var showAdd = false

    var body: some View {
        Section {
            if alterations.isEmpty {
                Label("No alterations yet", systemImage: "scissors")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(alterations) { a in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: a.status.systemImage)
                                .foregroundStyle(tint(a.status))
                            Text("Round \(a.roundNumber)").font(.subheadline.weight(.medium))
                            Spacer()
                            Menu {
                                ForEach(AlterationStatus.allCases) { s in
                                    if s != a.status {
                                        Button(s.label) {
                                            Task {
                                                _ = try? await AlterationsService.updateStatus(a.id, to: s, completed: s == .completed)
                                                await load()
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Text(a.status.label).font(.caption).foregroundStyle(tint(a.status))
                            }
                        }
                        Text(a.requestNotes).font(.caption)
                        if let td = a.targetDate {
                            Label("Target \(td)", systemImage: "calendar")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Button {
                showAdd = true
            } label: {
                Label("Request alteration", systemImage: "plus")
            }
        } header: {
            Text("Alterations")
        }
        .task { await load() }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                AlterationFormView(orderId: orderId) {
                    showAdd = false
                    Task { await load() }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func load() async {
        alterations = (try? await AlterationsService.listForOrder(orderId)) ?? []
    }

    private func tint(_ s: AlterationStatus) -> Color {
        switch s {
        case .requested: .orange
        case .in_progress: .blue
        case .completed: .green
        case .cancelled: .gray
        }
    }
}

struct AlterationFormView: View {
    let orderId: UUID
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext

    @State private var notes: String = ""
    @State private var hasTarget = true
    @State private var targetDate = Calendar.current.date(byAdding: .day, value: 5, to: Date()) ?? Date()
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Request") {
                TextEditor(text: $notes).frame(minHeight: 100)
                Text("Capture what needs to be altered, in the customer's words. Internal notes can be added later.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("Target date") {
                Toggle("Set target date", isOn: $hasTarget)
                if hasTarget {
                    DatePicker("Ready by", selection: $targetDate, in: Date()..., displayedComponents: .date)
                }
            }
            if let err = error {
                Section { Text(err).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle("New alteration")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(saving || notes.isEmpty || ctx.boutiqueId == nil)
            }
        }
    }

    private func save() async {
        guard let bid = ctx.boutiqueId else { return }
        saving = true; defer { saving = false }
        // M1 sweep: use central Formatters.postgresDate
        do {
            let round = (try? await AlterationsService.nextRoundNumber(forOrder: orderId)) ?? 1
            _ = try await AlterationsService.create(NewAlteration(
                boutique_id: bid, order_id: orderId, round_number: round,
                request_notes: notes,
                internal_notes: nil,
                target_date: hasTarget ? Formatters.postgresDate.string(from: targetDate) : nil
            ))
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
