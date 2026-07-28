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

    // MARK: - R4c: fabric-meters estimate in the tailor brief

    func testTailorBriefAsksForFabricMetersEstimate() {
        let brief = PromptTemplates.tailorBrief(
            garmentType: "lehenga", occasion: "sangeet", customerNotes: nil,
            fabricList: [], measurements: ["bust": 36], embellishments: nil,
            dueDate: nil, karigarName: nil)
        XCTAssertTrue(brief.contains("meter"), "brief must request a meters estimate")
        XCTAssertTrue(brief.contains("andaaza"), "estimate must be marked approximate in Hinglish")
    }
}
