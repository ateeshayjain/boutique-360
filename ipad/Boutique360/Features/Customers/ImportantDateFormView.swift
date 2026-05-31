import SwiftUI

struct ImportantDateFormView: View {
    let customerId: UUID
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext

    @State private var occasion: String = "Anniversary"
    @State private var date: Date = Date()
    @State private var recurring: Bool = true
    @State private var reminderDays: Int = 7
    @State private var saving = false
    @State private var error: String?

    private let presets = ["Anniversary", "Birthday", "Kids birthday", "Sangeet", "Festival", "Other"]

    var body: some View {
        Form {
            Section("Occasion") {
                Picker("Type", selection: $occasion) {
                    ForEach(presets, id: \.self) { Text($0).tag($0) }
                }
                if occasion == "Other" {
                    TextField("Custom occasion", text: $occasion)
                }
            }
            Section("When") {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Toggle("Recurring (yearly)", isOn: $recurring)
                Stepper(value: $reminderDays, in: 0...60) {
                    LabeledContent("Remind", value: "\(reminderDays) days before")
                }
            }
            if let err = error {
                Section { Text(err).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle("Important date")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(saving || occasion.isEmpty || ctx.boutiqueId == nil)
            }
        }
    }

    private func save() async {
        guard let bid = ctx.boutiqueId else { return }
        saving = true; defer { saving = false }
        // M1 sweep: use central Formatters.postgresDate
        do {
            _ = try await ImportantDatesService.create(NewImportantDate(
                boutique_id: bid, customer_id: customerId,
                occasion: occasion == "Other" ? "Other" : occasion,
                date: Formatters.postgresDate.string(from: date),
                recurring: recurring,
                reminder_days_before: reminderDays
            ))
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
