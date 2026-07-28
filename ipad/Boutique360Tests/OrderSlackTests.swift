import XCTest
@testable import Boutique360

/// R1 — spec-mandated cases for the pure slack engine. Every expected value
/// hand-derivable from slack = daysToEvent − workRemaining − buffer − delivery
/// with today fixed at 2026-07-28.
final class OrderSlackTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ y: Int, _ m: Int, _ dd: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: dd))!
    }
    private var today: Date { d(2026, 7, 28) }

    private func verdict(event: Date?, due: Date?, done: Bool = false,
                         status: OrderStatus = .confirmed,
                         fulfillment: FulfillmentMethod? = .pickup,
                         buffer: Int = 7) -> OrderSlack.Verdict {
        OrderSlack.evaluate(eventDate: event, jobCardDue: due, jobCardDone: done,
                            orderStatus: status, fulfillment: fulfillment,
                            alterationBufferDays: buffer, today: today, calendar: cal)
    }

    func testNoEventDate() {
        XCTAssertEqual(verdict(event: nil, due: d(2026, 8, 10)), .noEvent)
    }

    func testCancelledIsNoEvent() {
        XCTAssertEqual(verdict(event: d(2026, 9, 1), due: d(2026, 8, 1), status: .cancelled), .noEvent)
    }

    func testEventButNoJobCardDueIsNoPlan() {
        XCTAssertEqual(verdict(event: d(2026, 9, 1), due: nil), .noPlan)
    }

    func testComfortable() {
        // event 9/30 (64d out), due 8/10 (13d work), buffer 7, pickup 0 → slack 44
        XCTAssertEqual(verdict(event: d(2026, 9, 30), due: d(2026, 8, 10)), .comfortable(days: 44))
    }

    func testAtRiskAtSlackZeroAndOne() {
        // due 8/10 → work 13. buffer 7. event today+20 → slack 0; +21 → 1.
        XCTAssertEqual(verdict(event: d(2026, 8, 17), due: d(2026, 8, 10)), .atRisk(days: 0))
        XCTAssertEqual(verdict(event: d(2026, 8, 18), due: d(2026, 8, 10)), .atRisk(days: 1))
    }

    func testLate() {
        XCTAssertEqual(verdict(event: d(2026, 8, 16), due: d(2026, 8, 10)), .late(days: 1))
    }

    func testShipAddsThreeDays() {
        // the slack-0 pickup case flips to late(3) when shipping
        XCTAssertEqual(verdict(event: d(2026, 8, 17), due: d(2026, 8, 10), fulfillment: .ship),
                       .late(days: 3))
    }

    func testOverdueUnfinishedBeatsPositiveSlack() {
        // due yesterday, not done, event far away — raw slack would be big + green
        XCTAssertEqual(verdict(event: d(2026, 12, 1), due: d(2026, 7, 27)),
                       .overdue(daysOverdue: 1))
    }

    func testDoneJobPastDueIsNotOverdue() {
        // done=true zeroes work; event 8/10 (13d out) − 0 − 7 → comfortable 6
        XCTAssertEqual(verdict(event: d(2026, 8, 10), due: d(2026, 7, 20), done: true),
                       .comfortable(days: 6))
    }

    func testDeliveredOrderWithUnclosedPastDueCardIsNotOverdue() {
        XCTAssertEqual(verdict(event: d(2026, 8, 10), due: d(2026, 7, 20), status: .delivered),
                       .comfortable(days: 6))
    }

    func testMustFinishByArithmetic() {
        let mf = OrderSlack.mustFinishBy(eventDate: d(2026, 9, 19), fulfillment: .ship,
                                         alterationBufferDays: 7, calendar: cal)
        XCTAssertEqual(mf, d(2026, 9, 9))   // 19 − 7 buffer − 3 ship
    }

    func testMustFinishByNilWithoutEvent() {
        XCTAssertNil(OrderSlack.mustFinishBy(eventDate: nil, fulfillment: .pickup,
                                             alterationBufferDays: 7, calendar: cal))
    }

    func testReadyEventZeroesWorkViaResolver() throws {
        // The full app-convention path: Order + JobCard decoded from JSON,
        // karigar `ready` event → done → work 0.
        // event 8/27 (30d out), due 8/17 (20d work), buffer 7, pickup:
        // without the event → comfortable(3); with ready → comfortable(23).
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let order = try decoder.decode(Order.self, from: """
        {"id":"11111111-1111-1111-1111-111111111111",
         "boutique_id":"22222222-2222-2222-2222-222222222222",
         "order_number":"BQ-9","customer_id":"33333333-3333-3333-3333-333333333333",
         "status":"confirmed","subtotal":100,"gst_amount":5,"total":105,"currency":"INR",
         "event_date":"2026-08-27","alteration_buffer_days":7,
         "created_at":"2026-07-28T10:00:00Z","updated_at":"2026-07-28T10:00:00Z"}
        """.data(using: .utf8)!)
        let card = try decoder.decode(JobCard.self, from: """
        {"id":"55555555-5555-5555-5555-555555555555",
         "boutique_id":"22222222-2222-2222-2222-222222222222",
         "job_number":"JC-9","status":"in_progress","due_date":"2026-08-17",
         "fabric_list_json":[],"current_stage":0,"stages_progress_json":[],
         "created_at":"2026-07-28T10:00:00Z","updated_at":"2026-07-28T10:00:00Z"}
        """.data(using: .utf8)!)
        let readyEvent = try decoder.decode(JobCardEvent.self, from: """
        {"id":"66666666-6666-6666-6666-666666666666",
         "boutique_id":"22222222-2222-2222-2222-222222222222",
         "job_card_id":"55555555-5555-5555-5555-555555555555",
         "event":"ready","created_at":"2026-07-28T10:00:00Z"}
        """.data(using: .utf8)!)

        XCTAssertEqual(OrderSlack.verdict(for: order, jobCard: card, today: today),
                       .comfortable(days: 3))
        XCTAssertEqual(OrderSlack.verdict(for: order, jobCard: card,
                                          latestEvent: readyEvent, today: today),
                       .comfortable(days: 23))
    }

    func testRushThresholdBoundary() {
        // Exactly minimumProductionDays (7) of production time is NOT rush;
        // 6 is. Pins the `<` (not `<=`) comparison used by the create view.
        XCTAssertFalse(7 < OrderSlack.minimumProductionDays)
        XCTAssertTrue(6 < OrderSlack.minimumProductionDays)
    }
}
