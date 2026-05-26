import Foundation

enum OrderStatus: String, Codable, CaseIterable, Identifiable {
    case pending, confirmed, packed, shipped, delivered, cancelled, returned
    var id: String { rawValue }

    var label: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .pending:   "hourglass"
        case .confirmed: "checkmark.seal"
        case .packed:    "shippingbox"
        case .shipped:   "truck.box"
        case .delivered: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        case .returned:  "arrow.uturn.left.circle"
        }
    }
    var tint: String {
        switch self {
        case .pending:   "orange"
        case .confirmed: "blue"
        case .packed:    "indigo"
        case .shipped:   "purple"
        case .delivered: "green"
        case .cancelled: "gray"
        case .returned:  "red"
        }
    }
    /// Allowed forward transitions (HIG: prevent invalid status menu items being shown enabled).
    var nextOptions: [OrderStatus] {
        switch self {
        case .pending:        [.confirmed, .cancelled]
        case .confirmed:      [.packed, .cancelled]
        case .packed:         [.shipped, .cancelled]
        case .shipped:        [.delivered]
        case .delivered:      [.returned]
        case .cancelled, .returned: []
        }
    }
}

struct Order: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var orderNumber: String
    var customerId: UUID
    var status: OrderStatus
    var subtotal: Double
    var gstAmount: Double
    var shipping: Double?
    var total: Double
    var currency: String
    var shippingAddressJson: AnyCodable?
    var trackingUrl: String?
    var trackingCourier: String?
    var magicLinkToken: String?
    var fulfillmentMethod: String?     // 'pickup' | 'ship'
    var placedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, subtotal, shipping, total, currency
        case boutiqueId = "boutique_id"
        case orderNumber = "order_number"
        case customerId = "customer_id"
        case gstAmount = "gst_amount"
        case shippingAddressJson = "shipping_address_json"
        case trackingUrl = "tracking_url"
        case trackingCourier = "tracking_courier"
        case magicLinkToken = "magic_link_token"
        case fulfillmentMethod = "fulfillment_method"
        case placedAt = "placed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct OrderItem: Identifiable, Codable, Hashable {
    let id: UUID
    var orderId: UUID
    var boutiqueId: UUID
    var productId: UUID?
    var variantId: UUID?
    var qty: Int
    var unitPrice: Double
    var gstAmount: Double
    var lineDescription: String?     // free-text fallback when no product is linked (custom design line)

    enum CodingKeys: String, CodingKey {
        case id, qty
        case orderId = "order_id"
        case boutiqueId = "boutique_id"
        case productId = "product_id"
        case variantId = "variant_id"
        case unitPrice = "unit_price"
        case gstAmount = "gst_amount"
        case lineDescription = "line_description"
    }
}

struct NewOrder: Encodable {
    let boutique_id: UUID
    let order_number: String
    let customer_id: UUID
    let status: String
    let subtotal: Double
    let gst_amount: Double
    let shipping: Double?
    let total: Double
    let currency: String
    let magic_link_token: String?
    let fulfillment_method: String     // 'pickup' | 'ship'
    let placed_at: String?
}

struct NewOrderItem: Encodable {
    let order_id: UUID
    let boutique_id: UUID
    let product_id: UUID?
    let variant_id: UUID?
    let qty: Int
    let unit_price: Double
    let gst_amount: Double
}

/// Minimal AnyCodable for shipping_address_json without pulling in a dep.
struct AnyCodable: Codable, Hashable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { value = v }
        else if let v = try? c.decode(Double.self) { value = v }
        else if let v = try? c.decode(Bool.self) { value = v }
        else if let v = try? c.decode([String: AnyCodable].self) { value = v }
        else if let v = try? c.decode([AnyCodable].self) { value = v }
        else if c.decodeNil() { value = NSNull() }
        else { value = NSNull() }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as String: try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as Bool: try c.encode(v)
        case let v as [String: AnyCodable]: try c.encode(v)
        case let v as [AnyCodable]: try c.encode(v)
        default: try c.encodeNil()
        }
    }
    static func == (l: AnyCodable, r: AnyCodable) -> Bool { String(describing: l.value) == String(describing: r.value) }
    func hash(into hasher: inout Hasher) { hasher.combine(String(describing: value)) }
}
