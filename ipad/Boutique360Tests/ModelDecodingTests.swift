import XCTest
@testable import Boutique360

/// Codable round-trip tests for the models that gained new optional columns
/// in the audit-fix cycles. Ensures we can:
///   1. Decode legacy rows that don't have the new columns yet (forward compat).
///   2. Decode current rows with the new columns populated.
///   3. Round-trip values without losing precision.
final class ModelDecodingTests: XCTestCase {

    // MARK: - Boutique.defaultGstRate

    func testBoutiqueDecodesWithoutDefaultGstRate() throws {
        // Legacy row pre-migration 0026 — column doesn't exist.
        let json = """
        {
            "id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e0",
            "name": "Test Boutique",
            "slug": "test",
            "gstin": null,
            "logo_url": null,
            "brand_color_hex": null,
            "address": null,
            "place_of_supply": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let b = try decoder.decode(Boutique.self, from: json)
        XCTAssertEqual(b.name, "Test Boutique")
        XCTAssertNil(b.defaultGstRate, "Missing column should decode as nil, not crash")
    }

    func testBoutiqueDecodesWithDefaultGstRate() throws {
        let json = """
        {
            "id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e0",
            "name": "Test",
            "slug": "test",
            "gstin": "07AABCS1234A1Z5",
            "logo_url": null,
            "brand_color_hex": null,
            "address": "Mumbai",
            "place_of_supply": "Maharashtra",
            "default_gst_rate": 12.0
        }
        """.data(using: .utf8)!

        let b = try JSONDecoder().decode(Boutique.self, from: json)
        XCTAssertEqual(b.defaultGstRate, 12.0)
        XCTAssertEqual(b.gstin, "07AABCS1234A1Z5")
        XCTAssertEqual(b.placeOfSupply, "Maharashtra")
    }

    // MARK: - OrderItem.gstRate

    func testOrderItemDecodesWithoutGstRate() throws {
        // Legacy row pre-migration 0026.
        let json = """
        {
            "id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e0",
            "order_id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e1001",
            "boutique_id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e1002",
            "product_id": null,
            "variant_id": null,
            "qty": 1,
            "unit_price": 25000.0,
            "gst_amount": 1250.0,
            "line_description": "Lehenga - Banarasi silk"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(OrderItem.self, from: json)
        XCTAssertEqual(item.qty, 1)
        XCTAssertEqual(item.unitPrice, 25000.0)
        XCTAssertEqual(item.gstAmount, 1250.0)
        XCTAssertNil(item.gstRate, "Legacy row should decode without gstRate")
    }

    func testOrderItemDecodesWithGstRate() throws {
        let json = """
        {
            "id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e0",
            "order_id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e1001",
            "boutique_id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e1002",
            "product_id": null,
            "variant_id": null,
            "qty": 1,
            "unit_price": 25000.0,
            "gst_rate": 5.0,
            "gst_amount": 1250.0,
            "line_description": "Lehenga"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(OrderItem.self, from: json)
        XCTAssertEqual(item.gstRate, 5.0)
        // Sanity: derived gst_amount matches qty * unit_price * rate / 100
        XCTAssertEqual(item.gstAmount,
                       Double(item.qty) * item.unitPrice * (item.gstRate ?? 0) / 100,
                       accuracy: 0.01)
    }

    // MARK: - Order.fulfillmentMethod (FulfillmentMethod enum)

    /// Order has timestamptz columns; use ISO8601 strategy to mirror Supabase.
    private func orderDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func testOrderDecodesWithFulfillmentMethodAsPickup() throws {
        let json = """
        {
            "id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e0",
            "boutique_id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e1002",
            "order_number": "BTQ-2026-0001",
            "customer_id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e1003",
            "status": "pending",
            "subtotal": 25000.0,
            "gst_amount": 1250.0,
            "shipping": 0,
            "total": 26250.0,
            "currency": "INR",
            "fulfillment_method": "pickup",
            "created_at": "2026-05-26T08:30:00Z",
            "updated_at": "2026-05-26T08:30:00Z"
        }
        """.data(using: .utf8)!

        let order = try orderDecoder().decode(Order.self, from: json)
        XCTAssertEqual(order.fulfillmentMethod, .pickup)
        XCTAssertEqual(order.status, .pending)
    }

    func testOrderDecodesUnknownFulfillmentAsPickup() throws {
        // Future "courier" value — should fall back to pickup, not crash.
        let json = """
        {
            "id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e0",
            "boutique_id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e1002",
            "order_number": "BTQ-2026-0001",
            "customer_id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e1003",
            "status": "pending",
            "subtotal": 0,
            "gst_amount": 0,
            "shipping": 0,
            "total": 0,
            "currency": "INR",
            "fulfillment_method": "courier",
            "created_at": "2026-05-26T08:30:00Z",
            "updated_at": "2026-05-26T08:30:00Z"
        }
        """.data(using: .utf8)!

        let order = try orderDecoder().decode(Order.self, from: json)
        XCTAssertEqual(order.fulfillmentMethod, .pickup,
                       "Unknown fulfillment method should fall back, not throw")
    }

    func testOrderDecodesNullFulfillmentMethod() throws {
        // fulfillment_method is optional on Order — null should decode as nil.
        let json = """
        {
            "id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e0",
            "boutique_id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e1002",
            "order_number": "BTQ-2026-0001",
            "customer_id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e1003",
            "status": "pending",
            "subtotal": 0,
            "gst_amount": 0,
            "shipping": 0,
            "total": 0,
            "currency": "INR",
            "fulfillment_method": null,
            "created_at": "2026-05-26T08:30:00Z",
            "updated_at": "2026-05-26T08:30:00Z"
        }
        """.data(using: .utf8)!

        let order = try orderDecoder().decode(Order.self, from: json)
        XCTAssertNil(order.fulfillmentMethod)
    }

    // MARK: - Design.referenceImagePath

    func testDesignDecodesWithoutReferencePath() throws {
        let json = """
        {
            "id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e0",
            "boutique_id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e0",
            "name": "Test Design",
            "status": "draft",
            "created_at": "2026-05-31T08:00:00Z",
            "updated_at": "2026-05-31T08:00:00Z"
        }
        """.data(using: .utf8)!

        let d = try orderDecoder().decode(Design.self, from: json)
        XCTAssertNil(d.referenceImagePath, "Missing column should decode as nil, not crash")
    }

    func testDesignDecodesWithReferencePath() throws {
        let json = """
        {
            "id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e0",
            "boutique_id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e0",
            "name": "Test Design",
            "status": "draft",
            "created_at": "2026-05-31T08:00:00Z",
            "updated_at": "2026-05-31T08:00:00Z",
            "reference_image_path": "designs/abc/reference.jpg"
        }
        """.data(using: .utf8)!

        let d = try orderDecoder().decode(Design.self, from: json)
        XCTAssertEqual(d.referenceImagePath, "designs/abc/reference.jpg")
    }

    // MARK: - R1: Order event_date + alteration_buffer_days

    func testOrderDecodesEventDateAndBuffer() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "boutique_id":"22222222-2222-2222-2222-222222222222",
         "order_number":"BQ-1","customer_id":"33333333-3333-3333-3333-333333333333",
         "status":"pending","subtotal":100,"gst_amount":5,"total":105,"currency":"INR",
         "event_date":"2026-09-19","alteration_buffer_days":14,
         "created_at":"2026-07-28T10:00:00Z","updated_at":"2026-07-28T10:00:00Z"}
        """.data(using: .utf8)!
        let order = try orderDecoder().decode(Order.self, from: json)
        XCTAssertEqual(order.eventDate, "2026-09-19")
        XCTAssertEqual(order.alterationBufferDays, 14)
    }

    func testOrderDecodesWithoutEventDate() throws {
        // Pre-0028 rows / cached payloads: event_date absent, buffer defaults 7.
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "boutique_id":"22222222-2222-2222-2222-222222222222",
         "order_number":"BQ-2","customer_id":"33333333-3333-3333-3333-333333333333",
         "status":"pending","subtotal":100,"gst_amount":5,"total":105,"currency":"INR",
         "created_at":"2026-07-28T10:00:00Z","updated_at":"2026-07-28T10:00:00Z"}
        """.data(using: .utf8)!
        let order = try orderDecoder().decode(Order.self, from: json)
        XCTAssertNil(order.eventDate)
        XCTAssertEqual(order.alterationBufferDays, 7)
        XCTAssertNil(order.designId)
    }

    // MARK: - R3: designId + OrderLock + ChangeOrder
    // Fixture dates are non-fractional ISO to suit orderDecoder(); production
    // decoding uses the Supabase SDK's fractional-tolerant decoder.

    func testOrderDecodesDesignId() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "boutique_id":"22222222-2222-2222-2222-222222222222",
         "order_number":"BQ-3","customer_id":"33333333-3333-3333-3333-333333333333",
         "status":"pending","subtotal":100,"gst_amount":5,"total":105,"currency":"INR",
         "design_id":"44444444-4444-4444-4444-444444444444",
         "created_at":"2026-07-28T10:00:00Z","updated_at":"2026-07-28T10:00:00Z"}
        """.data(using: .utf8)!
        let order = try orderDecoder().decode(Order.self, from: json)
        XCTAssertEqual(order.designId?.uuidString, "44444444-4444-4444-4444-444444444444")
    }

