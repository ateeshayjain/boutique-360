import SwiftUI

/// Faint outline templates the designer can lay down as a tracing guide
/// before sketching. Rendered as SwiftUI `Path` — no PNG assets, scales
/// cleanly at any canvas size, no Retina/localization concerns.
///
/// Each shape is drawn into a unit rect (0...1 × 0...1) and scaled by
/// `GarmentTemplateOverlay` to fit the canvas. Keep these symmetrical
/// (left/right mirrored) so the user gets a sensible mid-line.
enum GarmentTemplate: String, CaseIterable, Identifiable {
    case kurta
    case saree
    case blouse
    case shirt

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .kurta:  return "Kurta"
        case .saree:  return "Saree drape"
        case .blouse: return "Blouse"
        case .shirt:  return "Shirt"
        }
    }
    var systemImage: String { "rectangle.dashed" }

    /// Build the silhouette path inside the given rect. Coordinates are
    /// chosen empirically to look "right" rather than to match any
    /// specific measurement system — these are *guides*, not patterns.
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let midX = rect.midX
        var p = Path()

        switch self {
        case .kurta:
            // Knee-length kurta: neck → shoulders → straight sleeves →
            // side seams flaring slightly → hem at ~85% height.
            let neckW = w * 0.08
            let shoulderW = w * 0.30
            let sleeveDrop = h * 0.22
            let waistW = w * 0.28
            let hemW = w * 0.34
            let hemY = h * 0.85
            p.move(to: CGPoint(x: midX - neckW, y: h * 0.10))
            // Neckline
            p.addQuadCurve(to: CGPoint(x: midX + neckW, y: h * 0.10),
                           control: CGPoint(x: midX, y: h * 0.14))
            // Right shoulder
            p.addLine(to: CGPoint(x: midX + shoulderW, y: h * 0.13))
            // Right sleeve
            p.addLine(to: CGPoint(x: midX + shoulderW, y: h * 0.13 + sleeveDrop))
            // Tuck to torso
            p.addLine(to: CGPoint(x: midX + waistW, y: h * 0.40))
            // Side flare to hem
            p.addLine(to: CGPoint(x: midX + hemW, y: hemY))
            // Hem
            p.addLine(to: CGPoint(x: midX - hemW, y: hemY))
            // Mirror back up
            p.addLine(to: CGPoint(x: midX - waistW, y: h * 0.40))
            p.addLine(to: CGPoint(x: midX - shoulderW, y: h * 0.13 + sleeveDrop))
            p.addLine(to: CGPoint(x: midX - shoulderW, y: h * 0.13))
            p.closeSubpath()

        case .saree:
            // Saree drape: blouse area + pleat trapezoid + pallu drape on
            // the left shoulder.
            // Pleat trapezoid (centre)
            p.move(to: CGPoint(x: midX - w * 0.22, y: h * 0.30))
            p.addLine(to: CGPoint(x: midX + w * 0.22, y: h * 0.30))
            p.addLine(to: CGPoint(x: midX + w * 0.32, y: h * 0.90))
            p.addLine(to: CGPoint(x: midX - w * 0.32, y: h * 0.90))
            p.closeSubpath()
            // Pallu (left shoulder drape)
            p.move(to: CGPoint(x: midX - w * 0.22, y: h * 0.30))
            p.addQuadCurve(to: CGPoint(x: midX - w * 0.42, y: h * 0.10),
                           control: CGPoint(x: midX - w * 0.35, y: h * 0.18))
            p.addLine(to: CGPoint(x: midX - w * 0.34, y: h * 0.08))
            p.addQuadCurve(to: CGPoint(x: midX - w * 0.12, y: h * 0.28),
                           control: CGPoint(x: midX - w * 0.22, y: h * 0.22))
            p.closeSubpath()

        case .blouse:
            // Cropped blouse: scoop neck, fitted bodice, ends at waist.
            let neckW = w * 0.10
            let shoulderW = w * 0.30
            let bustW = w * 0.27
            let waistY = h * 0.55
            p.move(to: CGPoint(x: midX - neckW, y: h * 0.20))
            p.addQuadCurve(to: CGPoint(x: midX + neckW, y: h * 0.20),
                           control: CGPoint(x: midX, y: h * 0.28))
            p.addLine(to: CGPoint(x: midX + shoulderW, y: h * 0.22))
            // Cap sleeve
            p.addLine(to: CGPoint(x: midX + shoulderW + w * 0.04, y: h * 0.30))
            p.addLine(to: CGPoint(x: midX + bustW, y: h * 0.38))
            p.addLine(to: CGPoint(x: midX + bustW, y: waistY))
            p.addLine(to: CGPoint(x: midX - bustW, y: waistY))
            p.addLine(to: CGPoint(x: midX - bustW, y: h * 0.38))
            p.addLine(to: CGPoint(x: midX - shoulderW - w * 0.04, y: h * 0.30))
            p.addLine(to: CGPoint(x: midX - shoulderW, y: h * 0.22))
            p.closeSubpath()

        case .shirt:
            // Western shirt: collar, button placket, full sleeves to wrist.
            let collarW = w * 0.07
            let shoulderW = w * 0.32
            let sleeveDrop = h * 0.50
            let hemY = h * 0.85
            // Body
            p.move(to: CGPoint(x: midX - collarW, y: h * 0.12))
            p.addLine(to: CGPoint(x: midX - collarW * 0.4, y: h * 0.20))
            p.addLine(to: CGPoint(x: midX + collarW * 0.4, y: h * 0.20))
            p.addLine(to: CGPoint(x: midX + collarW, y: h * 0.12))
            p.addLine(to: CGPoint(x: midX + shoulderW, y: h * 0.16))
            // Right sleeve outer
            p.addLine(to: CGPoint(x: midX + shoulderW + w * 0.04, y: h * 0.16 + sleeveDrop))
            p.addLine(to: CGPoint(x: midX + shoulderW - w * 0.04, y: h * 0.16 + sleeveDrop))
            // Tuck back to torso
            p.addLine(to: CGPoint(x: midX + shoulderW - w * 0.10, y: h * 0.45))
            // Side seam
            p.addLine(to: CGPoint(x: midX + w * 0.24, y: hemY))
            // Hem
            p.addLine(to: CGPoint(x: midX - w * 0.24, y: hemY))
            // Mirror
            p.addLine(to: CGPoint(x: midX - shoulderW + w * 0.10, y: h * 0.45))
            p.addLine(to: CGPoint(x: midX - shoulderW + w * 0.04, y: h * 0.16 + sleeveDrop))
            p.addLine(to: CGPoint(x: midX - shoulderW - w * 0.04, y: h * 0.16 + sleeveDrop))
            p.addLine(to: CGPoint(x: midX - shoulderW, y: h * 0.16))
            p.closeSubpath()
            // Centre placket line
            p.move(to: CGPoint(x: midX, y: h * 0.20))
            p.addLine(to: CGPoint(x: midX, y: hemY - h * 0.02))
        }
        return p
    }
}

/// Renders a chosen template as a faint dashed outline that sits below
/// fabric overlays + strokes in `SketchCanvasView`'s ZStack.
struct GarmentTemplateOverlay: View {
    let template: GarmentTemplate

    var body: some View {
        GeometryReader { geo in
            template.path(in: geo.frame(in: .local))
                .stroke(
                    Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                       lineJoin: .round, dash: [6, 4])
                )
                .allowsHitTesting(false) // never block strokes
        }
        .accessibilityLabel("\(template.displayName) outline guide")
    }
}
