import XCTest
@testable import Boutique360

/// R4b — the gated-surface register.
final class RolePolicyTests: XCTestCase {
    func testOwnerSeesEverything() {
        for s in RolePolicy.Surface.allCases {
            XCTAssertTrue(RolePolicy.canSee(s, role: .owner), "owner must see \(s)")
        }
    }

    func testAssistantSeesNoGatedSurface() {
        for s in RolePolicy.Surface.allCases {
            XCTAssertFalse(RolePolicy.canSee(s, role: .assistant), "assistant must NOT see \(s)")
        }
    }

    /// Tripwire. A bare `allCases` loop passes automatically for a newly
    /// added case (the rule is "assistant sees none"), so pin the count —
    /// adding a surface fails here until someone consciously reviews where
    /// it's enforced and bumps the number.
    func testSurfaceCountIsPinned() {
        XCTAssertEqual(RolePolicy.Surface.allCases.count, 10)
    }
}
