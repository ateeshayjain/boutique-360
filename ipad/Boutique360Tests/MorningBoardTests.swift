import XCTest
@testable import Boutique360

/// R2 — every rule from the spec's Unit 1. today = 2026-07-28 throughout.
final class MorningBoardTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ y: Int, _ m: Int, _ dd: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: dd))!
    }
    private var today: Date { d(2026, 7, 28) }
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    private func order(_ num: String, status: String = "confirmed",
                       total: Double = 1000, event: String? = nil,
                       buffer: Int = 7, placed: String = "2026-07-01T10:00:00Z",
                       id: UUID = UUID()) -> Order {
        let eventLine = event.map { "\"event_date\":\"\($0)\"," } ?? ""
        let json = """
        {"id":"\(id.uuidString)",
         "boutique_id":"22222222-2222-2222-2222-222222222222",
         "order_number":"\(num)","customer_id":"33333333-3333-3333-3333-333333333333",
         "status":"\(status)","subtotal":\(total),"gst_amount":0,"total":\(total),
         "currency":"INR",\(eventLine)"alteration_buffer_days":\(buffer),
         "placed_at":"\(placed)",
         "created_at":"2026-07-01T10:00:00Z","updated_at":"2026-07-01T10:00:00Z"}
        """
        return try! decoder.decode(Order.self, from: json.data(using: .utf8)!)
    }

    private func card(orderId: UUID, status: String = "in_progress",
                      due: String? = "2026-08-10", id: UUID = UUID()) -> JobCard {
        let dueLine = due.map { "\"due_date\":\"\($0)\"," } ?? ""
        let json = """
        {"id":"\(id.uuidString)","boutique_id":"22222222-2222-2222-2222-222222222222",
         "job_number":"JC-\(id.uuidString.prefix(4))","order_id":"\(orderId.uuidString)",
         "status":"\(status)",\(dueLine)"fabric_list_json":[],"current_stage":0,
         "stages_progress_json":[],
         "created_at":"2026-07-01T10:00:00Z","updated_at":"2026-07-01T10:00:00Z"}
        """
        return try! decoder.decode(JobCard.self, from: json.data(using: .utf8)!)
    }

    private func readyEvent(cardId: UUID) -> JobCardEvent {
        try! decoder.decode(JobCardEvent.self, from: """
        {"id":"\(UUID().uuidString)","boutique_id":"22222222-2222-2222-2222-222222222222",
         "job_card_id":"\(cardId.uuidString)","event":"ready",
         "created_at":"2026-07-27T10:00:00Z"}
        """.data(using: .utf8)!)
    }

    private func alteration(orderId: UUID, status: String) -> Alteration {
        try! decoder.decode(Alteration.self, from: """
        {"id":"\(UUID().uuidString)","boutique_id":"22222222-2222-2222-2222-222222222222",
         "order_id":"\(orderId.uuidString)","round_number":1,"status":"\(status)",
         "request_notes":"n","created_at":"2026-07-20T10:00:00Z"}
        """.data(using: .utf8)!)
    }

    private func build(orders: [Order] = [],
                       cards: [UUID: JobCard] = [:],
                       events: [UUID: JobCardEvent] = [:],
                       alterations: [Alteration] = [],
                       designing: Int = 0,
                       appointments: Int = 0,
                       received: [UUID: Double] = [:],
                       failures: Set<MorningBoard.Input> = []) -> MorningBoard.Board {
        MorningBoard.build(orders: orders, jobCardsByOrder: cards,
                           latestEventByCard: events, openAlterations: alterations,
                           designingCount: designing, todaysAppointments: appointments,
                           customersById: [:], receivedByOrder: received,
                           failures: failures, today: today, calendar: cal)
    }

    func testEmptyInputsZeroBoard() {
        let b = build()
        XCTAssertTrue(b.needsYou.isEmpty)
        XCTAssertEqual(b.atRiskCount, 0)
        XCTAssertEqual(b.moneyDue, .init(total: 0, orderCount: 0, oldestDays: 0))
        XCTAssertEqual(b.pipeline, .init(designing: 0, toStart: 0, withKarigar: 0, trialAlter: 0, ready: 0))
        XCTAssertEqual(b.todayFittings, 0)
        XCTAssertEqual(b.todayDeliveries, 0)
        XCTAssertTrue(b.failed.isEmpty)
    }

    func testSeverityOrdering() {
        // overdue (due 7/20, event 12/1) → late (event 8/16, due 8/10) →
        // atRisk (event 8/18, due 8/10) → ready (done card, balance 500)
        let o1 = order("BQ-OVD", event: "2026-12-01"); let c1 = card(orderId: o1.id, due: "2026-07-20")
        let o2 = order("BQ-LATE", event: "2026-08-16"); let c2 = card(orderId: o2.id, due: "2026-08-10")
        let o3 = order("BQ-RISK", event: "2026-08-18"); let c3 = card(orderId: o3.id, due: "2026-08-10")
        let o4 = order("BQ-RDY", total: 1000); let c4 = card(orderId: o4.id, status: "ready")
        let b = build(orders: [o4, o3, o2, o1],
                      cards: [o1.id: c1, o2.id: c2, o3.id: c3, o4.id: c4],
                      received: [o4.id: 500])
        XCTAssertEqual(b.needsYou.map(\.orderNumber), ["BQ-OVD", "BQ-LATE", "BQ-RISK", "BQ-RDY"])
        XCTAssertEqual(b.atRiskCount, 3)
        XCTAssertEqual(b.needsYou.last?.action, .deliverAndCollect(500))
    }

    func testReadyBeatsOverdue() {
        // Card past due BUT status ready → ready group, .deliver (paid), not chase.
        let o = order("BQ-RO", event: "2026-08-05")
        let c = card(orderId: o.id, status: "ready", due: "2026-07-20")
        let b = build(orders: [o], cards: [o.id: c], received: [o.id: 1000])
        XCTAssertEqual(b.needsYou.count, 1)
        XCTAssertEqual(b.needsYou[0].action, .deliver)
        XCTAssertEqual(b.atRiskCount, 0)
    }

    func testReadyEventCountsAsDone() {
        let o = order("BQ-EV")
        let c = card(orderId: o.id, status: "in_progress", due: "2026-07-20")
        let b = build(orders: [o], cards: [o.id: c],
                      events: [c.id: readyEvent(cardId: c.id)], received: [o.id: 1000])
        XCTAssertEqual(b.needsYou.first?.action, .deliver)
        XCTAssertEqual(b.pipeline.ready, 1)
    }

    func testMoneyDueExcludesCancelledAndSubPaise() {
        let o1 = order("BQ-1", total: 1000)
        let o2 = order("BQ-2", status: "cancelled", total: 5000)
        let o3 = order("BQ-3", total: 100)
        let b = build(orders: [o1, o2, o3],
                      received: [o1.id: 600, o3.id: 99.999999])
        XCTAssertEqual(b.moneyDue.total, 400, accuracy: 0.01)
        XCTAssertEqual(b.moneyDue.orderCount, 1)
        XCTAssertEqual(b.moneyDue.oldestDays, 27)
    }

    func testPipelineLaneExclusivity() {
        let oNoCard = order("BQ-NC", status: "pending")
        let oDraft = order("BQ-DR"); let cDraft = card(orderId: oDraft.id, status: "draft")
        let oWork = order("BQ-WK"); let cWork = card(orderId: oWork.id, status: "issued")
        let oPacked = order("BQ-PK", status: "packed"); let cPackedReady = card(orderId: oPacked.id, status: "ready")
        let alts = [alteration(orderId: oWork.id, status: "requested"),
                    alteration(orderId: oWork.id, status: "completed")]
        let b = build(orders: [oNoCard, oDraft, oWork, oPacked],
                      cards: [oDraft.id: cDraft, oWork.id: cWork, oPacked.id: cPackedReady],
                      alterations: alts, designing: 2)
        XCTAssertEqual(b.pipeline, .init(designing: 2, toStart: 2, withKarigar: 1,
                                         trialAlter: 1, ready: 1))
        XCTAssertEqual(b.todayDeliveries, 1)
    }

    func testDegradationPassthroughAndPaymentsFailure() {
        let o = order("BQ-RDY2", total: 800)
        let c = card(orderId: o.id, status: "ready")
        let b = build(orders: [o], cards: [o.id: c], received: [:],
                      failures: [.payments])
        XCTAssertEqual(b.failed, [.payments])
        XCTAssertEqual(b.needsYou.first?.action, .deliver)
    }

    func testWithinGroupTieBreakDeterministic() {
        // Two overdue orders, same days-overdue (due 7/20) → tie broken by
        // event date asc (8/10 before 12/1); same event date → order number.
        let oA = order("BQ-B", event: "2026-12-01"); let cA = card(orderId: oA.id, due: "2026-07-20")
        let oB = order("BQ-A", event: "2026-08-10"); let cB = card(orderId: oB.id, due: "2026-07-20")
        let oC = order("BQ-AA", event: "2026-12-01"); let cC = card(orderId: oC.id, due: "2026-07-20")
        let b = build(orders: [oA, oB, oC], cards: [oA.id: cA, oB.id: cB, oC.id: cC])
        XCTAssertEqual(b.needsYou.map(\.orderNumber), ["BQ-A", "BQ-AA", "BQ-B"])
    }

    func testCustomerLookupMissRendersDash() {
        let o = order("BQ-CM", event: "2026-08-16")
        let c = card(orderId: o.id, due: "2026-08-10")
        let b = build(orders: [o], cards: [o.id: c])
        XCTAssertEqual(b.needsYou.first?.customerName, "—")
    }
}