    func testOrderLockDecodes() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "boutique_id":"22222222-2222-2222-2222-222222222222",
         "order_id":"33333333-3333-3333-3333-333333333333",
         "design_id":null,"render_image_path":null,"fabric_code":"BNRS-EM-01",
         "fabric_description":"emerald banarasi","measurement_id":null,
         "price_breakup":{"fabric":40000,"work":50000,"other":10000},
         "event_date":"2026-09-19","alteration_buffer_days":7,
         "must_finish_by":"2026-09-09","advance_amount":50000,
         "rush_accepted":false,"locked_at":"2026-07-28T10:00:00Z"}
        """.data(using: .utf8)!
        let l = try orderDecoder().decode(OrderLock.self, from: json)
        XCTAssertEqual(l.fabricCode, "BNRS-EM-01")
        XCTAssertEqual(l.priceBreakup?.work, 50000)
        XCTAssertEqual(l.mustFinishBy, "2026-09-09")
    }

    func testChangeOrderDecodesWithNullEventDate() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111",
         "boutique_id":"22222222-2222-2222-2222-222222222222",
         "order_id":"33333333-3333-3333-3333-333333333333",
         "description":"sleeves added","price_delta":1000,
         "new_event_date":null,"created_at":"2026-07-28T10:00:00Z"}
        """.data(using: .utf8)!
        let co = try orderDecoder().decode(ChangeOrder.self, from: json)
        XCTAssertEqual(co.priceDelta, 1000)
        XCTAssertNil(co.newEventDate)
    }

    // MARK: - R4d: JobCardEvent

    func testJobCardEventDecodes() throws {
        let json = """
        {"id":"44444444-4444-4444-4444-444444444444",
         "boutique_id":"22222222-2222-2222-2222-222222222222",
         "job_card_id":"55555555-5555-5555-5555-555555555555",
         "event":"ready","wip_photo_path":null,
         "created_at":"2026-07-28T10:00:00Z"}
        """.data(using: .utf8)!
        let e = try orderDecoder().decode(JobCardEvent.self, from: json)
        XCTAssertEqual(e.event, .ready)
        XCTAssertNil(e.wipPhotoPath)
    }
}
