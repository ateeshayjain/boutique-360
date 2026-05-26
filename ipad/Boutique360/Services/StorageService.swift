import Foundation
import Supabase

/// Single entry point for uploading/fetching images across all Storage buckets.
/// Centralizes the public-vs-private decision and auto-purge contracts.
enum StorageService {
    enum Bucket: String {
        case productImages      = "product-images"          // public
        case vtoUploads         = "vto-uploads"             // private, signed
        case vtoResults         = "vto-results"             // public (watermarked)
        case designSketches     = "design-sketches"         // private (staff only)
        case designRenders      = "design-renders"          // private
        case customerPhotos     = "customer-photos"         // private, AUTO-PURGE 7 days
        case fabrics            = "fabrics"                 // private
        case invoices           = "invoices"                // private
        case measurementsPhotos = "measurements-photos"     // private

        var isPublic: Bool {
            switch self {
            case .productImages, .vtoResults: true
            default: false
            }
        }
    }

    /// Upload data; returns the URL to fetch the asset.
    /// For public buckets: returns the long-lived public URL.
    /// For private buckets: returns a short-lived signed URL (1 hour default).
    static func upload(_ data: Data, to bucket: Bucket, path: String, contentType: String) async throws -> String {
        _ = try await SupabaseService.client.storage
            .from(bucket.rawValue)
            .upload(path: path, file: data, options: .init(contentType: contentType, upsert: true))

        if bucket.isPublic {
            return try SupabaseService.client.storage.from(bucket.rawValue).getPublicURL(path: path).absoluteString
        } else {
            let signed = try await SupabaseService.client.storage
                .from(bucket.rawValue)
                .createSignedURL(path: path, expiresIn: 3600)
            return signed.absoluteString
        }
    }

    /// Get a fresh signed URL for a previously-uploaded private asset.
    static func refreshSignedURL(bucket: Bucket, path: String, expiresIn seconds: Int = 3600) async throws -> String {
        try await SupabaseService.client.storage
            .from(bucket.rawValue)
            .createSignedURL(path: path, expiresIn: seconds)
            .absoluteString
    }

    /// Convenience: deterministic path for design sketches.
    static func sketchPath(designId: UUID) -> String { "designs/\(designId.uuidString)/sketch.png" }
    static func renderPath(renderId: UUID) -> String { "renders/\(renderId.uuidString).png" }
    static func tryonPath(tryonId: UUID, kind: String) -> String { "tryons/\(tryonId.uuidString)/\(kind).png" }
}
