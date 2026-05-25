import SwiftUI

struct MeasurementFormView: View {
    let customerId: UUID
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext

    @State private var garment: GarmentType = .blouse
    @State private var values: [String: String] = [:]
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        Form {
            Section {
                Picker("Garment", selection: $garment) {
                    ForEach(GarmentType.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: garment) { _, _ in values = [:] }
            }

            Section("Measurements (inches)") {
                ForEach(garment.fields, id: \.self) { field in
                    HStack {
                        Text(field.replacingOccurrences(of: "_", with: " ").capitalized)
                        Spacer()
                        TextField("0.0", text: Binding(
                            get: { values[field] ?? "" },
                            set: { values[field] = $0 }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    }
                }
            }

            if let err = saveError {
                Section { Text(err).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle("New measurement")
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
        let json = values.reduce(into: [String: Double]()) { acc, kv in
            if let d = Double(kv.value), d > 0 { acc[kv.key] = d }
        }
        guard !json.isEmpty else { saveError = "Enter at least one measurement"; return }
        do {
            _ = try await MeasurementsService.create(NewMeasurement(
                boutique_id: bid, customer_id: customerId,
                garment_type: garment.rawValue, measurements_json: json
            ))
            onSaved()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
