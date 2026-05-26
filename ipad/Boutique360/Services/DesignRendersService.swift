import Foundation
import Supabase

enum DesignRendersService {
    static func listForDesign(_ designId: UUID) async throws -> [DesignRender] {
        try await SupabaseService.client.from("design_renders")
            .select()
            .eq("design_id", value: designId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func record(_ input: NewDesignRender) async throws -> DesignRender {
        try await SupabaseService.client.from("design_renders")
            .insert(input)
            .select()
            .single()
            .execute()
            .value
    }

    static func markFavorite(_ id: UUID, favorite: Bool) async throws {
        _ = try await SupabaseService.client.from("design_renders")
            .update(["is_favorite": favorite])
            .eq("id", value: id)
            .execute()
    }
}

enum DesignTryOnsService {
    static func listForRender(_ renderId: UUID) async throws -> [DesignTryOn] {
        try await SupabaseService.client.from("design_tryons")
            .select()
            .eq("design_render_id", value: renderId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func record(_ input: NewDesignTryOn) async throws -> DesignTryOn {
        try await SupabaseService.client.from("design_tryons")
            .insert(input)
            .select()
            .single()
            .execute()
            .value
    }
}
