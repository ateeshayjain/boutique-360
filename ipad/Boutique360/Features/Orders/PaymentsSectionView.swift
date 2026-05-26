import SwiftUI

/// Advance + balance payment tracking embedded in OrderDetailView.
/// Common bridal pattern: 40% advance on order, 60% on delivery.
struct PaymentsSectionView: View {
    let order: Order

    @State private var payments: [PaymentRow] = []
    @State private var showAdd = false
    @State private var defaultAmount: Double = 0

    struct PaymentRow: Identifiable, Decodable {
        let id: UUID
        let amount: Double
        let status: String
        let method: String?
        let captured_at: Date?
        let created_at: Date
    }

    var body: some View {
        Section {
            LabeledContent("Order total", value: format(order.total))
            LabeledContent("Received", value: format(receivedTotal))
            LabeledContent("Balance due") {
                Text(format(max(order.total - receivedTotal, 0)))
                    .foregroundStyle(balanceDue > 0 ? .orange : .green)
                    .fontWeight(.semibold)
            }

            if !payments.isEmpty {
                ForEach(payments) { p in
                    HStack {
                        Image(systemName: p.status == "captured" ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(p.status == "captured" ? .green : .secondary)
                        VStack(alignment: .leading) {
                            Text(format(p.amount)).font(.subheadline.weight(.medium))
                            HStack(spacing: 6) {
                                if let m = p.method { Text(m.uppercased()).font(.caption2) }
                                Text("·").foregroundStyle(.tertiary)
                                Text((p.captured_at ?? p.created_at).formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Button {
                defaultAmount = max(order.total - receivedTotal, 0)
                showAdd = true
            } label: {
                Label("Record payment", systemImage: "plus.circle")
            }
            .disabled(balanceDue <= 0)
        } header: {
            Text("Payments")
        }
        .task { await load() }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                RecordPaymentView(order: order, suggestedAmount: defaultAmount) {
                    showAdd = false
                    Task { await load() }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var receivedTotal: Double {
        payments.filter { $0.status == "captured" }.reduce(0) { $0 + $1.amount }
    }
    private var balanceDue: Double { order.total - receivedTotal }

    private func format(_ v: Double) -> String { Formatters.inr(v) }

    private func load() async {
        do {
            let rows: [PaymentRow] = try await SupabaseService.client.from("payments")
                .select("id,amount,status,method,captured_at,created_at")
                .eq("order_id", value: order.id)
                .order("created_at", ascending: true)
                .execute()
                .value
            self.payments = rows
        } catch { payments = [] }
    }
}

struct RecordPaymentView: View {
    let order: Order
    let suggestedAmount: Double
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext

    @State private var amountText: String = ""
    @State private var method: String = "upi"
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Amount") {
                LabeledContent("Suggested", value: formatINR(suggestedAmount))
                LabeledContent("Amount") {
                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section("Method") {
                Picker("Method", selection: $method) {
                    Label("UPI", systemImage: "qrcode").tag("upi")
                    Label("Cash", systemImage: "indianrupeesign").tag("cash")
                    Label("Card", systemImage: "creditcard").tag("card")
                    Label("Net banking", systemImage: "building.columns").tag("netbanking")
                    Label("Wallet", systemImage: "wallet.pass").tag("wallet")
                    Label("Bank transfer", systemImage: "arrow.left.arrow.right").tag("bank_transfer")
                }
                .pickerStyle(.menu)
            }
            if let err = error {
                Section { Text(err).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle("Record payment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving…" : "Save") { Task { await save() } }
                    .disabled(saving || (Double(amountText) ?? 0) <= 0)
            }
        }
        .onAppear {
            if amountText.isEmpty, suggestedAmount > 0 {
                amountText = String(Int(suggestedAmount))
            }
        }
    }

    private func formatINR(_ v: Double) -> String { Formatters.inr(v) }

    private func save() async {
        guard let bid = ctx.boutiqueId, let amount = Double(amountText), amount > 0 else { return }
        saving = true; defer { saving = false }
        struct NewPayment: Encodable {
            let boutique_id: UUID
            let order_id: UUID
            let amount: Double
            let status: String
            let method: String
            let captured_at: String
        }
        do {
            _ = try await SupabaseService.client.from("payments")
                .insert(NewPayment(
                    boutique_id: bid, order_id: order.id, amount: amount,
                    status: "captured", method: method,
                    captured_at: ISO8601DateFormatter().string(from: Date())
                ))
                .execute()
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
