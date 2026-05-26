import Foundation
import Supabase

enum DesignsService {
    static func list(status: DesignStatus? = nil, customerId: UUID? = nil) async throws -> [Design] {
        var query = SupabaseService.client.from("designs").select()
        if let s = status { query = query.eq("status", value: s.rawValue) }
        if let cid = customerId { query = query.eq("customer_id", value: cid) }
        return try await query
            .order("updated_at", ascending: false)
            .limit(200)
            .execute()
            .value
    }

    static func get(id: UUID) async throws -> Design {
        try await SupabaseService.client.from("designs")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    static func create(_ input: NewDesign) async throws -> Design {
        try await SupabaseService.client.from("designs")
            .insert(input)
            .select()
            .single()
            .execute()
            .value
    }

    struct DesignPatch: Encodable {
        var name: String?
        var status: String?
        var garment_type: String?
        var occasion: String?
        var notes_md: String?
        var customer_id: UUID?
    }

    static func update(_ id: UUID, patch: DesignPatch) async throws -> Design {
        try await SupabaseService.client.from("designs")
            .update(patch)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value
    }

    /// Persists the sketch's canonical Storage path (not the expiring signed URL).
    /// `cachedURL` is included as a write-through cache for immediate display only.
    struct SketchPatch: Encodable {
        let sketch_image_path: String
        let sketch_image_url: String
        let sketch_strokes_json: SketchStrokesJSON
        let status: String
    }
    struct SketchStrokesJSON: Encodable {
        let data: String
    }
    static func saveSketchPath(designId: UUID, path: String, cachedURL: String, strokes: Data) async throws {
        let patch = SketchPatch(
            sketch_image_path: path,
            sketch_image_url: cachedURL,
            sketch_strokes_json: .init(data: strokes.base64EncodedString()),
            status: DesignStatus.draft.rawValue
        )
        _ = try await SupabaseService.client.from("designs")
            .update(patch)
            .eq("id", value: designId)
            .execute()
    }
}

enum LookbooksService {
    static func list() async throws -> [DesignLookbook] {
        try await SupabaseService.client.from("design_lookbook")
            .select()
            .order("name", ascending: true)
            .execute()
            .value
    }

    static func create(_ input: NewLookbook) async throws -> DesignLookbook {
        try await SupabaseService.client.from("design_lookbook")
            .insert(input)
            .select()
            .single()
            .execute()
            .value
    }
}
