import XCTest
@testable import Boutique360

/// R3 — spec Unit 3 rules. today = 2026-07-28 throughout.
final class LockGateTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ y: Int, _ m: Int, _ dd: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: dd))!
    }
    private var today: Date { d(2026, 7, 28) }

    private func blockers(advance: Double = 500, event: Date? = nil,
                          fulfillment: FulfillmentMethod? = .pickup,
                          buffer: Int = 7, rush: Bool = false,
                          breakup: (Double, Double, Double)? = nil,
                          subtotal: Double = 1000) -> [LockGate.Blocker] {
        LockGate.blockers(advancePaid: advance, eventDate: event,
                          fulfillment: fulfillment, alterationBufferDays: buffer,
                          rushAccepted: rush,
                          breakup: breakup.map { (fabric: $0.0, work: $0.1, other: $0.2) },
                          subtotal: subtotal, today: today, calendar: cal)
    }

    func testNoAdvanceBlocks() {
        XCTAssertEqual(blockers(advance: 0), [.noAdvance])
    }

    func testAdvancePassesCleanOrder() {
        XCTAssertTrue(blockers().isEmpty)
    }

    func testEventInsideBufferBlocksUnlessRush() {
        // event 8/1: mustFinishBy = 7/25 < today 7/28 → blocked
        let e = d(2026, 8, 1)
        let mf = OrderSlack.mustFinishBy(eventDate: e, fulfillment: .pickup,
                                         alterationBufferDays: 7, calendar: cal)!
        XCTAssertEqual(blockers(event: e), [.eventInsideBuffer(mustFinishBy: mf)])
        XCTAssertTrue(blockers(event: e, rush: true).isEmpty)
    }

    func testMustFinishByTodayPasses() {
        // event 8/4 pickup buffer 7 → mustFinishBy 7/28 == today → OK
        XCTAssertTrue(blockers(event: d(2026, 8, 4)).isEmpty)
    }

    func testBreakupMismatchBlocks() {
        XCTAssertEqual(blockers(breakup: (400, 500, 50)),
                       [.breakupMismatch(sum: 950, subtotal: 1000)])
    }

    func testBreakupExactAtPaisePasses() {
        // Sub-paise drift must not block (FP-safe comparison).
        XCTAssertTrue(blockers(breakup: (400, 500, 99.999999)).isEmpty)
    }

    func testNilBreakupSkipsCheck() {
        XCTAssertTrue(blockers(breakup: nil).isEmpty)
    }

    func testBlockerOrderAdvanceFirst() {
        let e = d(2026, 8, 1)
        let bs = blockers(advance: 0, event: e, breakup: (1, 1, 1))
        XCTAssertEqual(bs.first, .noAdvance)
        XCTAssertEqual(bs.count, 3)
    }
}
