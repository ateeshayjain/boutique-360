import XCTest
@testable import Boutique360

/// Verify the status state machines match the documented business rules.
/// Adding a new status enum case without updating these tests is the surest
/// way to catch "I added 'in_finishing' but forgot to include it in nextOptions."
final class StatusMachineTests: XCTestCase {

    // MARK: - OrderStatus

    func testOrderPendingCanGoToConfirmedOrCancelled() {
        XCTAssertEqual(Set(OrderStatus.pending.nextOptions), [.confirmed, .cancelled])
    }

    func testOrderDeliveredCanOnlyBeReturned() {
        XCTAssertEqual(OrderStatus.delivered.nextOptions, [.returned])
    }

    func testOrderTerminalStatesHaveNoNext() {
        XCTAssertTrue(OrderStatus.cancelled.nextOptions.isEmpty)
        XCTAssertTrue(OrderStatus.returned.nextOptions.isEmpty)
    }

    func testOrderShippedCanOnlyBeDelivered() {
        XCTAssertEqual(OrderStatus.shipped.nextOptions, [.delivered])
    }

    func testOrderNeverGoesBackwards() {
        // Sanity: no status's nextOptions includes .pending.
        for status in OrderStatus.allCases {
            XCTAssertFalse(status.nextOptions.contains(.pending),
                           "\(status) can transition back to pending — that's a regression")
        }
    }

    // MARK: - InquiryStatus (H8 fix)

    func testInquiryNewCanProgressOrBeLost() {
        let next = Set(InquiryStatus.new.allowedNext)
        XCTAssertTrue(next.contains(.consulting))
        XCTAssertTrue(next.contains(.lost))
    }

    func testInquiryDeliveredAndLostAreTerminal() {
        XCTAssertTrue(InquiryStatus.delivered.allowedNext.isEmpty)
        XCTAssertTrue(InquiryStatus.lost.allowedNext.isEmpty)
    }

    func testInquiryCannotGoBackToNew() {
        // Critical regression guard: this is the bug H8 was created to prevent.
        for status in InquiryStatus.allCases {
            XCTAssertFalse(status.allowedNext.contains(.new),
                           "\(status) can move back to .new — Kanban data corruption risk")
        }
    }

    func testInquiryInProductionCanOnlyMoveToReady() {
        XCTAssertEqual(InquiryStatus.in_production.allowedNext, [.ready])
    }

    func testInquiryReadyCanOnlyMoveToDelivered() {
        XCTAssertEqual(InquiryStatus.ready.allowedNext, [.delivered])
    }

    func testEveryNonTerminalInquiryStateAllowsLost() {
        // Owner can mark any in-flight inquiry as lost if customer ghosts.
        // Exception: terminal pipeline stages (in_production, ready) — by then
        // resources are committed.
        let mustAllowLost: [InquiryStatus] = [.new, .consulting, .measurements, .quoted, .confirmed]
        for state in mustAllowLost {
            XCTAssertTrue(state.allowedNext.contains(.lost),
                          "\(state) should allow marking lost (customer ghosting)")
        }
    }

    // MARK: - Kanban column ordering matches forward flow

    func testKanbanColumnsAreOrderedByForwardFlow() {
        let cols = InquiryStatus.kanbanColumns
        XCTAssertEqual(cols.first, .new)
        XCTAssertEqual(cols.last, .delivered)
        XCTAssertFalse(cols.contains(.lost), ".lost shouldn't be a Kanban column — it's a side exit")
    }
}
