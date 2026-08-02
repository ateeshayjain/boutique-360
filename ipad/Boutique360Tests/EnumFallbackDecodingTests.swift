import XCTest
@testable import Boutique360

/// Upgrade Path §3 / Sync & Multi-Device §A — "an UNKNOWN raw value from a
/// newer version degrades to a safe fallback on the older version — tested
/// per enum, not assumed."
///
/// The failure this prevents: v1 of the app fetches a row written by v2 whose
/// status is `refunded`. Without a fallback the enum throws, the *whole list
/// decode* fails, and the owner sees an empty Orders screen with no
/// explanation — one new value in one row taking out every row.
final class EnumFallbackDecodingTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, raw: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data("\"\(raw)\"".utf8))
    }

    // MARK: - The high-stakes one

    /// OrderStatus gets a real `.unknown` case rather than falling back to an
    /// existing status, because every other case is a claim about a customer's
    /// money and garment.
    func testUnknownOrderStatusDecodesToUnknown() throws {
        XCTAssertEqual(try decode(OrderStatus.self, raw: "refunded"), .unknown)
        XCTAssertEqual(try decode(OrderStatus.self, raw: ""), .unknown)
        XCTAssertEqual(try decode(OrderStatus.self, raw: "PENDING"), .unknown,
                       "raw values are case-sensitive; a case-mangled value is still unknown")
    }

    func testKnownOrderStatusStillDecodesExactly() throws {
        XCTAssertEqual(try decode(OrderStatus.self, raw: "pending"), .pending)
        XCTAssertEqual(try decode(OrderStatus.self, raw: "delivered"), .delivered)
    }

    /// The safety property: an unknown status offers NO transitions, so nobody
    /// can advance an order whose real state this build cannot see.
    func testUnknownOrderStatusOffersNoTransitions() {
        XCTAssertTrue(OrderStatus.unknown.nextOptions.isEmpty)
    }

    func testUnknownOrderStatusIsNotMistakenForActionableWork() {
        // It must not appear as "in production" or similar in aggregations.
        XCTAssertFalse(OrderStatus.unknown.isActive)
    }

    // MARK: - The rest fall back to an existing benign case

    func testUnknownInquiryStatusFallsBack() throws {
        XCTAssertEqual(try decode(InquiryStatus.self, raw: "ghosted"), .new)
    }

    func testUnknownJobCardStatusFallsBack() throws {
        XCTAssertEqual(try decode(JobCardStatus.self, raw: "reworked"), .draft)
    }

    func testUnknownDesignStatusFallsBack() throws {
        XCTAssertEqual(try decode(DesignStatus.self, raw: "remixed"), .draft)
    }

    func testUnknownAlterationStatusFallsBack() throws {
        XCTAssertEqual(try decode(AlterationStatus.self, raw: "disputed"), .requested)
    }

    func testUnknownAppointmentTypeFallsBackToOther() throws {
        // `other` already exists and means exactly this.
        XCTAssertEqual(try decode(AppointmentType.self, raw: "video_call"), .other)
    }

    func testUnknownAppointmentStatusFallsBack() throws {
        XCTAssertEqual(try decode(AppointmentStatus.self, raw: "rescheduled"), .scheduled)
    }

    func testUnknownGarmentTypeFallsBackToOther() throws {
        XCTAssertEqual(try decode(GarmentType.self, raw: "sherwani"), .other)
    }

    func testUnknownRenderStatusFallsBackToFailed() throws {
        // Not `.done` — claiming a render succeeded when we can't tell is the
        // wrong direction to be wrong in.
        XCTAssertEqual(try decode(RenderStatus.self, raw: "moderated"), .failed)
    }

    func testUnknownFulfillmentMethodFallsBackToPickup() throws {
        // Matches the DB default.
        XCTAssertEqual(try decode(FulfillmentMethod.self, raw: "drone"), .pickup)
    }

    // MARK: - A whole row still decodes

    /// The point of all of the above: one unfamiliar value must not take out
    /// the row it sits in.
    func testOrderRowWithUnknownStatusStillDecodes() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "boutique_id":"22222222-2222-2222-2222-222222222222",
         "customer_id":"33333333-3333-3333-3333-333333333333",
         "order_number":"BTQ-2026-0009","status":"refunded",
         "subtotal":1000,"gst_amount":50,"total":1050,
         "currency":"INR","created_at":"2026-08-01T10:00:00Z",
         "updated_at":"2026-08-01T10:00:00Z"}
        """
        // Same strategy the app's decoder uses for timestamptz columns.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let order = try decoder.decode(Order.self, from: Data(json.utf8))
        XCTAssertEqual(order.status, .unknown)
        XCTAssertEqual(order.orderNumber, "BTQ-2026-0009")
    }
}
