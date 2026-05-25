import SwiftUI

struct DesignFormView: View {
    enum Mode { case create, edit(Design) }
    let mode: Mode
    let onSaved: (Design) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext

    @State private var name: String = ""
    @State private var garmentType: String = "Blouse"
    @State private var occasion: String = ""
    @State private var notes: String = ""
    @State private var selectedCustomerId: UUID?
    @State private var customers: [Customer] = []
    @State private var saving = false
    @State private var error: String?

    private let garments = ["Blouse", "Lehenga", "Saree", "Kurti", "Suit", "Dress", "Gown", "Other"]

    var body: some View {
        Form {
            Section("About") {
                TextField("Design name", text: $name)
                Picker("Garment", selection: $garmentType) {
                    ForEach(garments, id: \.self) { Text($0).tag($0) }
                }
                TextField("Occasion (Wedding, Festive, Sangeet…)", text: $occasion)
            }

            Section("Customer (optional)") {
                Picker("Link to customer", selection: $selectedCustomerId) {
                    Text("None (library concept)").tag(UUID?.none)
                    ForEach(customers) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }

            Section("Notes") {
                TextEditor(text: $notes).frame(minHeight: 120)
            }

            if let err = error {
                Section { Text(err).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle(isEditing ? "Edit design" : "New design")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(saving || name.isEmpty || ctx.boutiqueId == nil)
            }
        }
        .task { await load() }
    }

    private var isEditing: Bool { if case .edit = mode { return true } else { return false } }

    private func load() async {
        customers = (try? await CustomersService.list()) ?? []
        if case .edit(let d) = mode {
            name = d.name
            garmentType = d.garmentType ?? "Other"
            occasion = d.occasion ?? ""
            notes = d.notesMd ?? ""
            selectedCustomerId = d.customerId
        }
    }

    private func save() async {
        guard let bid = ctx.boutiqueId else { return }
        saving = true; defer { saving = false }
        do {
            switch mode {
            case .create:
                let created = try await DesignsService.create(NewDesign(
                    boutique_id: bid,
                    customer_id: selectedCustomerId,
                    name: name,
                    status: DesignStatus.draft.rawValue,
                    garment_type: garmentType,
                    occasion: occasion.isEmpty ? nil : occasion,
                    notes_md: notes.isEmpty ? nil : notes,
                    created_by_staff_id: nil
                ))
                onSaved(created)
                dismiss()
            case .edit(let d):
                let patch = DesignsService.DesignPatch(
                    name: name,
                    status: nil,
                    garment_type: garmentType,
                    occasion: occasion.isEmpty ? nil : occasion,
                    notes_md: notes.isEmpty ? nil : notes,
                    customer_id: selectedCustomerId
                )
                let updated = try await DesignsService.update(d.id, patch: patch)
                onSaved(updated)
                dismiss()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
