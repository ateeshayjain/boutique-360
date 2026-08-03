import SwiftUI

struct OrderDetailView: View {
    let order: Order
    let customerName: String?

    @EnvironmentObject private var ctx: BoutiqueContext
    @EnvironmentObject private var roles: StaffRoleContext
    @State private var current: Order
    @State private var items: [OrderItem] = []
    @State private var changing = false
    @State private var invoicePDF: Data?
    @State private var showingInvoice = false
    @State private var invoiceError: String?
    @State private var customer: Customer?
    @State private var statusError: String?
    @State private var notifyMessage: String?     // success/error toast
    @State private var sending: Bool = false
    @State private var jobCard: JobCard?          // R1: slack badge input
    // R3: lock state. lockLoadFailed → never offer locking on unknown state.
    @State private var lock: OrderLock?
    @State private var lockLoadFailed = false
    @State private var showLockSheet = false
    @State private var showLockSummary = false

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
                        .foregroundStyle(current.status.color)
                }
                LabeledContent("Fulfillment") {
                    let method = current.fulfillmentMethod ?? .pickup
                    Label(method.label, systemImage: method.systemImage)
                        .foregroundStyle(.secondary)
                }
                // R1: deadline slack against the customer's event date.
                if current.eventDate != nil {
                    LabeledContent("Deadline") {
                        HStack(spacing: 8) {
                            SlackBadge(verdict: OrderSlack.verdict(for: current, jobCard: jobCard))
                            Text("Event \(current.eventDate ?? "—") · buffer \(current.alterationBufferDays)d")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if lock != nil {
                        Text("Locked — changes via change order only.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                // R3: the lock row / lock action.
                if let lock {
                    LabeledContent("Locked") {
                        Button {
                            showLockSummary = true
                        } label: {
                            Label(lock.lockedAt.formatted(date: .abbreviated, time: .omitted),
                                  systemImage: "lock.fill")
                        }
                    }
                } else if !lockLoadFailed, [.pending, .confirmed].contains(current.status) {
                    Button {
                        showLockSheet = true
                    } label: {
                        Label("Lock the look", systemImage: "lock")
                    }
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
                            // R4b — line value rides with `.invoice`: the
                            // same numbers the invoice PDF prints.
                            if RolePolicy.canSee(.invoice, role: roles.role) {
                                Text(formatINR(Double(item.qty) * item.unitPrice)).monospacedDigit()
                            }
                        }
                    }
                }
            }

            if RolePolicy.canSee(.invoice, role: roles.role) {
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
            }

            if let url = current.trackingUrl {
                Section("Tracking") {
                    Link(destination: URL(string: url) ?? URL(string: "about:blank")!) {
                        Label(current.trackingCourier ?? "Open tracking", systemImage: "shippingbox.and.arrow.backward")
                    }
                }
            }

            if RolePolicy.canSee(.invoice, role: roles.role) {
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
            }

            // Wave 3: unified notify panel — WhatsApp (always when consented) +
            // Email (consented + configured) + SMS (consented + configured).
            // Each channel is independently gated; missing config = disabled
            // button with a hint, so the feature's existence is discoverable.
            if let cust = customer {
                notifySection(customer: cust)
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
        .sheet(isPresented: $showLockSheet) {
            NavigationStack {
                LockSheet(order: current, customer: customer) { newLock in
                    lock = newLock
                }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showLockSummary) {
            if let lock {
                NavigationStack {
                    LockSummarySheet(order: current, lock: lock) {
                        // Totals/event date changed server-side — refetch.
                        NotificationCenter.default.post(name: .orderDidChange, object: nil)
                        Task {
                            if let refreshed = try? await OrdersService.get(id: current.id) {
                                current = refreshed
                            }
                        }
                    }
                }
                .presentationDetents([.large])
            }
        }
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
            // Wave 1: use the customer's billing phone (not WA #) on invoices,
            // and the structured address when present. Falling back to nil
            // keeps the existing "no address captured" layout.
            customerPhone: customer?.phone,
            customerAddress: customer?.address?.multiLine.nonEmpty,
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
        // R1: this order's job card for the slack badge. Best-effort.
        if let bid = ctx.boutiqueId {
            jobCard = (try? await JobCardsService.forOrders([order.id], boutiqueId: bid))?.first
            // R3: lock state — on failure, suppress the lock button (never
            // offer locking on unknown state).
            do {
                lock = try await OrderLocksService.get(orderId: order.id, boutiqueId: bid)
                lockLoadFailed = false
            } catch {
                lockLoadFailed = true
            }
        }
    }

    /// Status-aware WhatsApp button label.
    private func whatsAppLabel(for status: OrderStatus) -> String {
        switch status {
        case .pending, .confirmed: "Send order confirmation"
        case .packed, .shipped:    "Send shipping update"
        case .delivered:           "Send ready/delivered note"
        case .cancelled:           "Send cancellation note"
        case .returned:            "Send return acknowledgement"
        // Never name a state this build can't see.
        case .unknown:             "Send a general update"
        }
    }

    /// Templated, editable Hinglish message — the owner can tweak before sending.
    /// Keeps tone consistent ("Namaste {firstName}", boutique name signature).
    private func whatsAppMessage(for status: OrderStatus, customer: Customer) -> String {
        let firstName = customer.name.split(separator: " ").first.map(String.init) ?? customer.name
        let boutiqueName = ctx.boutique?.name ?? "Boutique"
        // R4b — an assistant composing a status message must not carry the
        // order value out to the customer (same rule as ReminderDrafts).
        let amount = Formatters.inr(current.total)
        let showAmount = RolePolicy.canSee(.invoice, role: roles.role)
        switch status {
        case .pending, .confirmed:
            return showAmount
                ? "Namaste \(firstName)! Your order \(current.orderNumber) for \(amount) is confirmed. We'll keep you updated. — \(boutiqueName)"
                : "Namaste \(firstName)! Your order \(current.orderNumber) is confirmed. We'll keep you updated. — \(boutiqueName)"
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
        case .unknown:
            // A status written by a newer app version. Say nothing about the
            // order's state — a wrong claim here goes to a real customer.
            return "Hi \(firstName), an update on your order \(current.orderNumber). — \(boutiqueName)"
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


    private func formatINR(_ v: Double) -> String { Formatters.inr(v) }

    // MARK: - Wave 3: unified notify section

    @ViewBuilder
    private func notifySection(customer cust: Customer) -> some View {
        let boutiqueName = ctx.boutique?.name ?? "Boutique"
        let plan = CustomerNotifier.orderReadyPlan(
            for: current, customer: cust, boutiqueName: boutiqueName
        )

        // Hide the whole section if there's literally no consented channel.
        if plan.whatsapp == nil && plan.email == nil && plan.sms == nil
           && cust.email?.isEmpty != false && cust.whatsappTarget == nil {
            EmptyView()
        } else {
            Section("Notify customer") {
                // WhatsApp — keeps the existing link-flow behavior.
                if let wa = plan.whatsapp {
                    Button {
                        WhatsAppShareHelper.open(phone: wa.target,
                                                 message: whatsAppMessage(for: current.status, customer: cust))
                    } label: {
                        Label(whatsAppLabel(for: current.status), systemImage: "message.fill")
                            .foregroundStyle(.green)
                    }
                }

                // Email — direct SendGrid send.
                if let em = plan.email {
                    Button {
                        Task { await sendEmail(em, customer: cust) }
                    } label: {
                        HStack {
                            Label("Email \(em.to)", systemImage: "envelope.fill")
                            Spacer()
                            if sending { ProgressView() }
                        }
                    }
                    .disabled(sending)
                } else if let email = cust.email, !email.isEmpty {
                    Label(Config.emailEnabled
                          ? "Email — customer hasn't consented"
                          : "Email — add SENDGRID_API_KEY to enable",
                          systemImage: "envelope")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                // SMS — direct Twilio send.
                if let sms = plan.sms {
                    Button {
                        Task { await sendSMS(sms, customer: cust) }
                    } label: {
                        HStack {
                            Label("SMS \(sms.to)", systemImage: "bubble.left.fill")
                            Spacer()
                            if sending { ProgressView() }
                        }
                    }
                    .disabled(sending)
                } else if cust.whatsappTarget != nil {
                    Label(Config.smsEnabled
                          ? "SMS — uses WhatsApp consent flag"
                          : "SMS — add TWILIO_SID/AUTH_TOKEN/FROM to enable",
                          systemImage: "bubble.left")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                if let m = notifyMessage {
                    Text(m).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @MainActor
    private func sendEmail(_ plan: CustomerNotifier.EmailPlan, customer cust: Customer) async {
        sending = true; defer { sending = false }
        do {
            try await CustomerNotifier.sendEmail(plan, customer: cust)
            notifyMessage = "Email sent to \(plan.to)."
        } catch {
            notifyMessage = "Couldn't send email: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func sendSMS(_ plan: CustomerNotifier.SMSPlan, customer cust: Customer) async {
        sending = true; defer { sending = false }
        do {
            try await CustomerNotifier.sendSMS(plan, customer: cust)
            notifyMessage = "SMS sent to \(plan.to)."
        } catch {
            notifyMessage = "Couldn't send SMS: \(error.localizedDescription)"
        }
    }
}

private extension String {
    /// Returns nil instead of an empty string — useful for converting
    /// "" sentinels into honest absence before passing to optional APIs.
    var nonEmpty: String? { isEmpty ? nil : self }
}
