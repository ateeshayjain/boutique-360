import SwiftUI

/// R3 — read-only view of the frozen contract + the change-order ledger +
/// the "Add change order" form. Breakup and buffer are shown as agreed at
/// lock time (frozen artifacts); the ledger records everything since.
struct LockSummarySheet: View {
    let order: Order
    let lock: OrderLock
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ctx: BoutiqueContext
    @EnvironmentObject private var roles: StaffRoleContext

    @State private var renderURL: URL?
    @State private var pinnedMeasurement: CustomerMeasurement?
    @State private var changeOrders: [ChangeOrder] = []
    @State private var coLoadError: String?
    @State private var coDescription = ""
    @State private var coDeltaText = ""
    @State private var coHasNewDate = false
    @State private var coNewDate = Date()
    @State private var applying = false
    @State private var applyError: String?

    var body: some View {
        Form {
            contractSection
            ledgerSection
            addChangeOrderSection
        }
        .navigationTitle("Locked look")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
        }
        .task { await load() }
    }

    private var contractSection: some View {
        Section {
            if let url = renderURL {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFit().frame(maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } placeholder: { ProgressView() }
            }
            if let code = lock.fabricCode {
                LabeledContent("Fabric", value: code)
            }
            if let desc = lock.fabricDescription {
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("Pinned naap") {
                if let m = pinnedMeasurement {
                    Text("\(m.garmentType.capitalized) — \(m.takenAt.formatted(date: .abbreviated, time: .omitted))")
                } else if lock.measurementId != nil {
                    Text("snapshot …") .foregroundStyle(.secondary)
                } else {
                    Text("not pinned").foregroundStyle(.secondary)
                }
            }
            if let b = lock.priceBreakup, RolePolicy.canSee(.lockPricing, role: roles.role) {
                LabeledContent("Fabric ₹", value: Formatters.inr(b.fabric))
                LabeledContent("Work ₹", value: Formatters.inr(b.work))
                LabeledContent("Other ₹", value: Formatters.inr(b.other))
            }
            if let ev = lock.eventDate {
                LabeledContent("Event (at lock)", value: ev)
            }
            if let buf = lock.alterationBufferDays {
                LabeledContent("Buffer (at lock)", value: "\(buf) days")
            }
            if let mf = lock.mustFinishBy {
                LabeledContent("Must finish by (at lock)", value: mf)
            }
            if RolePolicy.canSee(.lockPricing, role: roles.role) {
                LabeledContent("Advance at lock", value: Formatters.inr(lock.advanceAmount))
            }
            if lock.rushAccepted {
                Label("Rush accepted at lock", systemImage: "hare.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Label("The contract — locked \(lock.lockedAt.formatted(date: .abbreviated, time: .omitted))",
                  systemImage: "lock.fill")
        } footer: {
            Text("Agreed at lock; later changes live in the ledger below. Breakup and buffer are frozen artifacts.")
        }
    }

    private var ledgerSection: some View {
        Section("Change orders") {
            if let err = coLoadError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
                Button("Retry") { Task { await loadChangeOrders() } }
                    .buttonStyle(.bordered)
            } else if changeOrders.isEmpty {
                Text("No changes since lock.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(changeOrders) { co in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(co.description).font(.subheadline)
                        HStack(spacing: 8) {
                            if co.priceDelta != 0, RolePolicy.canSee(.lockPricing, role: roles.role) {
                                Text("\(co.priceDelta > 0 ? "+" : "−")\(Formatters.inr(abs(co.priceDelta)))")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(co.priceDelta > 0 ? .orange : .green)
                                    .monospacedDigit()
                            }
                            if let d = co.newEventDate {
                                Text("event → \(d)").font(.caption).foregroundStyle(.purple)
                            }
                            Spacer()
                            Text(co.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var addChangeOrderSection: some View {
        Section("Add change order") {
            TextField("What changed (e.g. sleeves added)", text: $coDescription,
                      axis: .vertical)
                .lineLimit(1...2)
            // R4b — an assistant can log "sleeves added"; repricing it is the
            // owner's call. The delta submits as 0 when hidden.
            if RolePolicy.canSee(.lockPricing, role: roles.role) {
                LabeledContent("Price delta ₹ (±)") {
                    TextField("0", text: $coDeltaText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .frame(width: 140)
                }
            }
            Toggle("New event date", isOn: $coHasNewDate)
            if coHasNewDate {
                DatePicker("Event date", selection: $coNewDate,
                           in: Date()..., displayedComponents: .date)
            }
            Button {
                Task { await apply() }
            } label: {
                HStack {
                    Label(applying ? "Applying…" : "Apply change order", systemImage: "plus.circle")
                    Spacer()
                    if applying { ProgressView() }
                }
            }
            .disabled(applying || coDescription.trimmingCharacters(in: .whitespaces).isEmpty)

            if let err = applyError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            Text("Applied atomically: totals + event date update, and the entry is permanent (append-only).")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Loads / actions

    private func load() async {
        if let path = lock.renderImagePath {
            renderURL = try? await StorageService.signedURL(bucket: .designRenders, path: path)
        }
        if let mid = lock.measurementId {
            let all = (try? await MeasurementsService.listForCustomer(order.customerId)) ?? []
            pinnedMeasurement = all.first { $0.id == mid }
        }
        await loadChangeOrders()
    }

    private func loadChangeOrders() async {
        guard let bid = ctx.boutiqueId else { return }
        do {
            changeOrders = try await OrderLocksService.changeOrders(orderId: order.id, boutiqueId: bid)
            coLoadError = nil
        } catch {
            coLoadError = "Couldn't load change orders: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func apply() async {
        applying = true; defer { applying = false }
        let delta = Double(coDeltaText) ?? 0
        do {
            _ = try await OrderLocksService.applyChangeOrder(
                orderId: order.id,
                description: coDescription.trimmingCharacters(in: .whitespaces),
                priceDelta: delta,
                newEventDate: coHasNewDate ? Formatters.postgresDate.string(from: coNewDate) : nil
            )
            coDescription = ""; coDeltaText = ""; coHasNewDate = false
            applyError = nil
            await loadChangeOrders()
            onChanged()
        } catch {
            // The RPC's exception messages (not locked / negative subtotal)
            // are user-meaningful — surface verbatim.
            applyError = error.localizedDescription
        }
    }
}
