import XCTest
@testable import Boutique360

/// Tests for the Decodable shapes that `PaymentsService` exposes.
/// Network behavior isn't tested here (would need a mocked Supabase client).
/// What we DO test: the JSON shapes Supabase actually returns decode correctly.
final class PaymentsServiceModelTests: XCTestCase {

    func testCapturedRowDecodes() throws {
        let json = """
        {
            "amount": 12000.0,
            "method": "upi",
            "status": "captured",
            "captured_at": "2026-05-26T08:30:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(PaymentsService.CapturedRow.self, from: json)
        XCTAssertEqual(row.amount, 12000.0)
        XCTAssertEqual(row.method, "upi")
        XCTAssertEqual(row.status, "captured")
        XCTAssertNotNil(row.captured_at)
    }

    func testCapturedRowDecodesNilMethod() throws {
        let json = """
        {
            "amount": 5000.0,
            "method": null,
            "status": "captured",
            "captured_at": null
        }
        """.data(using: .utf8)!

        let row = try JSONDecoder().decode(PaymentsService.CapturedRow.self, from: json)
        XCTAssertNil(row.method)
        XCTAssertNil(row.captured_at)
    }

    func testPerOrderSumDecodes() throws {
        let json = """
        {
            "order_id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e0",
            "amount": 25000.0
        }
        """.data(using: .utf8)!

        let row = try JSONDecoder().decode(PaymentsService.PerOrderSum.self, from: json)
        XCTAssertEqual(row.amount, 25000.0)
    }

    func testOrderHistoryRowDecodes() throws {
        let json = """
        {
            "id": "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e0",
            "amount": 20000.0,
            "status": "captured",
            "method": "cash",
            "captured_at": "2026-05-26T15:00:00Z",
            "created_at": "2026-05-26T15:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(PaymentsService.OrderHistoryRow.self, from: json)
        XCTAssertEqual(row.amount, 20000.0)
        XCTAssertEqual(row.status, "captured")
        XCTAssertEqual(row.method, "cash")
    }

    func testNewPaymentEncodes() throws {
        let payment = PaymentsService.NewPayment(
            boutique_id: UUID(uuidString: "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e0")!,
            order_id: UUID(uuidString: "8a89e7c2-3e25-4b7f-9e8e-d5e10e0e10e1")!,
            amount: 20000.0,
            status: "captured",
            method: "upi",
            captured_at: "2026-05-26T15:00:00Z"
        )

        let data = try JSONEncoder().encode(payment)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["amount"] as? Double, 20000.0)
        XCTAssertEqual(json?["method"] as? String, "upi")
        XCTAssertEqual(json?["status"] as? String, "captured")
    }
}
