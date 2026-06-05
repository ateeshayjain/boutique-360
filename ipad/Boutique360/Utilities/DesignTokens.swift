import SwiftUI

/// Named design tokens — per the Apple Design Framework's 8pt grid system.
/// Use these instead of raw numeric values so design adjustments happen in one place
/// and the codebase carries explicit token discipline.
///
/// HIG audit fix: spacing previously inlined as `.padding(8)`, `.padding(16)` etc.
/// Numbers were correct (on the 8pt grid) but not named — future adjustments would
/// require grepping for every magic number.
enum Spacing {
    static let micro: CGFloat = 4    // Icon padding, fine adjustments
    static let small: CGFloat = 8    // Related element spacing
    static let medium: CGFloat = 16  // Section padding, card margins
    static let large: CGFloat = 24   // Major section breaks
    static let xLarge: CGFloat = 32  // Screen-level padding
}

/// Corner radii from the HIG component spec.
enum CornerRadius {
    static let card: CGFloat = 12        // Standard cards
    static let cardLarge: CGFloat = 16   // Large feature cards
    static let chip: CGFloat = 10        // Tag chips, status pills (uses Capsule too)
    static let button: CGFloat = 16      // Filled buttons per HIG
}

/// Animation durations (HIG-compliant easing).
enum AnimationToken {
    static let micro: Double = 0.15      // Micro-interactions
    static let standard: Double = 0.25   // Page/state transitions
    static let complex: Double = 0.4     // Reveals
}
