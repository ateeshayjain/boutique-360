import Foundation
import UIKit

/// Wrapper around the Gemini REST API for sketch→garment render and customer VTO.
/// Uses `gemini-2.5-flash-image` model which accepts multi-modal text+image
/// input and returns generated images as base64 PNG.
///
/// API docs: https://ai.google.dev/gemini-api/docs/image-generation
enum GeminiService {
    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    private static let model = "gemini-2.5-flash-image"

    enum GeminiError: LocalizedError {
        case notConfigured
        case badResponse(String)
        case decodeFailed
        case noImageReturned
        var errorDescription: String? {
            switch self {
            case .notConfigured: "Gemini API key not set. Add it to Env.xcconfig and rebuild."
            case .badResponse(let s): "Gemini error: \(s)"
            case .decodeFailed: "Could not decode Gemini response"
            case .noImageReturned: "Gemini returned no image (check prompt + try again)"
            }
        }
    }

    // MARK: - Public API

    /// Renders a designer's sketch into a photorealistic garment image.
    /// Combines: the sketch drawing, optional fabric reference photos, structured
    /// metadata (garment type, occasion, fabric names, color palette).
    static func renderGarmentFromSketch(
        sketch: UIImage,
        fabricReferences: [UIImage] = [],
        garmentType: String?,
        occasion: String?,
        fabricNames: [String] = [],
        colorPalette: [String] = [],
        styleNotes: String? = nil
    ) async throws -> UIImage {
        guard !Config.geminiApiKey.isEmpty else { throw GeminiError.notConfigured }

        let prompt = PromptTemplates.renderGarment(
            garmentType: garmentType, occasion: occasion,
            fabricNames: fabricNames, colorPalette: colorPalette, styleNotes: styleNotes
        )
        let images = [sketch] + fabricReferences
        return try await generateImage(prompt: prompt, inputImages: images)
    }

    /// Renders a garment from a customer-supplied reference photo (e.g. a dress
    /// from Pinterest/Instagram/camera roll), re-imagined in the chosen fabric.
    /// The reference image is the FIRST input; optional fabric swatches follow.
    /// `generateImage` enforces the per-boutique AICostMeter ceiling internally.
    static func renderGarmentFromReference(
        reference: UIImage,
        fabricImages: [UIImage] = [],
        fabricDescription: String? = nil,
        garmentType: String?,
        occasion: String?,
        styleNotes: String? = nil
    ) async throws -> UIImage {
        guard !Config.geminiApiKey.isEmpty else { throw GeminiError.notConfigured }

        let prompt = PromptTemplates.renderGarmentFromReference(
            garmentType: garmentType,
            occasion: occasion,
            fabricDescription: fabricDescription,
            fabricImageCount: fabricImages.count,
            styleNotes: styleNotes
        )
        let images = [reference] + fabricImages
        return try await generateImage(prompt: prompt, inputImages: images)
    }

    /// Generates a Romanized-Hindi tailor brief from structured design data.
    /// Output is plain text suitable for the bottom of the Job Card PDF or
    /// pasting into a WhatsApp message to the karigar.
    static func generateTailorBrief(
        garmentType: String?,
        occasion: String?,
        customerNotes: String?,
        fabricList: [FabricLine],
        measurements: [String: Double]?,
        embellishments: String?,
        dueDate: String?,
        karigarName: String?
    ) async throws -> String {
        guard !Config.geminiApiKey.isEmpty else { throw GeminiError.notConfigured }

        let prompt = PromptTemplates.tailorBrief(
            garmentType: garmentType, occasion: occasion, customerNotes: customerNotes,
            fabricList: fabricList, measurements: measurements,
            embellishments: embellishments, dueDate: dueDate, karigarName: karigarName
        )
        return try await generateText(prompt: prompt)
    }

    // MARK: - Wave 6: AI style suggestions
    /// Returns 3 next-look suggestions for a customer based on their order
    /// history + style notes. Plain-text output (one suggestion per line,
    /// `1. ... 2. ... 3. ...`) so the caller can split + render as cards
    /// without parsing JSON. JSON would be more robust but adds a retry
    /// loop for the times Gemini wraps the JSON in markdown fences.
    static func suggestStyles(
        customerName: String,
        recentOccasions: [String],
        recentGarmentTypes: [String],
        styleNotes: String?,
        upcomingOccasion: String?
    ) async throws -> [String] {
        guard !Config.geminiApiKey.isEmpty else { throw GeminiError.notConfigured }
        let prompt = PromptTemplates.styleSuggestions(
            customerName: customerName,
            recentOccasions: recentOccasions,
            recentGarmentTypes: recentGarmentTypes,
            styleNotes: styleNotes,
            upcomingOccasion: upcomingOccasion
        )
        let raw = try await generateText(prompt: prompt)
        return parseSuggestionLines(raw)
    }

