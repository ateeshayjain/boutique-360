import XCTest
@testable import Boutique360

/// H9 fix verification: enums with custom init(from:) should fall back to a
/// safe default instead of failing decode when the DB returns an unknown value.
/// This protects us if someone adds a new option server-side without shipping
/// a client update.
final class EnumDecodingTests: XCTestCase {

    func testFulfillmentMethodKnownValuesDecode() throws {
        XCTAssertEqual(try decode(FulfillmentMethod.self, "\"pickup\""), .pickup)
        XCTAssertEqual(try decode(FulfillmentMethod.self, "\"ship\""), .ship)
    }

    func testFulfillmentMethodUnknownFallsBackToPickup() throws {
        // Future "courier" value comes back from the DB; we don't crash.
        XCTAssertEqual(try decode(FulfillmentMethod.self, "\"courier\""), .pickup)
    }

    func testGarmentTypeKnownValuesDecode() throws {
        XCTAssertEqual(try decode(GarmentType.self, "\"blouse\""), .blouse)
        XCTAssertEqual(try decode(GarmentType.self, "\"lehenga\""), .lehenga)
    }

    func testGarmentTypeUpperCaseDecodes() throws {
        // The DB might have legacy values in mixed case; decoder lowercases.
        XCTAssertEqual(try decode(GarmentType.self, "\"LEHENGA\""), .lehenga)
        XCTAssertEqual(try decode(GarmentType.self, "\"Blouse\""), .blouse)
    }

    func testGarmentTypeUnknownFallsBackToOther() throws {
        XCTAssertEqual(try decode(GarmentType.self, "\"anarkali\""), .other)
        XCTAssertEqual(try decode(GarmentType.self, "\"sherwani\""), .other)
    }

    // MARK: - Helper

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(T.self, from: data)
    }
}
