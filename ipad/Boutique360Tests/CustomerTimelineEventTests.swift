import XCTest
@testable import Boutique360

final class CustomerTimelineEventTests: XCTestCase {

    func testIdEqualityRequiresAllThreeComponents() {
        let now = Date()
        let id1 = CustomerTimelineEvent.ID(kind: .orderPlaced, sourceId: UUID(), at: now)
        let id2 = CustomerTimelineEvent.ID(kind: .orderPlaced, sourceId: UUID(), at: now)
        XCTAssertNotEqual(id1, id2, "Different source IDs should produce different IDs even at same instant")

        let sharedSource = UUID()
        let id3 = CustomerTimelineEvent.ID(kind: .orderPlaced, sourceId: sharedSource, at: now)
        let id4 = CustomerTimelineEvent.ID(kind: .orderPlaced, sourceId: sharedSource, at: now)
        XCTAssertEqual(id3, id4)

        let id5 = CustomerTimelineEvent.ID(kind: .orderStatusChanged, sourceId: sharedSource, at: now)
        XCTAssertNotEqual(id3, id5, "Different kind on same source = different event")
    }

    func testEventConvenienceAccessors() {
        let source = UUID()
        let when = Date()
        let event = CustomerTimelineEvent(
            id: .init(kind: .paymentCaptured, sourceId: source, at: when),
            title: "₹20,000 received",
            subtitle: "BTQ-2026-0042 · UPI"
        )
        XCTAssertEqual(event.at, when)
        XCTAssertEqual(event.kind, .paymentCaptured)
    }

    func testKindHasIconForEveryCase() {
        // If a new Kind is added without a systemImage mapping, this catches it
        // at compile time via exhaustiveness; here we just sanity-check non-empty.
        for kind in [CustomerTimelineEvent.Kind.customerJoined,
                     .inquiryCreated, .inquiryStatusChanged,
                     .measurementTaken,
                     .designCreated, .designSketchSaved, .designRendered, .designTryOn,
                     .orderPlaced, .orderStatusChanged,
                     .paymentCaptured,
                     .jobCardIssued,
                     .alterationRequested, .alterationCompleted,
                     .appointmentScheduled, .appointmentCompleted] {
            XCTAssertFalse(kind.systemImage.isEmpty, "\(kind) has no systemImage")
        }
    }

    func testHashableUsableInSet() {
        let now = Date()
        let source = UUID()
        let e1 = CustomerTimelineEvent(
            id: .init(kind: .orderPlaced, sourceId: source, at: now),
            title: "Order placed",
            subtitle: nil
        )
        let e2 = CustomerTimelineEvent(
            id: .init(kind: .orderPlaced, sourceId: source, at: now),
            title: "Order placed",
            subtitle: nil
        )
        let set = Set([e1, e2])
        XCTAssertEqual(set.count, 1, "Equal events should dedupe in a Set")
    }
}
