import SwiftUI

struct OrderCreateView: View {
    let onCreated: (Order) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext

    @State private var customers: [Customer] = []
    @State private var inquiries: [Inquiry] = []
    @State private var selectedCustomerId: UUID?
    @State private var selectedInquiryId: UUID?

    @State private var lineDescription: String = ""
    @State private var lineQty: Int = 1
    @State private var linePriceText: String = ""
    @State private var gstRate: Double = 5.0   // populated from boutique.defaultGstRate on .task
    @State private var fulfillmentMethod: FulfillmentMethod = .pickup

    @State private var saving = false
    @State private var error: String?

    /// Sub-total = qty × unitPrice. GST = sub-total × rate/100. Total = sub-total + GST.
    @State private var hasEventDate = false
    @State private var eventDate = Date()
    @State private var alterationBufferDays = 7

    private var unitPrice: Double { Double(linePriceText) ?? 0 }
    private var subtotal: Double { Double(lineQty) * unitPrice }
    private var gstAmount: Double { subtotal * gstRate / 100 }
    private var total: Double { subtotal + gstAmount }

    var body: some View {
        Form {
            Section("Customer") {
                Picker("Customer", selection: $selectedCustomerId) {
                    Text("Select customer").tag(UUID?.none)
                    ForEach(customers) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }

            if let cid = selectedCustomerId, !inquiries.filter({ $0.customerId == cid }).isEmpty {
                Section("Convert from inquiry (optional)") {
                    Picker("Inquiry", selection: $selectedInquiryId) {
                        Text("Direct order").tag(UUID?.none)
                        ForEach(inquiries.filter { $0.customerId == cid }) { inq in
                            Text("\(inq.inquiryNumber) — \(inq.occasion ?? "—")").tag(UUID?.some(inq.id))
                        }
                    }
                    if selectedInquiryId != nil {
                        Text("Inquiry will be marked Confirmed and linked to this order.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Order line") {
                TextField("Description (e.g. Custom Bridal Lehenga)", text: $lineDescription)
                Stepper(value: $lineQty, in: 1...100) {
                    LabeledContent("Qty", value: "\(lineQty)")
                }
                LabeledContent("Unit price") {
                    TextField("0", text: $linePriceText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(width: 120)
                }
                Picker("GST rate", selection: $gstRate) {
                    ForEach([0.0, 5.0, 12.0, 18.0], id: \.self) { Text("\(Int($0))%").tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Delivery") {
                Picker("Method", selection: $fulfillmentMethod) {
                    Label("Pickup from store", systemImage: "bag.fill").tag(FulfillmentMethod.pickup)
                    Label("Ship to address", systemImage: "shippingbox").tag(FulfillmentMethod.ship)
                }
                .pickerStyle(.segmented)
            }

            // R1: event-date anchoring. Creation-time semantics per spec —
            // no job card exists yet, so we show the must-finish-by date
            // (event − buffer − delivery) and warn on rush/impossible.
            // Warn, never block: the owner may knowingly accept rush work.
            Section("Event deadline") {
                Toggle("Tied to an event date", isOn: $hasEventDate)
                if hasEventDate {
                    DatePicker("Event date", selection: $eventDate,
                               in: Date()..., displayedComponents: .date)
                    Stepper("Alteration buffer: \(alterationBufferDays) days",
                            value: $alterationBufferDays, in: 0...30)
                    mustFinishByLine
                }
            }

            Section("Totals") {
                // R4b triage — deliberately NOT gated. Every input to these
                // sums (unit price × qty, GST rate) is being typed on this
                // same screen by whoever is filling the form, so hiding the
                // derived total hides nothing they can't add up. Gating it
                // would only mean an assistant quotes a price blind.
                LabeledContent("Subtotal", value: formatINR(subtotal))
                LabeledContent("GST (\(Int(gstRate))%)", value: formatINR(gstAmount))
                LabeledContent {
                    Text(formatINR(total)).fontWeight(.semibold)
                } label: {
                    Text("Total").fontWeight(.semibold)
                }
            }

            if let err = error {
                Section { Text(err).foregroundStyle(.red).font(.caption) }
            }
        }
        .navigationTitle("New order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Saving…" : "Create") { Task { await create() } }
                    .disabled(saving || selectedCustomerId == nil || total <= 0 || error != nil)
            }
        }
        .task { await load() }
    }

    private func load() async {
        // M3 fix: surface load failure. If customers list silently empties, the
        // picker shows nothing and the owner adds a duplicate customer record.
        do {
            self.customers = try await CustomersService.list()
            self.inquiries = (try await InquiriesService.list())
                .filter { ![.delivered, .lost].contains($0.status) }
            self.error = nil
            // L2 fix: seed GST rate from boutique config instead of 5% hardcode.
            if let r = ctx.boutique?.defaultGstRate { self.gstRate = r }
        } catch {
            self.error = "Couldn't load customers: \(error.localizedDescription). Retry."
        }
    }

    private func create() async {
        guard let bid = ctx.boutiqueId, let cid = selectedCustomerId else { return }
        saving = true; defer { saving = false }

        do {
            let orderNumber = try await OrdersService.generateOrderNumber(boutiqueId: bid)
            let new = NewOrder(
                boutique_id: bid,
                order_number: orderNumber,
                customer_id: cid,
                status: OrderStatus.pending.rawValue,
                subtotal: subtotal,
                gst_amount: gstAmount,
                shipping: 0,
                total: total,
                currency: "INR",
                magic_link_token: UUID().uuidString,
                fulfillment_method: fulfillmentMethod.rawValue,
                placed_at: Formatters.iso8601Basic.string(from: Date()),
                event_date: hasEventDate ? Formatters.postgresDate.string(from: eventDate) : nil,
                alteration_buffer_days: alterationBufferDays
            )
            let lineDesc = lineDescription.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil
                : lineDescription.trimmingCharacters(in: .whitespaces)
            let created = try await OrdersService.create(
                order: new,
                items: [.init(productId: nil, variantId: nil,
                              qty: lineQty, unitPrice: unitPrice,
                              gstRate: gstRate,            // H13: store the chosen rate
                              gstAmount: gstAmount, lineDescription: lineDesc)],
                sourceInquiryId: selectedInquiryId
            )
            onCreated(created)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func formatINR(_ v: Double) -> String { Formatters.inr(v) }

    /// R1 creation-time guidance: production must finish by
    /// event − buffer − delivery. Red when < minimumProductionDays remain.
    @ViewBuilder private var mustFinishByLine: some View {
        if let mf = OrderSlack.mustFinishBy(eventDate: eventDate,
                                            fulfillment: fulfillmentMethod,
                                            alterationBufferDays: alterationBufferDays) {
            let days = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: Date()),
                to: mf).day ?? 0
            if days < 0 {
                Label("Won't fit: the event is inside the alteration + delivery buffer.",
                      systemImage: "exclamationmark.octagon.fill")
                    .font(.caption).foregroundStyle(.red)
            } else if days < OrderSlack.minimumProductionDays {
                Label("Production must finish by \(mf.formatted(date: .abbreviated, time: .omitted)) — only \(days) days. Rush order.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            } else {
                Label("Production must finish by \(mf.formatted(date: .abbreviated, time: .omitted)) — \(days) days from today.",
                      systemImage: "calendar.badge.clock")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
