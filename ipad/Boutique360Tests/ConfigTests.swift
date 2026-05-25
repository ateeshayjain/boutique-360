import XCTest
@testable import Boutique360

final class ConfigTests: XCTestCase {
    func testSupabaseURLLoaded() {
        XCTAssertEqual(Config.supabaseURL.host, "tdnwdlrkbrtoxjzcgusg.supabase.co")
        XCTAssertEqual(Config.supabaseURL.scheme, "https")
    }

    func testSupabaseAnonKeyLoaded() {
        XCTAssertFalse(Config.supabaseAnonKey.isEmpty)
        XCTAssertTrue(Config.supabaseAnonKey.hasPrefix("eyJ"), "Expected JWT-style anon key")
    }
}
