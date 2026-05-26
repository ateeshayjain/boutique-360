import Foundation
import Supabase

/// Single entry point for uploading + fetching images across all Storage buckets.
///
/// Critical design rule (post-audit):
///   - **Persist (bucket, path)** in DB, never the signed URL.
///   - **Generate signed URL on read** at view time (signed URLs expire after 1 hour).
///   - Public buckets return long-lived URLs that ARE safe to persist.
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

    /// Result of an upload — caller persists `path` (and optionally `signedURL` for immediate use).
    /// For private buckets, the signed URL is short-lived; refresh via `signedURL(bucket:path:)` before use.
    struct UploadResult {
        let bucket: Bucket
        let path: String
        let immediateURL: String   // public URL OR fresh signed URL (1hr)
    }

    /// Upload data to a bucket.
    /// **Caller must persist (bucket, path), NOT immediateURL.**
    @discardableResult
    static func upload(_ data: Data, to bucket: Bucket, path: String, contentType: String) async throws -> UploadResult {
        _ = try await SupabaseService.client.storage
            .from(bucket.rawValue)
            .upload(path: path, file: data, options: .init(contentType: contentType, upsert: true))

        let url: String
        if bucket.isPublic {
            url = try SupabaseService.client.storage.from(bucket.rawValue).getPublicURL(path: path).absoluteString
        } else {
            url = try await SupabaseService.client.storage
                .from(bucket.rawValue)
                .createSignedURL(path: path, expiresIn: 3600)
                .absoluteString
        }
        return UploadResult(bucket: bucket, path: path, immediateURL: url)
    }

    /// Generate a fresh signed URL for a previously-uploaded private asset.
    /// **Use this every time you display a private image** — never store the result.
    static func signedURL(bucket: Bucket, path: String, expiresIn seconds: Int = 3600) async throws -> URL {
        try await SupabaseService.client.storage
            .from(bucket.rawValue)
            .createSignedURL(path: path, expiresIn: seconds)
    }

    /// For public buckets, the URL is stable — safe to persist or fetch directly.
    static func publicURL(bucket: Bucket, path: String) throws -> URL {
        try SupabaseService.client.storage.from(bucket.rawValue).getPublicURL(path: path)
    }

    // MARK: - Deterministic paths

    static func sketchPath(designId: UUID) -> String { "designs/\(designId.uuidString)/sketch.png" }
    static func renderPath(renderId: UUID) -> String { "renders/\(renderId.uuidString).png" }
    static func tryonPath(tryonId: UUID, kind: String) -> String { "tryons/\(tryonId.uuidString)/\(kind).png" }
}