    /// Pull the 3 numbered lines out of the model's reply. Tolerant to
    /// markdown bullets, blank lines, and "1)" vs "1." numbering.
    private static func parseSuggestionLines(_ raw: String) -> [String] {
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // Match lines starting with "1.", "1)", "- ", "•", or "*"
        let pattern = #"^\s*(?:\d+[.)]|[-•*])\s+"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let stripped = lines.compactMap { line -> String? in
            guard let r = regex else { return line }
            let range = NSRange(line.startIndex..., in: line)
            let cleaned = r.stringByReplacingMatches(in: line, range: range, withTemplate: "")
            return cleaned.isEmpty ? nil : cleaned
        }
        // Return the first 3 substantive lines (defensive cap — model
        // sometimes adds a "hope this helps!" trailer we ignore).
        return Array(stripped.prefix(3))
    }

    /// Dresses a customer photo in the garment shown in `garmentImage`.
    /// The result preserves the customer's face/body while applying the garment realistically.
    static func virtualTryOn(
        customerPhoto: UIImage,
        garmentImage: UIImage,
        garmentType: String?
    ) async throws -> UIImage {
        guard !Config.geminiApiKey.isEmpty else { throw GeminiError.notConfigured }
        let prompt = PromptTemplates.virtualTryOn(garmentType: garmentType)
        return try await generateImage(prompt: prompt, inputImages: [customerPhoto, garmentImage])
    }

    // MARK: - Core calls

    private static func generateText(prompt: String) async throws -> String {
        // For text-only generation we use gemini-2.5-flash (cheaper, faster).
        let textModel = "gemini-2.5-flash"
        // Audit fix: API key in `x-goog-api-key` header, not URL query — URLs
        // get logged in proxies/error reports/network traces; the header
        // doesn't. Cost-ceiling check via Supabase RPC before the call.
        try await AICostMeter.checkCeiling(costEstimate: 0.001)   // gemini-2.5-flash text is ~$0.001 per call
        guard let url = URL(string: "\(baseURL)/models/\(textModel):generateContent") else {
            throw GeminiError.badResponse("Couldn't build Gemini URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.geminiApiKey, forHTTPHeaderField: "x-goog-api-key")
        req.timeoutInterval = 30

        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw GeminiError.badResponse("Brief gen failed: \(body.prefix(500))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String
        else { throw GeminiError.decodeFailed }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func generateImage(prompt: String, inputImages: [UIImage]) async throws -> UIImage {
        // Image gen is ~40x more expensive than text — ~$0.04 per call.
        try await AICostMeter.checkCeiling(costEstimate: 0.04)
        guard let url = URL(string: "\(baseURL)/models/\(model):generateContent") else {
            throw GeminiError.badResponse("Couldn't build Gemini URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.geminiApiKey, forHTTPHeaderField: "x-goog-api-key")
        req.timeoutInterval = 120

        var parts: [[String: Any]] = [["text": prompt]]
        for img in inputImages {
            guard let data = img.jpegData(compressionQuality: 0.85) else { continue }
            parts.append([
                "inlineData": [
                    "mimeType": "image/jpeg",
                    "data": data.base64EncodedString(),
                ]
            ])
        }
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": ["responseModalities": ["IMAGE", "TEXT"]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw GeminiError.decodeFailed }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw GeminiError.badResponse("HTTP \(http.statusCode): \(body.prefix(500))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let respParts = content["parts"] as? [[String: Any]]
        else { throw GeminiError.decodeFailed }

        for part in respParts {
            if let inline = part["inlineData"] as? [String: Any],
               let base64 = inline["data"] as? String,
               let data = Data(base64Encoded: base64),
               let img = UIImage(data: data) {
                return img
            }
        }
        throw GeminiError.noImageReturned
    }
}

// MARK: - Prompt templates
// ┌─────────────────────────────────────────────────────────────────────────────┐
// │  USER CONTRIBUTION OPPORTUNITY                                              │
// │                                                                             │
// │  These prompt templates SHAPE what comes back from Gemini. Smart defaults   │
// │  below — but a boutique designer's eye for what "a good lehenga render"     │
// │  looks like will iterate them better than I can guess.                      │
// │                                                                             │
// │  After your first render: review the result, identify what's off (too      │
// │  cartoony? wrong drape? wrong embroidery density? Western styling?), and   │
// │  refine the strings in `PromptTemplates` below. Re-run for instant test.   │
// └─────────────────────────────────────────────────────────────────────────────┘
enum PromptTemplates {
    static func renderGarment(
        garmentType: String?,
        occasion: String?,
        fabricNames: [String],
        colorPalette: [String],
        styleNotes: String?
    ) -> String {
        let garment = garmentType ?? "outfit"
        let occasionStr = occasion.map { " for \($0)" } ?? ""
        let fabricStr = fabricNames.isEmpty ? "" : " Use these fabrics: \(fabricNames.joined(separator: ", "))."
        let colorStr = colorPalette.isEmpty ? "" : " Color palette: \(colorPalette.joined(separator: ", "))."
        let notesStr = styleNotes.map { " Designer notes: \($0)" } ?? ""

        return """
        You are an expert Indian fashion designer rendering a sketch into a photorealistic garment.

        Convert the input sketch into a high-quality, photorealistic image of a finished \(garment)\(occasionStr).\(fabricStr)\(colorStr)\(notesStr)

        Requirements:
        - Indian aesthetic — traditional craftsmanship (zari, gota, mirror work, embroidery as appropriate)
        - Garment displayed on a neutral mannequin or flat-lay against soft studio lighting
        - Authentic fabric drape and texture; visible weave and stitching detail
        - Preserve the silhouette, neckline, and design elements from the sketch
        - Studio photography quality — sharp focus, true colors, no cartoon/illustration look
        - Square 1:1 aspect ratio
        - No text overlays, no watermarks
        """
    }

    /// ┌─────────────────────────────────────────────────────────────────────────┐
    /// │  USER CONTRIBUTION OPPORTUNITY (tailor brief)                          │
    /// │                                                                         │
    /// │  This Romanized-Hindi prompt produces the friendly brief at the bottom │
    /// │  of every Job Card PDF. Older karigars often read this faster than the │
    /// │  structured top half. After your first real Job Card, look at the AI's │
    /// │  output and refine: tone, vocabulary, common tailor phrases you'd      │
    /// │  actually use, regional preferences (Delhi vs Surat vs Banaras).       │
    /// └─────────────────────────────────────────────────────────────────────────┘
    static func tailorBrief(
        garmentType: String?, occasion: String?, customerNotes: String?,
        fabricList: [FabricLine], measurements: [String: Double]?,
        embellishments: String?, dueDate: String?, karigarName: String?
    ) -> String {
        let greeting = karigarName.map { "\($0) bhai," } ?? "Bhai,"
        let garment = garmentType ?? "dress"
        let occasionStr = occasion.map { " ye \($0) ke liye hai." } ?? ""
        let dueStr = dueDate.map { " Due date \($0) hai, time pe ready hona chahiye." } ?? ""
        let measureStr: String = {
            guard let m = measurements, !m.isEmpty else { return "" }
            let pairs = m.sorted { $0.key < $1.key }
                .map { "\($0.key.replacingOccurrences(of: "_", with: " ")): \(String(format: "%.1f", $0.value))" }
                .joined(separator: ", ")
            return "\n\nMeasurements: \(pairs) (sab inches mein hain)"
        }()
        let fabricStr: String = {
            guard !fabricList.isEmpty else { return "" }
            let lines = fabricList.map { f -> String in
                var s = "- \(f.name)"
                if let c = f.color { s += " (\(c))" }
                s += " — \(String(format: "%.1f", f.quantityMeters)) meter"
                if let r = f.role { s += " (\(r))" }
                return s
            }.joined(separator: "\n")
            return "\n\nFabric:\n\(lines)"
        }()
        let embStr = embellishments.map { "\n\nEmbroidery / work: \($0)" } ?? ""
        let notesStr = customerNotes.map { "\n\nCustomer note: \($0)" } ?? ""

        return """
        You are writing a brief for a master tailor (karigar) in India. Karigars read Romanized Hindi (Hindi words in English script) faster than Devanagari on phone screens.

        Take the structured design info below and write a short, friendly, practical brief in Romanized Hindi (Hinglish). Use simple tailor vocabulary like 'chati' (chest), 'kamar' (waist), 'lambai' (length), 'astar' (lining), 'lace', 'border'. Keep numbers in digits. Mention due date clearly. End with "Doubt ho to call kar lena."

        Style:
        - 5 to 8 short sentences
        - No formal English greetings — start with "\(greeting)"
        - Don't repeat measurements unless calling out a critical one
        - Use natural tailor language, not translated English

        ----- DESIGN DATA -----
        Garment: \(garment)\(occasionStr)\(dueStr)\(measureStr)\(fabricStr)\(embStr)\(notesStr)
        ----- END DATA -----

        Output ONLY the Hindi brief text. No explanations, no English headers, no markdown.
        """
    }

    static func renderGarmentFromReference(
        garmentType: String?,
        occasion: String?,
        fabricDescription: String?,
        fabricImageCount: Int,
        styleNotes: String?
    ) -> String {
        var p = """
        You are a fashion illustrator. The FIRST image is a reference photo of a \
        garment the customer likes. Recreate that garment as a single photorealistic \
        finished piece, preserving its silhouette, neckline, and overall design.
        """
        if fabricImageCount > 0 {
            p += "\n\nThe next \(fabricImageCount) image(s) are fabric swatches — render the garment in this fabric."
        }
        if let d = fabricDescription, !d.isEmpty { p += "\nFabric: \(d)" }
        if let g = garmentType { p += "\nGarment type: \(g)" }
        if let o = occasion { p += "\nOccasion: \(o)" }
        if let s = styleNotes, !s.isEmpty { p += "\nStyle notes: \(s)" }
        p += "\n\nReturn a single image on a clean white studio background. Do not include the original reference photo's background or any person."
        return p
    }

    static func virtualTryOn(garmentType: String?) -> String {
        let garment = garmentType ?? "garment"
        return """
        Create a photorealistic virtual try-on image.

        Take the person from the first photo and dress them in the \(garment) shown in the second photo.

        Requirements:
        - Preserve the person's face, hairstyle, skin tone, and body proportions EXACTLY
        - Apply the garment naturally with realistic drape, fit, and folds for the person's body
        - Maintain the garment's original colors, patterns, embroidery, and embellishments
        - Indian aesthetic — appropriate jewellery and styling cues only if minimal and tasteful
        - Studio-quality fashion photography lighting
        - Neutral or softly-blurred background
        - No text overlays. Output a subtle 'Boutique 360 — preview' watermark at the bottom-right corner
        """
    }

    // MARK: - Wave 6: Style suggestions

    /// Builds the "what should this customer wear next" prompt. We give
    /// the model the customer's recent history + the upcoming occasion
    /// and ask for 3 concrete looks. Short, actionable language — the
    /// designer should be able to walk into the next consultation
    /// already knowing what to pull from the rack.
    static func styleSuggestions(
        customerName: String,
        recentOccasions: [String],
        recentGarmentTypes: [String],
        styleNotes: String?,
        upcomingOccasion: String?
    ) -> String {
        let firstName = customerName.split(separator: " ").first.map(String.init) ?? customerName
        let occasionsStr = recentOccasions.isEmpty
            ? "no specific occasions logged yet"
            : recentOccasions.joined(separator: ", ")
        let garmentsStr = recentGarmentTypes.isEmpty
            ? "no specific garments logged yet"
            : recentGarmentTypes.joined(separator: ", ")
        let notesStr = styleNotes.map { "Style notes from the designer: \($0)" } ?? "No style notes yet."
        let nextStr = upcomingOccasion.map { "Upcoming occasion: \($0)." } ?? "No specific upcoming occasion."

        return """
        You are a senior Indian boutique designer suggesting next looks for an existing customer.

        Customer: \(firstName)
        Recent occasions: \(occasionsStr)
        Recent garment types: \(garmentsStr)
        \(notesStr)
        \(nextStr)

        Output EXACTLY 3 concrete style suggestions, each on its own line, numbered 1–3.
        Each suggestion must include:
        - silhouette (e.g. anarkali, saree, sharara, lehenga, kurta set, fusion gown)
        - one fabric (e.g. emerald Banarasi silk, ivory chanderi, kanjivaram brocade)
        - one occasion this suits (haldi, sangeet, reception, festive, daywear)
        - one signature detail (e.g. gota patti border, mirror work yoke, zardozi blouse)

        Format: "1. <silhouette> in <fabric> — perfect for <occasion>, finished with <detail>."

        Keep it tight (one sentence per number). Do NOT add headers, intros, or sign-offs. Do NOT use markdown bold/italic. Just the 3 numbered lines.
        """
    }
}
