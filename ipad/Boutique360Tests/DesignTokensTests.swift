import XCTest
import SwiftUI
@testable import Boutique360

/// Verify the design tokens match the Apple Design Framework's 8pt grid spec
/// (`docs/superpowers/specs/` references the framework). Adding a new spacing
/// value that breaks the grid will fail these tests at CI time before it lands.
final class DesignTokensTests: XCTestCase {

    // MARK: - Spacing on the 8pt grid (with explicit 4pt micro exception)

    func testMicroIs4ptIconPaddingException() {
        XCTAssertEqual(Spacing.micro, 4)
    }

    func testSmallIs8pt() {
        XCTAssertEqual(Spacing.small, 8)
    }

    func testMediumIs16pt() {
        XCTAssertEqual(Spacing.medium, 16)
    }

    func testLargeIs24pt() {
        XCTAssertEqual(Spacing.large, 24)
    }

    func testXLargeIs32pt() {
        XCTAssertEqual(Spacing.xLarge, 32)
    }

    func testAllSpacingValuesOn4ptSubgrid() {
        // Every value must be divisible by 4 (the framework's micro-grid).
        let values: [CGFloat] = [Spacing.micro, Spacing.small, Spacing.medium, Spacing.large, Spacing.xLarge]
        for v in values {
            XCTAssertEqual(v.truncatingRemainder(dividingBy: 4), 0,
                           "Spacing value \(v) is not on the 4pt subgrid")
        }
    }

    func testNonMicroSpacingOn8ptGrid() {
        // Above the micro exception, every value must be on the 8pt grid proper.
        let values: [CGFloat] = [Spacing.small, Spacing.medium, Spacing.large, Spacing.xLarge]
        for v in values {
            XCTAssertEqual(v.truncatingRemainder(dividingBy: 8), 0,
                           "Spacing value \(v) is not on the 8pt grid")
        }
    }

    // MARK: - Corner radii match HIG spec

    func testCardCornerRadius() {
        XCTAssertEqual(CornerRadius.card, 12)
    }

    func testCardLargeCornerRadius() {
        XCTAssertEqual(CornerRadius.cardLarge, 16)
    }

    func testButtonCornerRadius() {
        // HIG button spec: 16pt corner radius for filled buttons.
        XCTAssertEqual(CornerRadius.button, 16)
    }

    // MARK: - Animation durations in HIG ranges

    func testMicroAnimationInRange() {
        // Framework spec: 100-150ms for micro-interactions.
        XCTAssertGreaterThanOrEqual(AnimationToken.micro, 0.1)
        XCTAssertLessThanOrEqual(AnimationToken.micro, 0.15)
    }

    func testStandardAnimationInRange() {
        // 200-300ms for standard transitions.
        XCTAssertGreaterThanOrEqual(AnimationToken.standard, 0.2)
        XCTAssertLessThanOrEqual(AnimationToken.standard, 0.3)
    }

    func testComplexAnimationInRange() {
        // 300-500ms for complex animations.
        XCTAssertGreaterThanOrEqual(AnimationToken.complex, 0.3)
        XCTAssertLessThanOrEqual(AnimationToken.complex, 0.5)
    }
}
