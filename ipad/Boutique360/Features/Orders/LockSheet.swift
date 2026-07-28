import SwiftUI

/// R3 — freeze the Look's contract. Presented from OrderDetailView on
/// pending/confirmed unlocked orders. The Lock button is gated by the pure
/// LockGate (advance → event → breakup); the actual lock is atomic via the
/// lock_order RPC (also patches orders.design_id).
struct LockSheet: View {
    let order: Order
    let customer: Customer?
    let onLocked: (OrderLock) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext

    @State private var designs: [Design] = []
    @State private var selectedDesignId: UUID?
    @State private var renderPath: String?
    @State private var renderURL: URL?
    @State private var fabricCode = ""
    @State private var fabricDescription = ""
    @State private var measurements: [CustomerMeasurement] = []
    @State private var selectedMeasurementId: UUID?
    @State private var useBreakup = false
    @State private var fabricText = ""
    @State private var workText = ""
    @State private var otherText = ""
    @State private var rushAccepted = false
    @State private var advancePaid: Double?    // nil = loading/failed; 0 = genuinely no advance
    @State private var advanceLoadFailed = false
    @State private var locking = false
    @State private var error: String?

    var body: some View {
        Form {
            designSection
            fabricSection
            measurementSection
            breakupSection
            eventSection
            advanceSection
            lockSection
        }
        .navigationTitle("Lock the look")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .task { await load() }
        .onChange(of: selectedDesignId) { _, newValue in
            Task { await loadRender(designId: newValue) }
        }
    }

    // MARK: - Sections

