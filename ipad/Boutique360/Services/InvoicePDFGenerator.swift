import Foundation
import PDFKit
import UIKit

/// GST-compliant invoice PDF generator using PDFKit + UIGraphicsPDFRenderer.
/// Layout: A4 portrait, ~24pt margins, header / from / to / line items / totals / footer.
enum InvoicePDFGenerator {
    struct Input {
        let invoiceNumber: String
        let orderNumber: String
        let issuedAt: Date
        let boutiqueName: String
        let boutiqueAddress: String
        let boutiqueGSTIN: String?
        let customerName: String
        let customerPhone: String?
        let customerAddress: String?
        let items: [InvoiceLine]
        let subtotal: Double
        let gstAmount: Double
        let shipping: Double
        let total: Double
        let placeOfSupply: String     // e.g. "Delhi"
        let hsnDefault: String        // e.g. "6204"
    }

    struct InvoiceLine {
        let description: String
        let qty: Int
        let unitPrice: Double
        let gstRate: Double
        let hsnCode: String?
        var subtotal: Double { Double(qty) * unitPrice }
        var gstAmount: Double { subtotal * gstRate / 100 }
        var total: Double { subtotal + gstAmount }
    }

    /// Renders to PDF data. Caller can write to a file URL or upload to Storage.
    static func render(_ input: Input) -> Data {
        // A4: 595.2 × 841.8 pt
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let margin: CGFloat = 36
        let contentRect = pageRect.insetBy(dx: margin, dy: margin)

        let renderer = UIGraphicsPDFRenderer(
            bounds: pageRect,
            format: {
                let f = UIGraphicsPDFRendererFormat()
                f.documentInfo = [
                    kCGPDFContextTitle as String: "Invoice \(input.invoiceNumber)",
                    kCGPDFContextAuthor as String: input.boutiqueName,
                    kCGPDFContextCreator as String: "Boutique 360 iPad",
                ]
                return f
            }()
        )

        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y = contentRect.minY
            // H12 fix: use central Formatters.inr — guarantees en_IN lakh grouping
            // (₹1,31,250). Previous local NumberFormatter() lacked the locale and
            // rendered as ₹131,250 on devices set to en_US locale.
            func money(_ v: Double) -> String { Formatters.inr(v) }

            // Header
            let title = "TAX INVOICE"
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: UIColor.label,
            ]
            (title as NSString).draw(at: CGPoint(x: contentRect.minX, y: y), withAttributes: titleAttrs)
            let invNoAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.label,
            ]
            let invNoStr = "Invoice #\(input.invoiceNumber)"
            let invNoSize = (invNoStr as NSString).size(withAttributes: invNoAttrs)
            (invNoStr as NSString).draw(at: CGPoint(x: contentRect.maxX - invNoSize.width, y: y + 2), withAttributes: invNoAttrs)
            y += 32

            let dateStr = "Issued: \(input.issuedAt.formatted(date: .long, time: .omitted))"
            let smallAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel,
            ]
            (dateStr as NSString).draw(at: CGPoint(x: contentRect.minX, y: y), withAttributes: smallAttrs)
            let orderStr = "Order #\(input.orderNumber)"
            let orderSize = (orderStr as NSString).size(withAttributes: smallAttrs)
            (orderStr as NSString).draw(at: CGPoint(x: contentRect.maxX - orderSize.width, y: y), withAttributes: smallAttrs)
            y += 20

            // Separator
            ctx.cgContext.setStrokeColor(UIColor.separator.cgColor)
            ctx.cgContext.setLineWidth(0.5)
            ctx.cgContext.move(to: CGPoint(x: contentRect.minX, y: y))
            ctx.cgContext.addLine(to: CGPoint(x: contentRect.maxX, y: y))
            ctx.cgContext.strokePath()
            y += 16

            // From / To columns
            let colW = (contentRect.width - 20) / 2
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel,
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.label,
            ]

            ("FROM" as NSString).draw(at: CGPoint(x: contentRect.minX, y: y), withAttributes: labelAttrs)
            ("BILL TO" as NSString).draw(at: CGPoint(x: contentRect.minX + colW + 20, y: y), withAttributes: labelAttrs)
            y += 14

            let fromText = """
            \(input.boutiqueName)
            \(input.boutiqueAddress)
            \(input.boutiqueGSTIN.map { "GSTIN: \($0)" } ?? "")
            """
            let toText = """
            \(input.customerName)
            \(input.customerPhone ?? "")
            \(input.customerAddress ?? "")
            """
            drawMultiline(fromText, in: CGRect(x: contentRect.minX, y: y, width: colW, height: 80), attrs: bodyAttrs)
            drawMultiline(toText, in: CGRect(x: contentRect.minX + colW + 20, y: y, width: colW, height: 80), attrs: bodyAttrs)
            y += 80

            ("Place of supply: \(input.placeOfSupply)" as NSString).draw(at: CGPoint(x: contentRect.minX, y: y), withAttributes: smallAttrs)
            y += 24

            // Items table header
            let colDesc = contentRect.minX
            let colHsn = contentRect.minX + 260
            let colQty = contentRect.minX + 310
            let colRate = contentRect.minX + 360
            let colGst = contentRect.minX + 420
            // Amount column is right-aligned per row (see `amountSize` math below),
            // so no fixed left edge is needed.

            let headerBgRect = CGRect(x: contentRect.minX - 4, y: y - 2, width: contentRect.width + 8, height: 22)
            UIColor.secondarySystemBackground.setFill()
            UIBezierPath(roundedRect: headerBgRect, cornerRadius: 4).fill()

            let hAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel,
            ]
            ("DESCRIPTION" as NSString).draw(at: CGPoint(x: colDesc, y: y + 3), withAttributes: hAttrs)
            ("HSN" as NSString).draw(at: CGPoint(x: colHsn, y: y + 3), withAttributes: hAttrs)
            ("QTY" as NSString).draw(at: CGPoint(x: colQty, y: y + 3), withAttributes: hAttrs)
            ("RATE" as NSString).draw(at: CGPoint(x: colRate, y: y + 3), withAttributes: hAttrs)
            ("GST" as NSString).draw(at: CGPoint(x: colGst, y: y + 3), withAttributes: hAttrs)
            let amtSize = ("AMOUNT" as NSString).size(withAttributes: hAttrs)
            ("AMOUNT" as NSString).draw(at: CGPoint(x: contentRect.maxX - amtSize.width, y: y + 3), withAttributes: hAttrs)
            y += 26

            let cellAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.label,
            ]
            for line in input.items {
                (line.description as NSString).draw(in: CGRect(x: colDesc, y: y, width: 240, height: 30), withAttributes: cellAttrs)
                ((line.hsnCode ?? input.hsnDefault) as NSString).draw(at: CGPoint(x: colHsn, y: y), withAttributes: cellAttrs)
                ("\(line.qty)" as NSString).draw(at: CGPoint(x: colQty, y: y), withAttributes: cellAttrs)
                (money(line.unitPrice) as NSString).draw(at: CGPoint(x: colRate, y: y), withAttributes: cellAttrs)
                ("\(Int(line.gstRate))%" as NSString).draw(at: CGPoint(x: colGst, y: y), withAttributes: cellAttrs)
                let amount = money(line.total)
                let amountSize = (amount as NSString).size(withAttributes: cellAttrs)
                (amount as NSString).draw(at: CGPoint(x: contentRect.maxX - amountSize.width, y: y), withAttributes: cellAttrs)
                y += 22
            }

            // Totals
            y += 8
            ctx.cgContext.move(to: CGPoint(x: contentRect.minX + 320, y: y))
            ctx.cgContext.addLine(to: CGPoint(x: contentRect.maxX, y: y))
            ctx.cgContext.strokePath()
            y += 10

            func drawTotalLine(_ label: String, _ value: Double, bold: Bool = false) {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: bold ? .bold : .regular),
                    .foregroundColor: UIColor.label,
                ]
                (label as NSString).draw(at: CGPoint(x: contentRect.minX + 320, y: y), withAttributes: attrs)
                let v = money(value)
                let vSize = (v as NSString).size(withAttributes: attrs)
                (v as NSString).draw(at: CGPoint(x: contentRect.maxX - vSize.width, y: y), withAttributes: attrs)
                y += bold ? 20 : 16
            }
            drawTotalLine("Subtotal", input.subtotal)
            drawTotalLine("GST", input.gstAmount)
            if input.shipping > 0 { drawTotalLine("Shipping", input.shipping) }
            drawTotalLine("TOTAL", input.total, bold: true)

            // Footer
            y = contentRect.maxY - 40
            let footer = "Thank you for your business. This is a computer-generated invoice — no signature required.\nFor queries: contact your boutique."
            drawMultiline(footer, in: CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: 40), attrs: smallAttrs)
        }
    }

    private static func drawMultiline(_ text: String, in rect: CGRect, attrs: [NSAttributedString.Key: Any]) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        var withParagraph = attrs
        withParagraph[.paragraphStyle] = paragraph
        (text as NSString).draw(in: rect, withAttributes: withParagraph)
    }
}
