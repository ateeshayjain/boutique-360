import SwiftUI

/// Advance + balance payment tracking embedded in OrderDetailView.
/// Common bridal pattern: 40% advance on order, 60% on delivery.
struct PaymentsSectionView: View {
    let order: Order
    var customer: Customer? = nil
    @EnvironmentObject private var ctx: BoutiqueContext

    @State private var payments: [PaymentRow] = []
    @State private var showAdd = false
    @State private var defaultAmount: Double = 0
    @State private var loadError: String?
    @State private var loading = false

    typealias PaymentRow = PaymentsService.OrderHistoryRow

    var body: some View {
        Section {
            if let err = loadError {
                // B1 fix: NEVER show a balance derived from a failed fetch — that
                // tricks the owner into double-charging the customer. Surface the
                // failure prominently and block the Record-payment button below.
                Label("Couldn't load payment history — \(err). Retry before recording new payments.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Button("Retry") { Task { await load() } }
                    .buttonStyle(.bordered)
            }
            LabeledContent("Order total", value: format(order.total))
            LabeledContent("Received", value: loadError == nil ? format(receivedTotal) : "—")
            LabeledContent("Balance due") {
                // HIG audit fix: SF symbol prefix gives a non-color cue (works for
                // color-blind users and in grayscale). Color reinforces but doesn't carry.
                HStack(spacing: Spacing.micro) {
                    if loadError == nil {
                        Image(systemName: balanceDue > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(balanceDue > 0 ? .orange : .green)
                            .accessibilityHidden(true)
                    }
                    Text(loadError == nil ? format(max(order.total - receivedTotal, 0)) : "—")
                        .foregroundStyle(balanceDue > 0 ? .orange : .green)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(balanceDue > 0
                    ? "Balance due \(format(max(order.total - receivedTotal, 0)))"
                    : "Fully paid")
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
            // Block recording while load is failed — receivedTotal would be 0
            // and the suggested amount would be the full order total.
            .disabled(balanceDue <= 0 || loadError != nil)

            if balanceDue > 0, let cust = customer, cust.consentWhatsapp, cust.phone != nil {
                Button {
                    let firstName = cust.name.split(separator: " ").first.map(String.init) ?? cust.name
                    let boutiqueName = ctx.boutique?.name ?? "Boutique"
                    let msg = "Hi \(firstName), a gentle reminder — balance of \(format(balanceDue)) is pending on order \(order.orderNumber). UPI / card / cash all accepted. Thank you! — \(boutiqueName)"
                    WhatsAppShareHelper.open(phone: cust.phone, message: msg)
                } label: {
                    Label("Send payment reminder on WhatsApp", systemImage: "message.fill")
                        .foregroundStyle(.green)
                }
            }
        } header: {
            Text("Payments")
        }
        .task { await load() }
        // H3 fix: refresh when the parent order changes status (could affect
        // payment-due interpretation downstream) or returns from foreground.
        .onReceive(NotificationCenter.default.publisher(for: .orderDidChange)) { _ in
            Task { await load() }
        }
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
    /// L7 fix: round to paise to prevent floating-point drift surfacing a
    /// "₹0.000001 balance due" WhatsApp reminder on a fully-paid order.
    /// Uses the shared `Money.roundedToPaise` helper (testable + reusable).
    private var balanceDue: Double {
        Money.roundedToPaise(order.total - receivedTotal)
    }

    private func format(_ v: Double) -> String { Formatters.inr(v) }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            // Audit-fix: through Service layer.
            self.payments = try await PaymentsService.historyForOrder(order.id)
            self.loadError = nil
        } catch {
            // B1 fix: surface the error instead of silently emptying the list.
            // The view binds `loadError` to disable Record-payment + show banner.
            self.loadError = error.localizedDescription
        }
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
        do {
            // Audit-fix: through Service layer.
            try await PaymentsService.record(.init(
                boutique_id: bid, order_id: order.id, amount: amount,
                status: "captured", method: method,
                captured_at: Formatters.iso8601Basic.string(from: Date())
            ))
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
