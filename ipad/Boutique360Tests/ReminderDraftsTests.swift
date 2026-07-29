import XCTest
@testable import Boutique360

/// R4a — spec Unit 2 rules. today = 2026-07-28 throughout.
final class ReminderDraftsTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ y: Int, _ m: Int, _ dd: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: dd))!
    }
    private var today: Date { d(2026, 7, 28) }
    private let dec: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
    private let bid = "22222222-2222-2222-2222-222222222222"

    private func customer(consent: Bool = true, phone: String? = "9876543210",
                          id: UUID = UUID()) -> Customer {
        let phoneLine = phone.map { "\"phone\":\"\($0)\"," } ?? ""
        return try! dec.decode(Customer.self, from: """
        {"id":"\(id.uuidString)","boutique_id":"\(bid)","name":"Priya Mehta",
         \(phoneLine)"tags":[],"vip_status":false,"loyalty_points":0,
         "source":"walkin","consent_whatsapp":\(consent),"consent_email":false,
         "created_at":"2026-07-01T10:00:00Z","updated_at":"2026-07-01T10:00:00Z"}
        """.data(using: .utf8)!)
    }

    private func appointment(customerId: UUID, type: String = "fitting",
                             status: String = "scheduled",
                             at: Date, id: UUID = UUID()) -> Appointment {
        let iso = ISO8601DateFormatter()
        return try! dec.decode(Appointment.self, from: """
        {"id":"\(id.uuidString)","boutique_id":"\(bid)","customer_id":"\(customerId.uuidString)",
         "type":"\(type)","scheduled_at":"\(iso.string(from: at))","duration_minutes":30,
         "status":"\(status)"}
        """.data(using: .utf8)!)
    }

    private func order(_ num: String, customerId: UUID, status: String = "confirmed",
                       total: Double = 1000, placed: String = "2026-07-01T10:00:00Z",
                       id: UUID = UUID()) -> Order {
        try! dec.decode(Order.self, from: """
        {"id":"\(id.uuidString)","boutique_id":"\(bid)","order_number":"\(num)",
         "customer_id":"\(customerId.uuidString)","status":"\(status)","subtotal":\(total),
         "gst_amount":0,"total":\(total),"currency":"INR","placed_at":"\(placed)",
         "created_at":"\(placed)","updated_at":"\(placed)"}
        """.data(using: .utf8)!)
    }

    private func card(orderId: UUID, status: String = "ready", id: UUID = UUID()) -> JobCard {
        try! dec.decode(JobCard.self, from: """
        {"id":"\(id.uuidString)","boutique_id":"\(bid)","job_number":"JC-1",
         "order_id":"\(orderId.uuidString)","status":"\(status)","fabric_list_json":[],
         "current_stage":0,"stages_progress_json":[],
         "created_at":"2026-07-01T10:00:00Z","updated_at":"2026-07-01T10:00:00Z"}
        """.data(using: .utf8)!)
    }

    private func build(appointments: [Appointment] = [], orders: [Order] = [],
                       cards: [UUID: JobCard] = [:], events: [UUID: JobCardEvent] = [:],
                       received: [UUID: Double] = [:], customers: [UUID: Customer] = [:],
                       logged: Set<String> = [], failed: Set<MorningBoard.Input> = [])
                       -> [ReminderDrafts.Draft] {
        ReminderDrafts.build(appointments: appointments, orders: orders,
                             jobCardsByOrder: cards, latestEventByCard: events,
                             receivedByOrder: received, customersById: customers,
                             logged: logged, failedInputs: failed,
                             boutiqueName: "Aangan", today: today, calendar: cal)
    }

    // MARK: - Fitting rule

    func testFittingTodayAndTomorrowIncluded() {
        let c = customer()
        let a1 = appointment(customerId: c.id, at: d(2026, 7, 28))
        let a2 = appointment(customerId: c.id, at: d(2026, 7, 29))
        let drafts = build(appointments: [a1, a2], customers: [c.id: c])
        XCTAssertEqual(drafts.count, 2)
        XCTAssertTrue(drafts.allSatisfy { $0.kind == .fitting })
        // forDate is the APPOINTMENT's date, not today
        XCTAssertEqual(Set(drafts.map(\.forDate)), ["2026-07-28", "2026-07-29"])
    }

    func testFittingDayAfterTomorrowExcluded() {
        let c = customer()
        let a = appointment(customerId: c.id, at: d(2026, 7, 30))
        XCTAssertTrue(build(appointments: [a], customers: [c.id: c]).isEmpty)
    }

    func testNonFittingTypeExcluded() {
        let c = customer()
        let a = appointment(customerId: c.id, type: "consultation", at: d(2026, 7, 28))
        XCTAssertTrue(build(appointments: [a], customers: [c.id: c]).isEmpty)
    }

    func testCancelledAppointmentExcluded() {
        let c = customer()
        let a = appointment(customerId: c.id, status: "cancelled", at: d(2026, 7, 28))
        XCTAssertTrue(build(appointments: [a], customers: [c.id: c]).isEmpty)
    }

    // MARK: - Payment rule

    func testPaymentIncludedAtExactlySevenDays() {
        let c = customer()
        let o = order("BQ-1", customerId: c.id, placed: "2026-07-21T10:00:00Z")
        let drafts = build(orders: [o], received: [o.id: 400], customers: [c.id: c])
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].kind, .payment)
        XCTAssertEqual(drafts[0].amountDue, 600)
        XCTAssertEqual(drafts[0].forDate, "2026-07-28")   // payment forDate = today
    }

    func testPaymentExcludedAtSixDays() {
        let c = customer()
        let o = order("BQ-1", customerId: c.id, placed: "2026-07-22T10:00:00Z")
        XCTAssertTrue(build(orders: [o], customers: [c.id: c]).isEmpty)
    }

    func testPaymentExcludesPendingStatus() {
        // Matches DashboardView.filterOverdue exactly.
        let c = customer()
        let o = order("BQ-1", customerId: c.id, status: "pending")
        XCTAssertTrue(build(orders: [o], customers: [c.id: c]).isEmpty)
    }

    func testFullyPaidExcluded() {
        let c = customer()
        let o = order("BQ-1", customerId: c.id, total: 1000)
        XCTAssertTrue(build(orders: [o], received: [o.id: 1000], customers: [c.id: c]).isEmpty)
    }

    // MARK: - Ready rule

    func testReadyIncludedFromCardStatus() {
        let c = customer()
        let o = order("BQ-1", customerId: c.id, status: "confirmed")
        let jc = card(orderId: o.id, status: "ready")
        let drafts = build(orders: [o], cards: [o.id: jc],
                           received: [o.id: 1000], customers: [c.id: c])
        XCTAssertEqual(drafts.map(\.kind), [.ready])
    }

    func testReadyExcludedWhenDelivered() {
        let c = customer()
        let o = order("BQ-1", customerId: c.id, status: "delivered")
        let jc = card(orderId: o.id, status: "ready")
        XCTAssertTrue(build(orders: [o], cards: [o.id: jc],
                            received: [o.id: 1000], customers: [c.id: c]).isEmpty)
    }

    // MARK: - Consent gate (DPDP)

    func testNoConsentProducesNoDraft() {
        let c = customer(consent: false)
        let a = appointment(customerId: c.id, at: d(2026, 7, 28))
        XCTAssertTrue(build(appointments: [a], customers: [c.id: c]).isEmpty)
    }

    func testNoPhoneProducesNoDraft() {
        let c = customer(phone: nil)
        let a = appointment(customerId: c.id, at: d(2026, 7, 28))
        XCTAssertTrue(build(appointments: [a], customers: [c.id: c]).isEmpty)
    }

    // MARK: - Dedup

    func testLoggedKeyExcludesDraft() {
        let c = customer()
        let a = appointment(customerId: c.id, at: d(2026, 7, 28))
        let key = ReminderDrafts.key(kind: .fitting, subjectId: a.id, forDate: "2026-07-28")
        XCTAssertTrue(build(appointments: [a], customers: [c.id: c], logged: [key]).isEmpty)
    }

    func testKeyIsLowercasedAndStable() {
        let id = UUID()
        let k = ReminderDrafts.key(kind: .payment, subjectId: id, forDate: "2026-07-28")
        XCTAssertEqual(k, "payment-\(id.uuidString.lowercased())-2026-07-28")
        XCTAssertFalse(k.contains(where: { $0.isUppercase }))
    }

    // MARK: - Degraded inputs (correctness, not cosmetics)

    func testPaymentsFailureSuppressesPaymentDrafts() {
        // Without this, an empty receivedByOrder makes every balance look
        // like the full total — nudging customers for money already paid.
        let c = customer()
        let o = order("BQ-1", customerId: c.id, placed: "2026-07-01T10:00:00Z")
        let drafts = build(orders: [o], received: [:], customers: [c.id: c],
                           failed: [.payments])
        XCTAssertTrue(drafts.filter { $0.kind == .payment }.isEmpty)
    }

    func testOrdersFailureSuppressesPaymentAndReady() {
        let c = customer()
        let o = order("BQ-1", customerId: c.id, placed: "2026-07-01T10:00:00Z")
        let jc = card(orderId: o.id)
        let drafts = build(orders: [o], cards: [o.id: jc], received: [o.id: 0],
                           customers: [c.id: c], failed: [.orders])
        XCTAssertTrue(drafts.filter { $0.kind == .payment || $0.kind == .ready }.isEmpty)
    }

    func testJobCardsFailureSuppressesReady() {
        let c = customer()
        let o = order("BQ-1", customerId: c.id)
        let jc = card(orderId: o.id)
        let drafts = build(orders: [o], cards: [o.id: jc], received: [o.id: 1000],
                           customers: [c.id: c], failed: [.jobCards])
        XCTAssertTrue(drafts.filter { $0.kind == .ready }.isEmpty)
    }

    func testEventsFailureSuppressesReady() {
        // The done-signal also comes from karigar events; if those failed we
        // don't know whether the piece is ready. Better silent than wrong.
        let c = customer()
        let o = order("BQ-1", customerId: c.id)
        let jc = card(orderId: o.id)
        let drafts = build(orders: [o], cards: [o.id: jc], received: [o.id: 1000],
                           customers: [c.id: c], failed: [.events])
        XCTAssertTrue(drafts.filter { $0.kind == .ready }.isEmpty)
    }

    func testAppointmentsFailureSuppressesFitting() {
        let c = customer()
        let a = appointment(customerId: c.id, at: d(2026, 7, 28))
        XCTAssertTrue(build(appointments: [a], customers: [c.id: c],
                            failed: [.appointments]).isEmpty)
    }

    // MARK: - Security rule: no un-gated draft carries money

    func testOnlyPaymentDraftsContainRupeeAmounts() {
        // Mixed case on purpose: oReady is fully paid (→ ready draft only),
        // oPay is old and unpaid (→ payment draft). Without oPay the loop
        // would never see the kind the rule is actually about.
        let c = customer()
        let a = appointment(customerId: c.id, at: d(2026, 7, 28))
        let oReady = order("BQ-R", customerId: c.id)
        let jc = card(orderId: oReady.id, status: "ready")
        let oPay = order("BQ-P", customerId: c.id, placed: "2026-07-01T10:00:00Z")
        let drafts = build(appointments: [a], orders: [oReady, oPay],
                           cards: [oReady.id: jc],
                           received: [oReady.id: 1000, oPay.id: 0],
                           customers: [c.id: c])
        XCTAssertTrue(drafts.contains { $0.kind == .payment }, "need a payment draft in the mix")
        for draft in drafts where draft.kind != .payment {
            XCTAssertFalse(draft.message.contains("₹"),
                           "\(draft.kind) message must not contain money — it renders un-gated")
            XCTAssertNil(draft.amountDue)
        }
    }

    // MARK: - Sort + determinism

    func testSortOrderFittingReadyPayment() {
        let c = customer()
        let a = appointment(customerId: c.id, at: d(2026, 7, 28))
        let oReady = order("BQ-R", customerId: c.id)
        let jc = card(orderId: oReady.id, status: "ready")
        let oPay = order("BQ-P", customerId: c.id, placed: "2026-07-01T10:00:00Z")
        let drafts = build(appointments: [a], orders: [oPay, oReady],
                           cards: [oReady.id: jc],
                           received: [oReady.id: 1000, oPay.id: 0],
                           customers: [c.id: c])
        XCTAssertEqual(drafts.map(\.kind), [.fitting, .ready, .payment])
    }

    func testEmptyInputsProduceNoDrafts() {
        XCTAssertTrue(build().isEmpty)
    }
}
