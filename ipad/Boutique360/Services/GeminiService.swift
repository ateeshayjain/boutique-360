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
        let url = URL(string: "\(baseURL)/models/\(textModel):generateContent?key=\(Config.geminiApiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        let url = URL(string: "\(baseURL)/models/\(model):generateContent?key=\(Config.geminiApiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
}
