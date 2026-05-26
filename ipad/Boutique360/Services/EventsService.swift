import Foundation
import Supabase

struct AppEvent: Identifiable, Decodable, Hashable {
    let id: UUID
    let eventName: String
    let payloadJson: JSON
    let occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case eventName = "event_name"
        case payloadJson = "payload_json"
        case occurredAt = "occurred_at"
    }
}

enum EventsService {
    /// Read recent events filtered by names + optional payload JSONPath value.
    /// Used by the order timeline (filters on `payload_json ->> 'order_id'`).
    static func listForOrder(_ orderId: UUID, limit: Int = 50) async throws -> [AppEvent] {
        try await SupabaseService.client.from("events")
            .select("id,event_name,payload_json,occurred_at")
            .eq("payload_json->>order_id", value: orderId.uuidString)
            .order("occurred_at", ascending: true)
            .limit(limit)
            .execute()
            .value
    }
}

/// Tiny JSON wrapper for decoding payload_json without a full Codable model per event type.
enum JSON: Codable, Hashable {
    case string(String), int(Int), double(Double), bool(Bool), null
    case object([String: JSON]), array([JSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSON].self) { self = .object(v); return }
        if let v = try? c.decode([JSON].self) { self = .array(v); return }
        self = .null
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let v): return String(v)
        default: return nil
        }
    }
    subscript(key: String) -> JSON? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }
}
