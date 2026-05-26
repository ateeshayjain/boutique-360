import Foundation
import PDFKit
import UIKit

/// A4 portrait Job Card PDF.
///
/// Layout (hybrid format):
///   ┌──────────────────────────────────────────────────┐
///   │  TOP — STRUCTURED VISUAL                         │
///   │  Header: Job #, Due date, Customer, Garment      │
///   │  ┌─ Sketch ─┐  ┌─ Render ─┐                      │
///   │  │          │  │          │                      │
///   │  └──────────┘  └──────────┘                      │
///   │  Measurements (24pt monospaced grid)             │
///   │  Fabric list (rows)                              │
///   │  Embellishments + special instructions           │
///   ├──────────────────────────────────────────────────┤
///   │  BOTTOM — HINGLISH BRIEF                         │
///   │  "Raju bhai, ye lehenga banana hai 15 Dec tak…"  │
///   └──────────────────────────────────────────────────┘
enum JobCardPDFGenerator {
    struct Input {
        let jobNumber: String
        let dueDate: String?
        let boutiqueName: String
        let customerName: String
        let garmentType: String?
        let occasion: String?
        let measurements: [String: Double]?
        let fabrics: [FabricLine]
        let embellishments: String?
        let specialInstructions: String?
        let hindiBrief: String?
        let sketchImage: UIImage?
        let renderImage: UIImage?
    }

