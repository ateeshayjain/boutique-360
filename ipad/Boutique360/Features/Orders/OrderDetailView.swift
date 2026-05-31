import SwiftUI

struct OrderDetailView: View {
    let order: Order
    let customerName: String?

    @EnvironmentObject private var ctx: BoutiqueContext
    @State private var current: Order
    @State private var items: [OrderItem] = []
    @State private var changing = false
    @State private var invoicePDF: Data?
    @State private var showingInvoice = false
    @State private var invoiceError: String?
    @State private var customer: Customer?
    @State private var statusError: String?

    init(order: Order, customerName: String?) {
        self.order = order
        self.customerName = customerName
        _current = State(initialValue: order)
    }

    var body: some View {
        Form {
            if let err = statusError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.caption)
                }
            }
            Section("Summary") {
                LabeledContent("Order #", value: current.orderNumber)
                LabeledContent("Customer", value: customerName ?? "—")
                LabeledContent("Created", value: current.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Status") {
                    Label(current.status.label, systemImage: current.status.systemImage)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(tint(current.status))
                }
                LabeledContent("Fulfillment") {
                    let method = current.fulfillmentMethod ?? .pickup
                    Label(method.label, systemImage: method.systemImage)
                        .foregroundStyle(.secondary)
                }
            }

            PaymentsSectionView(order: current, customer: customer)
            AlterationsSectionView(orderId: current.id)
            OrderTimelineView(orderId: current.id)

            Section("Items") {
                if items.isEmpty {
                    Text("No items").foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.lineDescription ?? "Custom line")
                                Text("Qty \(item.qty)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatINR(Double(item.qty) * item.unitPrice)).monospacedDigit()
                        }
                    }
                }
            }

            Section("Totals") {
                LabeledContent("Subtotal", value: formatINR(current.subtotal))
                LabeledContent("GST", value: formatINR(current.gstAmount))
                if let s = current.shipping, s > 0 {
                    LabeledContent("Shipping", value: formatINR(s))
                }
                LabeledContent {
                    Text(formatINR(current.total)).fontWeight(.semibold).monospacedDigit()
                } label: { Text("Total").fontWeight(.semibold) }
            }

            if let url = current.trackingUrl {
                Section("Tracking") {
                    Link(destination: URL(string: url) ?? URL(string: "about:blank")!) {
                        Label(current.trackingCourier ?? "Open tracking", systemImage: "shippingbox.and.arrow.backward")
                    }
                }
            }

            Section("Invoice") {
                Button {
                    if let pdf = generateInvoicePDF() {
                        invoicePDF = pdf
                        showingInvoice = true
                    }
                } label: {
                    Label("Generate GST invoice", systemImage: "doc.text.fill")
                }
                .disabled(ctx.boutique?.gstin == nil)
                if ctx.boutique?.gstin == nil {
                    Label("Add your GSTIN in Settings before generating invoices.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let err = invoiceError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                Text("PDF preview opens in-app. Tap Share to email, print, or save.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            if let cust = customer, cust.consentWhatsapp, cust.phone != nil {
                Section("WhatsApp customer") {
                    Button {
                        WhatsAppShareHelper.open(phone: cust.phone, message: whatsAppMessage(for: current.status, customer: cust))
                    } label: {
                        Label(whatsAppLabel(for: current.status), systemImage: "message.fill")
                            .foregroundStyle(.green)
                    }
                    Text("Opens WhatsApp with a pre-filled, editable message.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Section("Magic link (customer-facing)") {
                if let token = current.magicLinkToken {
                    Text("https://boutique360.com/orders/\(token)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Send this link via WhatsApp once the public site is live (Plan 8).")
                        .font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Text("Magic link not generated").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Order \(current.orderNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if current.status.nextOptions.isEmpty {
                    EmptyView()
                } else {
                    Menu {
                        ForEach(current.status.nextOptions, id: \.self) { next in
                            Button {
                                Task { await advance(to: next) }
                            } label: {
                                Label("Mark \(next.label)", systemImage: next.systemImage)
                            }
                        }
                    } label: {
                        Label("Change status", systemImage: "ellipsis.circle")
                    }
                    .disabled(changing)
                }
            }
        }
        .task { await loadItems() }
        .sheet(isPresented: $showingInvoice) {
            if let data = invoicePDF {
                InvoicePreviewView(pdfData: data, invoiceNumber: invoiceNumberPreview())
            }
        }
    }

    /// Builds the PDF input from current order + items.
    /// Reads boutique identity from BoutiqueContext (never hard-coded).
    /// Returns nil if boutique identity isn't loaded — UI surfaces the error.
    private func generateInvoicePDF() -> Data? {
        guard let boutique = ctx.boutique else {
            invoiceError = "Boutique identity not loaded. Sign out and back in, or check Settings."
            return nil
        }
        let defaultRate = ctx.boutique?.defaultGstRate ?? 5.0
        let lines: [InvoicePDFGenerator.InvoiceLine] = items.isEmpty
            ? [.init(description: "Custom order \(current.orderNumber)",
                     qty: 1, unitPrice: current.subtotal,
                     // L2 fix: use boutique's default rate, not hardcoded 5%.
                     gstRate: current.subtotal > 0 ? (current.gstAmount / current.subtotal * 100) : defaultRate,
                     hsnCode: "6204")]
            : items.map { item in
                // H13 fix: prefer the persisted gstRate; only reverse-engineer
                // for legacy rows where gstRate is nil. Defaults to boutique's
                // configured rate, not the hardcoded 5%.
                let defaultRate = ctx.boutique?.defaultGstRate ?? 5.0
                let rate = item.gstRate ?? (item.unitPrice > 0
                    ? (item.gstAmount / (Double(item.qty) * item.unitPrice) * 100)
                    : defaultRate)
                return .init(
                    description: item.lineDescription ?? "Custom line",
                    qty: item.qty,
                    unitPrice: item.unitPrice,
                    gstRate: rate,
                    hsnCode: nil
                )
            }
        let input = InvoicePDFGenerator.Input(
            invoiceNumber: invoiceNumberPreview(),
            orderNumber: current.orderNumber,
            issuedAt: current.placedAt ?? current.createdAt,
            boutiqueName: boutique.name,
            boutiqueAddress: boutique.address ?? "",
            boutiqueGSTIN: boutique.gstin,
            customerName: customerName ?? "Customer",
            customerPhone: nil,
            customerAddress: nil,
            items: lines,
            subtotal: current.subtotal,
            gstAmount: current.gstAmount,
            shipping: current.shipping ?? 0,
            total: current.total,
            placeOfSupply: boutique.placeOfSupply ?? "—",
            hsnDefault: "6204"
        )
        invoiceError = nil
        return InvoicePDFGenerator.render(input)
    }

    private func invoiceNumberPreview() -> String {
        let year = Calendar(identifier: .gregorian).component(.year, from: current.placedAt ?? current.createdAt)
        let suffix = current.orderNumber.split(separator: "-").last.map(String.init) ?? "0001"
        return "INV-\(year)-\(suffix)"
    }

    private func loadItems() async {
        items = (try? await OrdersService.items(forOrder: order.id)) ?? []
        customer = try? await CustomersService.get(id: order.customerId)
    }

    /// Status-aware WhatsApp button label.
    private func whatsAppLabel(for status: OrderStatus) -> String {
        switch status {
        case .pending, .confirmed: "Send order confirmation"
        case .packed, .shipped:    "Send shipping update"
        case .delivered:           "Send ready/delivered note"
        case .cancelled:           "Send cancellation note"
        case .returned:            "Send return acknowledgement"
        }
    }

    /// Templated, editable Hinglish message — the owner can tweak before sending.
    /// Keeps tone consistent ("Namaste {firstName}", boutique name signature).
    private func whatsAppMessage(for status: OrderStatus, customer: Customer) -> String {
        let firstName = customer.name.split(separator: " ").first.map(String.init) ?? customer.name
        let boutiqueName = ctx.boutique?.name ?? "Boutique"
        let amount = Formatters.inr(current.total)
        switch status {
        case .pending, .confirmed:
            return "Namaste \(firstName)! Your order \(current.orderNumber) for \(amount) is confirmed. We'll keep you updated. — \(boutiqueName)"
        case .packed:
            return "Hi \(firstName), your order \(current.orderNumber) is packed and ready. We'll dispatch shortly. — \(boutiqueName)"
        case .shipped:
            let track = current.trackingUrl.map { "\nTrack: \($0)" } ?? ""
            return "Hi \(firstName), your order \(current.orderNumber) has been shipped.\(track) — \(boutiqueName)"
        case .delivered:
            let fulfillment = current.fulfillmentMethod ?? .pickup
            if fulfillment == .ship {
                return "Hi \(firstName), your order \(current.orderNumber) has been delivered. Hope you love it! — \(boutiqueName)"
            } else {
                return "Hi \(firstName), your order \(current.orderNumber) is ready for pickup at \(boutiqueName). Looking forward to seeing you!"
            }
        case .cancelled:
            return "Hi \(firstName), your order \(current.orderNumber) has been cancelled as discussed. Any refund will be processed within 5-7 days. — \(boutiqueName)"
        case .returned:
            return "Hi \(firstName), we've received your return for \(current.orderNumber). Refund will be processed shortly. — \(boutiqueName)"
        }
    }

    private func advance(to next: OrderStatus) async {
        changing = true; defer { changing = false }
        do {
            // H2 fix: surface failures instead of leaving the UI on the old
            // status (which led to the owner re-sending WhatsApp confirmations).
            let updated = try await OrdersService.updateStatus(order.id, to: next)
            current = updated
            statusError = nil
            // H3 fix: tell embedded child views (Payments, Alterations, Timeline)
            // to refresh — they were initialized with `current` at view load.
            NotificationCenter.default.post(name: .orderDidChange, object: order.id)
        } catch {
            statusError = "Couldn't update status: \(error.localizedDescription)"
        }
    }

    private func tint(_ s: OrderStatus) -> Color {
        switch s {
        case .pending: .orange; case .confirmed: .blue; case .packed: .indigo
        case .shipped: .purple; case .delivered: .green
        case .cancelled: .gray; case .returned: .red
        }
    }

    private func formatINR(_ v: Double) -> String { Formatters.inr(v) }
}
