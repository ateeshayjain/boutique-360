import SwiftUI

struct InquiryFormView: View {
    let customerId: UUID
    let onSaved: (Inquiry) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext

    @State private var occasion: String = ""
    @State private var eventDate: Date = Date()
    @State private var hasEventDate: Bool = false
    @State private var budget: String = ""
    @State private var notes: String = ""
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        Form {
            Section("What is this for?") {
                TextField("Occasion (Wedding, Reception, Birthday…)", text: $occasion)
                Toggle("Event date set", isOn: $hasEventDate)
                if hasEventDate {
                    DatePicker("Event date", selection: $eventDate, in: Date()..., displayedComponents: .date)
                }
                TextField("Budget range (e.g. ₹25k-50k)", text: $budget)
            }
            Section("Notes") {
                TextEditor(text: $notes).frame(minHeight: 100)
            }
            if let err = saveError {
                Section { Text(err).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle("New inquiry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(saving || ctx.boutiqueId == nil)
            }
        }
    }

    private func save() async {
        guard let bid = ctx.boutiqueId else { saveError = "Boutique context unavailable"; return }
        saving = true; defer { saving = false }
        // H5/M7 fix: use central Formatters.postgresDate (POSIX locale + Asia/Kolkata timezone).
        let dateString: String? = hasEventDate ? Formatters.postgresDate.string(from: eventDate) : nil
        do {
            // L6 fix: async sequence-RPC inquiry number instead of Int.random.
            let inquiryNumber = try await InquiriesService.generateInquiryNumber(boutiqueId: bid)
            let created = try await InquiriesService.create(NewInquiry(
                boutique_id: bid,
                inquiry_number: inquiryNumber,
                customer_id: customerId,
                occasion: occasion.isEmpty ? nil : occasion,
                event_date: dateString,
                budget_range: budget.isEmpty ? nil : budget,
                notes: notes.isEmpty ? nil : notes,
                source: "ipad"
            ))
            onSaved(created)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
