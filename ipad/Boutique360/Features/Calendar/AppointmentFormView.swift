import SwiftUI

struct AppointmentFormView: View {
    let initialDate: Date
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext

    @State private var customers: [Customer] = []
    @State private var orders: [Order] = []
    @State private var customerId: UUID?
    @State private var orderId: UUID?
    @State private var type: AppointmentType = .fitting
    @State private var date: Date
    @State private var duration: Int = 30
    @State private var notes: String = ""
    @State private var saving = false
    @State private var error: String?

    init(initialDate: Date, onSaved: @escaping () -> Void) {
        self.initialDate = initialDate
        self.onSaved = onSaved
        let cal = Calendar.current
        let d = cal.date(bySettingHour: 11, minute: 0, second: 0, of: initialDate) ?? initialDate
        _date = State(initialValue: d)
    }

    var body: some View {
        Form {
            Section("Who & what") {
                Picker("Customer", selection: $customerId) {
                    Text("Select").tag(UUID?.none)
                    ForEach(customers) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                Picker("Type", selection: $type) {
                    ForEach(AppointmentType.allCases) {
                        Label($0.label, systemImage: $0.systemImage).tag($0)
                    }
                }
                if let cid = customerId, !orders.filter({ $0.customerId == cid }).isEmpty {
                    Picker("Linked order (optional)", selection: $orderId) {
                        Text("None").tag(UUID?.none)
                        ForEach(orders.filter { $0.customerId == cid }) {
                            Text($0.orderNumber).tag(UUID?.some($0.id))
                        }
                    }
                }
            }
            Section("When") {
                DatePicker("Date & time", selection: $date)
                Stepper(value: $duration, in: 15...240, step: 15) {
                    LabeledContent("Duration", value: "\(duration) min")
                }
            }
            Section("Notes") {
                TextEditor(text: $notes).frame(minHeight: 80)
            }
            if let err = error {
                Section { Text(err).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle("New appointment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(saving || customerId == nil || ctx.boutiqueId == nil)
            }
        }
        .task {
            async let custs: [Customer] = (try? await CustomersService.list()) ?? []
            async let ords: [Order] = (try? await OrdersService.list()) ?? []
            self.customers = await custs
            self.orders = await ords
        }
    }

    private func save() async {
        guard let bid = ctx.boutiqueId, let cid = customerId else { return }
        saving = true; defer { saving = false }
        do {
            _ = try await AppointmentsService.create(NewAppointment(
                boutique_id: bid, customer_id: cid, order_id: orderId,
                type: type.rawValue,
                scheduled_at: ISO8601DateFormatter().string(from: date),
                duration_minutes: duration,
                notes: notes.isEmpty ? nil : notes
            ))
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