    static func render(_ input: Input) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)  // A4
        let margin: CGFloat = 32
        let content = pageRect.insetBy(dx: margin, dy: margin)

        let renderer = UIGraphicsPDFRenderer(
            bounds: pageRect,
            format: {
                let f = UIGraphicsPDFRendererFormat()
                f.documentInfo = [
                    kCGPDFContextTitle as String: "Job Card \(input.jobNumber)",
                    kCGPDFContextAuthor as String: input.boutiqueName,
                    kCGPDFContextCreator as String: "Boutique 360 iPad",
                ]
                return f
            }()
        )

        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y = content.minY

            // Header
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.label,
            ]
            ("JOB CARD" as NSString).draw(at: CGPoint(x: content.minX, y: y), withAttributes: titleAttrs)

            let jobNoAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: UIColor.label,
            ]
            let jobNoStr = input.jobNumber
            let jobNoSize = (jobNoStr as NSString).size(withAttributes: jobNoAttrs)
            (jobNoStr as NSString).draw(at: CGPoint(x: content.maxX - jobNoSize.width, y: y + 4), withAttributes: jobNoAttrs)
            y += 32

            // Boutique + customer + garment row
            let metaAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel,
            ]
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: UIColor.tertiaryLabel,
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: UIColor.label,
            ]

            let colW: CGFloat = (content.width - 24) / 4
            func drawMeta(at index: Int, label: String, value: String) {
                let x = content.minX + CGFloat(index) * (colW + 8)
                (label as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: labelAttrs)
                (value as NSString).draw(at: CGPoint(x: x, y: y + 14), withAttributes: bodyAttrs)
            }
            drawMeta(at: 0, label: "CUSTOMER", value: input.customerName)
            drawMeta(at: 1, label: "GARMENT", value: input.garmentType ?? "—")
            drawMeta(at: 2, label: "OCCASION", value: input.occasion ?? "—")
            drawMeta(at: 3, label: "DUE BY", value: input.dueDate ?? "—")
            y += 44

            // Separator
            ctx.cgContext.setStrokeColor(UIColor.separator.cgColor)
            ctx.cgContext.setLineWidth(0.5)
            ctx.cgContext.move(to: CGPoint(x: content.minX, y: y))
            ctx.cgContext.addLine(to: CGPoint(x: content.maxX, y: y))
            ctx.cgContext.strokePath()
            y += 12

            // Sketch + render side by side (each 240pt wide)
            if input.sketchImage != nil || input.renderImage != nil {
                let imageW: CGFloat = (content.width - 16) / 2
                let imageH: CGFloat = 200

                if let sketch = input.sketchImage {
                    let rect = CGRect(x: content.minX, y: y, width: imageW, height: imageH)
                    sketch.draw(in: aspectFit(sketch.size, into: rect))
                    ("SKETCH" as NSString).draw(at: CGPoint(x: content.minX + 4, y: y + imageH - 14), withAttributes: labelAttrs)
                }
                if let render = input.renderImage {
                    let rect = CGRect(x: content.minX + imageW + 16, y: y, width: imageW, height: imageH)
                    render.draw(in: aspectFit(render.size, into: rect))
                    ("AI RENDER" as NSString).draw(at: CGPoint(x: content.minX + imageW + 20, y: y + imageH - 14), withAttributes: labelAttrs)
                }
                y += imageH + 16
            }

            // Measurements — bold, large, monospaced
            if let m = input.measurements, !m.isEmpty {
                ("MEASUREMENTS (inches)" as NSString).draw(at: CGPoint(x: content.minX, y: y), withAttributes: labelAttrs)
                y += 16

                let measureAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: UIColor.label,
                ]
                let perRow = 3
                let cellW = content.width / CGFloat(perRow)
                let pairs = m.sorted { $0.key < $1.key }
                for (i, kv) in pairs.enumerated() {
                    let col = i % perRow
                    let row = i / perRow
                    let x = content.minX + CGFloat(col) * cellW
                    let yPos = y + CGFloat(row) * 22
                    let label = kv.key.replacingOccurrences(of: "_", with: " ").capitalized
                    let valueStr = String(format: "%.1f", kv.value)
                    let str = "\(label):  \(valueStr)\""
                    (str as NSString).draw(at: CGPoint(x: x, y: yPos), withAttributes: measureAttrs)
                }
                y += CGFloat((pairs.count + perRow - 1) / perRow) * 22 + 12
            }

            // Fabrics
            if !input.fabrics.isEmpty {
                ("FABRIC" as NSString).draw(at: CGPoint(x: content.minX, y: y), withAttributes: labelAttrs)
                y += 14
                for f in input.fabrics {
                    var line = "• \(f.name)"
                    if let c = f.color { line += " (\(c))" }
                    line += " — \(String(format: "%.1f", f.quantityMeters)) m"
                    if let r = f.role { line += "  [\(r)]" }
                    (line as NSString).draw(at: CGPoint(x: content.minX + 4, y: y), withAttributes: bodyAttrs)
                    y += 18
                }
                y += 6
            }

            // Embellishments
            if let e = input.embellishments, !e.isEmpty {
                ("EMBROIDERY / WORK" as NSString).draw(at: CGPoint(x: content.minX, y: y), withAttributes: labelAttrs)
                y += 14
                drawWrapped(e, in: CGRect(x: content.minX + 4, y: y, width: content.width - 8, height: 60), attrs: metaAttrs)
                y += 36
            }

            // Special instructions
            if let s = input.specialInstructions, !s.isEmpty {
                ("SPECIAL INSTRUCTIONS" as NSString).draw(at: CGPoint(x: content.minX, y: y), withAttributes: labelAttrs)
                y += 14
                drawWrapped(s, in: CGRect(x: content.minX + 4, y: y, width: content.width - 8, height: 60), attrs: metaAttrs)
                y += 36
            }

            // Separator
            ctx.cgContext.move(to: CGPoint(x: content.minX, y: y))
            ctx.cgContext.addLine(to: CGPoint(x: content.maxX, y: y))
            ctx.cgContext.strokePath()
            y += 12

            // Hinglish brief
            if let brief = input.hindiBrief, !brief.isEmpty {
                ("TAILOR BRIEF" as NSString).draw(at: CGPoint(x: content.minX, y: y), withAttributes: labelAttrs)
                y += 16
                let briefAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: UIColor.label,
                ]
                let remaining = content.maxY - y - 32
                drawWrapped(brief, in: CGRect(x: content.minX + 4, y: y, width: content.width - 8, height: remaining), attrs: briefAttrs)
            }

            // Footer
            let footer = "Generated by Boutique 360 · \(input.boutiqueName) · \(Date().formatted(date: .abbreviated, time: .shortened))"
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8, weight: .regular),
                .foregroundColor: UIColor.tertiaryLabel,
            ]
            (footer as NSString).draw(at: CGPoint(x: content.minX, y: content.maxY - 12), withAttributes: footerAttrs)
        }
    }

    private static func drawWrapped(_ text: String, in rect: CGRect, attrs: [NSAttributedString.Key: Any]) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 3
        var combined = attrs
        combined[.paragraphStyle] = paragraph
        (text as NSString).draw(in: rect, withAttributes: combined)
    }

    private static func aspectFit(_ image: CGSize, into rect: CGRect) -> CGRect {
        let scale = min(rect.width / image.width, rect.height / image.height)
        let w = image.width * scale
        let h = image.height * scale
        let x = rect.minX + (rect.width - w) / 2
        let y = rect.minY + (rect.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