    private var designSection: some View {
        Section("Design") {
            Picker("Design", selection: $selectedDesignId) {
                Text("No design — off-rack").tag(UUID?.none)
                ForEach(designs) { d in
                    Text(d.name).tag(UUID?.some(d.id))
                }
            }
            if let url = renderURL {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFit().frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } placeholder: { ProgressView() }
            }
        }
    }

    private var fabricSection: some View {
        Section("Fabric") {
            TextField("Fabric code (e.g. BNRS-EM-01)", text: $fabricCode)
                .autocorrectionDisabled()
            TextField("Description (e.g. emerald Banarasi silk)", text: $fabricDescription,
                      axis: .vertical)
                .lineLimit(1...2)
            Text("Free text until fabric inventory (R5) — code is your own shorthand.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var measurementSection: some View {
        Section("Measurement pin") {
            if measurements.isEmpty {
                Text("No measurements on file — lock proceeds without a pin.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Pinned naap", selection: $selectedMeasurementId) {
                    Text("None").tag(UUID?.none)
                    ForEach(measurements) { m in
                        Text("\(m.garmentType.capitalized) — \(m.takenAt.formatted(date: .abbreviated, time: .omitted))")
                            .tag(UUID?.some(m.id))
                    }
                }
                Text("The lock pins THIS snapshot — later re-measures won't silently change the spec.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var breakupSection: some View {
        Section("Price breakup") {
            Toggle("Record breakup", isOn: $useBreakup)
            if useBreakup {
                breakupField("Fabric", $fabricText)
                breakupField("Work", $workText)
                breakupField("Other", $otherText)
                let sum = breakupValues.map { $0.fabric + $0.work + $0.other } ?? 0
                Label(
                    Money.equalAtPaise(sum, order.subtotal)
                        ? "Reconciles with subtotal \(Formatters.inr(order.subtotal))"
                        : "Sums to \(Formatters.inr(sum)) — subtotal is \(Formatters.inr(order.subtotal))",
                    systemImage: Money.equalAtPaise(sum, order.subtotal)
                        ? "checkmark.circle" : "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(Money.equalAtPaise(sum, order.subtotal) ? .green : .orange)
            }
        }
    }

    private func breakupField(_ label: String, _ text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField("0", text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(width: 120)
        }
    }

    private var eventSection: some View {
        Section("Event plan (frozen into the lock)") {
            if let ev = order.eventDate {
                LabeledContent("Event", value: ev)
                LabeledContent("Alteration buffer", value: "\(order.alterationBufferDays) days")
                if let mf = mustFinishBy {
                    LabeledContent("Must finish by",
                                   value: mf.formatted(date: .abbreviated, time: .omitted))
                }
                if mustFinishByPast {
                    Label("Must-finish-by is already past.", systemImage: "exclamationmark.octagon.fill")
                        .font(.caption).foregroundStyle(.red)
                    Toggle("Accept rush and lock anyway", isOn: $rushAccepted)
                }
            } else {
                Text("No event date on this order — no deadline is frozen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var advanceSection: some View {
        Section("Advance") {
            if advanceLoadFailed {
                Label("Couldn't load payments.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
                Button("Retry") { Task { await loadAdvance() } }
                    .buttonStyle(.bordered)
            } else if let paid = advancePaid {
                LabeledContent("Received", value: Formatters.inr(paid))
            } else {
                ProgressView()
            }
            Text("No advance, no lock — the lock is a paid commitment.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var lockSection: some View {
        Section {
            Button {
                Task { await lock() }
            } label: {
                HStack {
                    Label(locking ? "Locking…" : "Lock the look", systemImage: "lock.fill")
                    Spacer()
                    if locking { ProgressView() }
                }
            }
            .disabled(locking || advancePaid == nil || !currentBlockers.isEmpty)

            if let first = currentBlockers.first {
                Text(message(for: first)).font(.caption).foregroundStyle(.orange)
            }
            if let err = error {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Derived

    private var eventDateParsed: Date? {
        order.eventDate.flatMap { Formatters.postgresDate.date(from: $0) }
    }
    private var mustFinishBy: Date? {
        OrderSlack.mustFinishBy(eventDate: eventDateParsed,
                                fulfillment: order.fulfillmentMethod,
                                alterationBufferDays: order.alterationBufferDays)
    }
    private var mustFinishByPast: Bool {
        guard let mf = mustFinishBy else { return false }
        return mf < Calendar.current.startOfDay(for: Date())
    }
    private var breakupValues: (fabric: Double, work: Double, other: Double)? {
        guard useBreakup else { return nil }
        return (Double(fabricText) ?? 0, Double(workText) ?? 0, Double(otherText) ?? 0)
    }
    private var currentBlockers: [LockGate.Blocker] {
        LockGate.blockers(advancePaid: advancePaid ?? 0,
                          eventDate: eventDateParsed,
                          fulfillment: order.fulfillmentMethod,
                          alterationBufferDays: order.alterationBufferDays,
                          rushAccepted: rushAccepted,
                          breakup: breakupValues,
                          subtotal: order.subtotal,
                          today: Date())
    }

    private func message(for blocker: LockGate.Blocker) -> String {
        switch blocker {
        case .noAdvance:
            "Record an advance payment first — no advance, no lock."
        case .eventInsideBuffer(let d):
            "Must finish by \(d.formatted(date: .abbreviated, time: .omitted)) is already past. Accept rush to lock anyway."
        case .breakupMismatch(let s, let t):
            "Breakup sums to \(Formatters.inr(s)); order subtotal is \(Formatters.inr(t))."
        }
    }

    // MARK: - Loads

    private func load() async {
        designs = (try? await DesignsService.list(customerId: order.customerId)) ?? []
        measurements = ((try? await MeasurementsService.listForCustomer(order.customerId)) ?? [])
            .sorted { $0.takenAt > $1.takenAt }
        selectedMeasurementId = measurements.first?.id
        await loadAdvance()
    }

    private func loadAdvance() async {
        do {
            let sums = try await PaymentsService.capturedSumsForOrders([order.id])
            // Empty result = genuinely ₹0 advance; nil stays reserved for load failure.
            advancePaid = sums.reduce(0.0) { $0 + $1.amount }
            advanceLoadFailed = false
        } catch {
            advancePaid = nil
            advanceLoadFailed = true
        }
    }

    private func loadRender(designId: UUID?) async {
        renderPath = nil; renderURL = nil
        guard let did = designId else { return }
        let renders = (try? await DesignRendersService.listForDesign(did)) ?? []
        guard let done = renders.first(where: { $0.status == .done }) else { return }
        renderPath = done.resultImagePath
        if let path = done.resultImagePath {
            renderURL = try? await StorageService.signedURL(bucket: .designRenders, path: path)
        }
    }

    // MARK: - Lock

    @MainActor
    private func lock() async {
        guard let bid = ctx.boutiqueId else { return }
        locking = true; defer { locking = false }
        let input = NewOrderLock(
            boutique_id: bid,
            order_id: order.id,
            design_id: selectedDesignId,
            render_image_path: renderPath,
            fabric_code: fabricCode.isEmpty ? nil : fabricCode,
            fabric_description: fabricDescription.isEmpty ? nil : fabricDescription,
            measurement_id: selectedMeasurementId,
            price_breakup: breakupValues.map { PriceBreakup(fabric: $0.fabric, work: $0.work, other: $0.other) },
            event_date: order.eventDate,
            alteration_buffer_days: order.alterationBufferDays,
            must_finish_by: mustFinishBy.map { Formatters.postgresDate.string(from: $0) },
            advance_amount: advancePaid ?? 0,
            rush_accepted: rushAccepted
        )
        do {
            let lock = try await OrderLocksService.lock(input)
            onLocked(lock)
            dismiss()
        } catch {
            // Raced double-lock arrives as a 23505 from the RPC — the order IS
            // locked, so fetch and treat as success.
            let msg = error.localizedDescription
            if msg.contains("23505") || msg.lowercased().contains("duplicate"),
               let existing = try? await OrderLocksService.get(orderId: order.id, boutiqueId: bid) {
                onLocked(existing)
                dismiss()
            } else {
                self.error = msg
            }
        }
    }
}
