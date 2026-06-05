import Foundation

/// Aggregates a customer's entire history into one chronological feed.
/// Runs 7 parallel reads, maps each row to a `CustomerTimelineEvent`, sorts
/// descending. Total payload per customer is small (tens of events), so an
/// in-Swift merge is faster than designing a DB view + RLS replication.
enum CustomerTimelineService {
    static func fetch(customerId: UUID, customer: Customer? = nil) async -> [CustomerTimelineEvent] {
        async let inquiries     = (try? InquiriesService.list(customerId: customerId)) ?? []
        async let orders        = (try? OrdersService.list(customerId: customerId)) ?? []
        async let designs       = (try? DesignsService.list(customerId: customerId)) ?? []
        async let measurements  = (try? MeasurementsService.listForCustomer(customerId)) ?? []
        async let appointments  = (try? AppointmentsService.listForCustomer(customerId)) ?? []
        async let jobCards      = (try? JobCardsService.listForCustomer(customerId)) ?? []

        let inq = await inquiries
        let ord = await orders
        let dsg = await designs
        let msr = await measurements
        let apt = await appointments
        let jcs = await jobCards

        // Alterations + payments are keyed by order_id — fetch in batch.
        let orderIds = ord.map(\.id)
        async let alterations   = fetchAlterations(orderIds: orderIds)
        async let payments      = fetchPayments(orderIds: orderIds)
        let alt = await alterations
        let pay = await payments

        var events: [CustomerTimelineEvent] = []

        // M9 fix: composite ID built from kind + sourceId + at — no string-format coupling.
        func ev(_ kind: CustomerTimelineEvent.Kind, sourceId: UUID, at: Date, title: String, subtitle: String? = nil) -> CustomerTimelineEvent {
            CustomerTimelineEvent(
                id: .init(kind: kind, sourceId: sourceId, at: at),
                title: title,
                subtitle: subtitle
            )
        }

        if let c = customer {
            events.append(ev(.customerJoined, sourceId: c.id, at: c.createdAt,
                             title: "Added to customer book",
                             subtitle: c.source.isEmpty ? nil : "Source: \(c.source)"))
        }

        for i in inq {
            events.append(ev(.inquiryCreated, sourceId: i.id, at: i.createdAt,
                             title: "Inquiry \(i.inquiryNumber)", subtitle: i.occasion))
            if i.updatedAt > i.createdAt.addingTimeInterval(60) {
                events.append(ev(.inquiryStatusChanged, sourceId: i.id, at: i.updatedAt,
                                 title: "Inquiry \(i.inquiryNumber) → \(i.status.label)"))
            }
        }

        for m in msr {
            events.append(ev(.measurementTaken, sourceId: m.id, at: m.takenAt,
                             title: "Measurements taken", subtitle: m.garmentType.capitalized))
        }

        for d in dsg {
            events.append(ev(.designCreated, sourceId: d.id, at: d.createdAt,
                             title: "Design '\(d.name)' created", subtitle: d.garmentType))
            if d.sketchImagePath != nil, d.updatedAt > d.createdAt.addingTimeInterval(60) {
                events.append(ev(.designSketchSaved, sourceId: d.id, at: d.updatedAt,
                                 title: "Sketch saved for '\(d.name)'"))
            }
        }

        for o in ord {
            events.append(ev(.orderPlaced, sourceId: o.id, at: o.placedAt ?? o.createdAt,
                             title: "Order \(o.orderNumber) placed",
                             subtitle: Formatters.inr(o.total)))
            if o.updatedAt > o.createdAt.addingTimeInterval(60), o.status != .pending {
                events.append(ev(.orderStatusChanged, sourceId: o.id, at: o.updatedAt,
                                 title: "Order \(o.orderNumber) → \(o.status.label)"))
            }
        }

        let ordersById = Dictionary(uniqueKeysWithValues: ord.map { ($0.id, $0) })
        for p in pay where p.status == "captured" {
            let orderNum = ordersById[p.order_id]?.orderNumber ?? "—"
            let method = (p.method ?? "").uppercased()
            let when = p.captured_at ?? p.created_at
            events.append(ev(.paymentCaptured, sourceId: p.id, at: when,
                             title: "\(Formatters.inr(p.amount)) received",
                             subtitle: "\(orderNum) · \(method.isEmpty ? "Payment" : method)"))
        }

        for j in jcs {
            events.append(ev(.jobCardIssued, sourceId: j.id, at: j.createdAt,
                             title: "Job card \(j.jobNumber) → workshop", subtitle: j.garmentType))
        }

        for a in alt {
            events.append(ev(.alterationRequested, sourceId: a.id, at: a.createdAt,
                             title: "Alteration #\(a.roundNumber) requested",
                             subtitle: a.requestNotes.isEmpty ? nil : String(a.requestNotes.prefix(80))))
            if let done = a.completedAt {
                events.append(ev(.alterationCompleted, sourceId: a.id, at: done,
                                 title: "Alteration #\(a.roundNumber) completed"))
            }
        }

        for ap in apt {
            let kind: CustomerTimelineEvent.Kind = ap.status == .completed ? .appointmentCompleted : .appointmentScheduled
            events.append(ev(kind, sourceId: ap.id, at: ap.scheduledAt,
                             title: "\(ap.type.label) appointment", subtitle: ap.notes))
        }

        return events.sorted { $0.at > $1.at }
    }

    // MARK: - Batch fetch helpers

    private static func fetchAlterations(orderIds: [UUID]) async -> [Alteration] {
        guard !orderIds.isEmpty else { return [] }
        return (try? await SupabaseService.client.from("alterations")
            .select()
            .in("order_id", values: orderIds.map(\.uuidString))
            .order("created_at", ascending: false)
            .execute()
            .value) ?? []
    }

    struct PaymentRow: Decodable, Hashable {
        let id: UUID
        let order_id: UUID
        let amount: Double
        let status: String
        let method: String?
        let captured_at: Date?
        let created_at: Date
    }
    private static func fetchPayments(orderIds: [UUID]) async -> [PaymentRow] {
        guard !orderIds.isEmpty else { return [] }
        return (try? await SupabaseService.client.from("payments")
            .select("id,order_id,amount,status,method,captured_at,created_at")
            .in("order_id", values: orderIds.map(\.uuidString))
            .execute()
            .value) ?? []
    }
}
