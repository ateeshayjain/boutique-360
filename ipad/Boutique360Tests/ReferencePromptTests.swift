import XCTest
@testable import Boutique360

final class ReferencePromptTests: XCTestCase {
    func testPromptIncludesGarmentOccasionFabricDescription() {
        let p = PromptTemplates.renderGarmentFromReference(
            garmentType: "lehenga", occasion: "wedding",
            fabricDescription: "emerald Banarasi silk with gold zari",
            fabricImageCount: 2, styleNotes: "heavy border")
        XCTAssertTrue(p.contains("lehenga"))
        XCTAssertTrue(p.contains("wedding"))
        XCTAssertTrue(p.contains("emerald Banarasi silk"))
        XCTAssertTrue(p.contains("heavy border"))
        XCTAssertTrue(p.lowercased().contains("fabric"))
    }
    func testPromptHandlesNilFabricGracefully() {
        let p = PromptTemplates.renderGarmentFromReference(
            garmentType: nil, occasion: nil,
            fabricDescription: nil, fabricImageCount: 0, styleNotes: nil)
        XCTAssertFalse(p.isEmpty)
        XCTAssertTrue(p.lowercased().contains("reference"))
    }
}
