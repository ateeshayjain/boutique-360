import Foundation

/// Produces CA-friendly CSVs for monthly GST filing (GSTR-1 source data).
///
/// Output columns match what most Indian CAs paste into the GST portal:
/// invoice number, date, customer GSTIN (blank for B2C), place of supply,
/// taxable value, CGST, SGST, IGST, total. Aggregating into GSTR-1 JSON
/// is the CA's job; we just make the source data trivial to consume.
enum GSTReportExporter {
    /// Build CSV for orders whose `placedAt` (or `createdAt`) falls in [start, end).
    /// Returns the CSV bytes + a suggested filename. Caller hands to ShareLink.
    struct Bundle {
        let data: Data
        let filename: String
        let rowCount: Int
        let totalTaxable: Double
        let totalTax: Double
        /// Number of orders flagged for shipment — CA should spot-check whether
        /// any of these are inter-state (would need IGST not CGST/SGST).
        let interStateUnknown: Int
    }

    /// H11 fix: `throws` so caller can refuse to export on partial data
    /// (which previously produced an empty "₹0 turnover" CSV that the CA filed).
    /// M7 fix: IST-locked calendar so month boundaries don't drift in other timezones.
    static func monthly(year: Int, month: Int, boutique: Boutique) async throws -> Bundle {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        var startComps = DateComponents(); startComps.year = year; startComps.month = month; startComps.day = 1
        let start = cal.date(from: startComps) ?? Date()
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? Date()

        // Throw instead of `?? []` — empty CSV silently filed by CA = statutory offense.
        let orders = try await OrdersService.list()
        let scoped = orders.filter { o in
            let date = o.placedAt ?? o.createdAt
            return date >= start && date < end
                && o.status != .cancelled
        }
        let customers = try await CustomersService.list()
        let custMap = Dictionary(uniqueKeysWithValues: customers.map { ($0.id, $0) })

        let placeOfSupply = boutique.placeOfSupply ?? "—"

        var rows: [[String]] = [[
            "Invoice #", "Order #", "Date", "Customer name", "Customer phone",
            "Place of supply", "Taxable value (₹)",
            "CGST (₹)", "SGST (₹)", "IGST (₹)",
            "Shipping (₹)", "Total (₹)"
        ]]

        var totalTaxable = 0.0
        var totalTax = 0.0
        // H10 fix: track inter-state orders so the caller can surface a warning.
        // We don't yet capture per-order customer state, so the heuristic is
        // "GSTIN starts with a 2-digit state code matching the boutique's state."
        // For pilot the boutique iPad has no customer state, so we always treat
        // as intra-state but expose `interStateUnknown` so the UI can warn the
        // CA to spot-check rows when shipping to another state.
        var interStateUnknown = 0

        for o in scoped {
            let invoiceNo = "INV-\(year)-\(o.orderNumber.split(separator: "-").last.map(String.init) ?? "0001")"
            let cust = custMap[o.customerId]
            let cgst = o.gstAmount / 2
            let sgst = o.gstAmount / 2
            let igst = 0.0
            totalTaxable += o.subtotal
            totalTax += o.gstAmount
            if (o.fulfillmentMethod ?? .pickup) == .ship { interStateUnknown += 1 }

            rows.append([
                invoiceNo,
                o.orderNumber,
                Formatters.postgresDate.string(from: o.placedAt ?? o.createdAt),
                cust?.name ?? "—",
                cust?.phone ?? "",
                placeOfSupply,
                formatAmount(o.subtotal),
                formatAmount(cgst),
                formatAmount(sgst),
                formatAmount(igst),
                formatAmount(o.shipping ?? 0),
                formatAmount(o.total)
            ])
        }

        let csv = rows.map { row in
            row.map(csvEscape).joined(separator: ",")
        }.joined(separator: "\r\n")
        let data = csv.data(using: .utf8) ?? Data()

        // M2 fix: standaloneMonthSymbols from Calendar avoids allocating a DateFormatter just for month names.
        let monthName = Calendar(identifier: .gregorian).standaloneMonthSymbols[max(0, min(11, month - 1))]
        let filename = "GST-\(boutique.gstin ?? "report")-\(monthName)-\(year).csv"

        return Bundle(
            data: data,
            filename: filename,
            rowCount: scoped.count,
            totalTaxable: totalTaxable,
            totalTax: totalTax,
            interStateUnknown: interStateUnknown
        )
    }

    /// CSV escape per RFC 4180: wrap in quotes if value contains comma/quote/newline,
    /// double any embedded quotes.
    /// `internal` (Swift module-default) so unit tests can reach it via @testable import.
    static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    private static func formatAmount(_ v: Double) -> String {
        String(format: "%.2f", v)
    }
}
