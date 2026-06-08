import Foundation

/// Parses a CSV file of customers and bulk-imports them.
///
/// Required headers: `name`
/// Optional headers: `phone`, `email`, `tags` (semicolon-separated), `source`, `vip`, `whatsapp_consent`, `email_consent`, `dob` (YYYY-MM-DD)
///
/// We accept loose header matching (case-insensitive, trimmed). Anything we
/// don't recognise is ignored so an existing contact-export from another
/// CRM/Sheets file works without prep.
enum CustomerImportService {
    struct ImportRow {
        var name: String
        var phone: String?
        var email: String?
        var tags: [String]
        var source: String
        var vip: Bool
        var whatsappConsent: Bool
        var emailConsent: Bool
        var dob: String?
    }

    struct Report {
        var parsed: [ImportRow]        // rows that survived parsing
        var skipped: [(Int, String)]   // (rowNumber, reason)
        var inserted: Int = 0
        var failed: [(Int, String)] = []
    }

    static func parse(csv text: String) -> Report {
        var report = Report(parsed: [], skipped: [])
        let lines = splitLines(text)
        guard let headerLine = lines.first else { return report }
        let headers = parseRow(headerLine).map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        let idx = Dictionary(uniqueKeysWithValues: headers.enumerated().map { ($1, $0) })
        guard idx["name"] != nil else {
            report.skipped.append((0, "CSV needs a 'name' column"))
            return report
        }
        for (lineNum, line) in lines.enumerated().dropFirst() {
            let cells = parseRow(line)
            func cell(_ key: String) -> String? {
                guard let i = idx[key], i < cells.count else { return nil }
                let v = cells[i].trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
            guard let name = cell("name"), !name.isEmpty else {
                report.skipped.append((lineNum + 1, "missing name"))
                continue
            }
            let row = ImportRow(
                name: name,
                phone: cell("phone"),
                email: cell("email"),
                tags: cell("tags")?.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) } ?? [],
                source: cell("source") ?? "import",
                vip: parseBool(cell("vip")) ?? false,
                whatsappConsent: parseBool(cell("whatsapp_consent")) ?? false,
                emailConsent: parseBool(cell("email_consent")) ?? false,
                dob: cell("dob")
            )
            report.parsed.append(row)
        }
        return report
    }

    /// Insert each row one at a time. We don't use batch insert because we
    /// want per-row failure isolation (one bad phone shouldn't kill the file).
    static func importRows(_ rows: [ImportRow], boutiqueId: UUID) async -> Report {
        var report = Report(parsed: rows, skipped: [])
        for (i, row) in rows.enumerated() {
            do {
                _ = try await CustomersService.create(NewCustomer(
                    boutique_id: boutiqueId,
                    name: row.name,
                    phone: row.phone,
                    // Wave 1: CSV import doesn't know about WA # / structured
                    // address yet (no source column). Leave nil — owner can
                    // edit per-row after import. Adding columns to the import
                    // schema is a separate, additive change.
                    whatsapp_phone: nil,
                    email: row.email,
                    dob: row.dob,
                    address_json: nil,
                    tags: row.tags,
                    vip_status: row.vip,
                    source: row.source,
                    consent_whatsapp: row.whatsappConsent,
                    consent_email: row.emailConsent
                ))
                report.inserted += 1
            } catch {
                report.failed.append((i + 1, error.localizedDescription))
            }
        }
        return report
    }

    // MARK: - CSV parsing (RFC 4180-ish: handles quoted fields with embedded commas/quotes)

    private static func splitLines(_ text: String) -> [String] {
        // Split on \r\n, \n, or \r, but not when inside quoted fields.
        //
        // Subtle Swift trap: iterating `for ch in text` walks grapheme clusters,
        // and "\r\n" is ONE Character (a single CRLF grapheme cluster) — equality
        // checks against "\n" or "\r" both return false. Result: CRLF files would
        // be silently parsed as one giant line. Iterate `unicodeScalars` instead.
        var lines: [String] = []
        var current = ""
        var inQuotes = false
        for scalar in text.unicodeScalars {
            let ch = Character(scalar)
            if ch == "\"" { inQuotes.toggle(); current.append(ch); continue }
            if (ch == "\n" || ch == "\r") && !inQuotes {
                if !current.isEmpty { lines.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    private static func parseRow(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if ch == "\"" {
                if inQuotes, line.index(after: i) < line.endIndex, line[line.index(after: i)] == "\"" {
                    current.append("\"")
                    i = line.index(i, offsetBy: 2)
                    continue
                }
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                fields.append(current); current = ""
            } else {
                current.append(ch)
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }

    private static func parseBool(_ s: String?) -> Bool? {
        guard let s = s?.lowercased() else { return nil }
        if ["true", "yes", "y", "1"].contains(s) { return true }
        if ["false", "no", "n", "0"].contains(s) { return false }
        return nil
    }
}
