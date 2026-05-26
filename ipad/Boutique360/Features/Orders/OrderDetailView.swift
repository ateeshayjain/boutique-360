import SwiftUI

struct OrderDetailView: View {
    let order: Order
    let customerName: String?

    @State private var current: Order
    @State private var items: [OrderItem] = []
    @State private var changing = false
    @State private var invoicePDF: Data?
    @State private var showingInvoice = false

    init(order: Order, customerName: String?) {
        self.order = order
        self.customerName = customerName
        _current = State(initialValue: order)
    }

    var body: some View {
        Form {
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
                    Label(
                        (current.fulfillmentMethod ?? "pickup") == "ship" ? "Ship" : "Pickup",
                        systemImage: (current.fulfillmentMethod ?? "pickup") == "ship" ? "shippingbox" : "bag.fill"
                    ).foregroundStyle(.secondary)
                }
            }

            PaymentsSectionView(order: current)
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
                    invoicePDF = generateInvoicePDF()
                    showingInvoice = true
                } label: {
                    Label("Generate GST invoice", systemImage: "doc.text.fill")
                }
                Text("PDF preview opens in-app. Tap Share to email, print, or save.")
                    .font(.caption2).foregroundStyle(.tertiary)
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

    /// Builds the PDF input from current order + items. Invoice number is "INV-YYYY-NNNN"
    /// using the order's placed-at year + a deterministic suffix from the order number.
    private func generateInvoicePDF() -> Data {
        let lines: [InvoicePDFGenerator.InvoiceLine] = items.isEmpty
            ? [.init(description: "Custom order \(current.orderNumber)", qty: 1, unitPrice: current.subtotal, gstRate: current.subtotal > 0 ? (current.gstAmount / current.subtotal * 100) : 5.0, hsnCode: "6204")]
            : items.map { item in
                .init(
                    description: item.lineDescription ?? "Custom line",
                    qty: item.qty,
                    unitPrice: item.unitPrice,
                    gstRate: item.unitPrice > 0 ? (item.gstAmount / (Double(item.qty) * item.unitPrice) * 100) : 5.0,
                    hsnCode: nil
                )
            }
        let input = InvoicePDFGenerator.Input(
            invoiceNumber: invoiceNumberPreview(),
            orderNumber: current.orderNumber,
            issuedAt: current.placedAt ?? current.createdAt,
            boutiqueName: "Aditi Designer Studio",
            boutiqueAddress: "123 Designer Street, New Delhi 110001",
            boutiqueGSTIN: "07AAAAA0000A1Z5",
            customerName: customerName ?? "Customer",
            customerPhone: nil,
            customerAddress: nil,
            items: lines,
            subtotal: current.subtotal,
            gstAmount: current.gstAmount,
            shipping: current.shipping ?? 0,
            total: current.total,
            placeOfSupply: "Delhi",
            hsnDefault: "6204"
        )
        return InvoicePDFGenerator.render(input)
    }

    private func invoiceNumberPreview() -> String {
        let year = Calendar(identifier: .gregorian).component(.year, from: current.placedAt ?? current.createdAt)
        let suffix = current.orderNumber.split(separator: "-").last.map(String.init) ?? "0001"
        return "INV-\(year)-\(suffix)"
    }

    private func loadItems() async {
        items = (try? await OrdersService.items(forOrder: order.id)) ?? []
    }

    private func advance(to next: OrderStatus) async {
        changing = true; defer { changing = false }
        if let updated = try? await OrdersService.updateStatus(order.id, to: next) {
            current = updated
        }
    }

    private func tint(_ s: OrderStatus) -> Color {
        switch s {
        case .pending: .orange; case .confirmed: .blue; case .packed: .indigo
        case .shipped: .purple; case .delivered: .green
        case .cancelled: .gray; case .returned: .red
        }
    }

    private func formatINR(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "INR"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "₹\(Int(v))"
    }
}
