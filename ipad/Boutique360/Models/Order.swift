import Foundation

/// H9 fix: typed enum replaces stringly-typed `fulfillment_method`.
/// Forward-compat decoder falls back to .pickup if the DB returns an unknown
/// value (e.g. a future "courier" option) — keeps existing reads working.
enum FulfillmentMethod: String, Codable, CaseIterable, Identifiable, Hashable, DecodableWithFallback {
    case pickup, ship
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .pickup: "bag.fill"
        case .ship:   "shippingbox"
        }
    }
    /// Upgrade-path fallback: matches the DB column default. This enum had a
    /// hand-rolled version of this decoder before the protocol existed — the
    /// idea was right, it just wasn't applied to the other fifteen enums, and
    /// it fell back silently.
    static let decodingFallback: FulfillmentMethod = .pickup
}

enum OrderStatus: String, Codable, CaseIterable, Identifiable, DecodableWithFallback {
    case pending, confirmed, packed, shipped, delivered, cancelled, returned
    /// A status written by a NEWER app version that this build doesn't know.
    /// Deliberately a real case rather than a fallback to `.pending`: every
    /// other status is a claim about a customer's money and garment, and
    /// `.unknown` offers no transitions so nobody can act on a state they
    /// cannot see. See `DecodableWithFallback`.
    case unknown

    static let decodingFallback: OrderStatus = .unknown

    /// Excluded from `allCases` consumers that build pickers — you can never
    /// deliberately *set* an order to unknown.
    static var selectableCases: [OrderStatus] { allCases.filter { $0 != .unknown } }

    /// Counts toward "work in progress" aggregations. Unknown does not: we
    /// can't claim it's active any more than we can claim it's finished.
    var isActive: Bool {
        switch self {
        case .pending, .confirmed, .packed, .shipped: true
        case .delivered, .cancelled, .returned, .unknown: false
        }
    }

    var id: String { rawValue }

    var label: String {
        self == .unknown ? "Unknown status" : rawValue.capitalized
    }
    var systemImage: String {
        switch self {
        case .pending:   "hourglass"
        case .confirmed: "checkmark.seal"
        case .packed:    "shippingbox"
        case .shipped:   "truck.box"
        case .delivered: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        case .returned:  "arrow.uturn.left.circle"
        case .unknown:   "questionmark.circle"
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
        // No transitions from a state this build doesn't understand.
        case .cancelled, .returned, .unknown: []
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
    var fulfillmentMethod: FulfillmentMethod?    // H9 fix: typed enum, was String?
    var designId: UUID?               // R3 — the Look thread link; patched by lock_order RPC
    var eventDate: String?            // YYYY-MM-DD — customer's occasion (R1 slack anchor)
    var alterationBufferDays: Int     // R1 — absent-key tolerant, defaults 7
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
        case designId = "design_id"
        case eventDate = "event_date"
        case alterationBufferDays = "alteration_buffer_days"
        case placedAt = "placed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Custom decode solely so alteration_buffer_days tolerates absence
    // (pre-0028 cached payloads) — synthesized decoding would throw.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        boutiqueId = try c.decode(UUID.self, forKey: .boutiqueId)
        orderNumber = try c.decode(String.self, forKey: .orderNumber)
        customerId = try c.decode(UUID.self, forKey: .customerId)
        status = try c.decode(OrderStatus.self, forKey: .status)
        subtotal = try c.decode(Double.self, forKey: .subtotal)
        gstAmount = try c.decode(Double.self, forKey: .gstAmount)
        shipping = try c.decodeIfPresent(Double.self, forKey: .shipping)
        total = try c.decode(Double.self, forKey: .total)
        currency = try c.decode(String.self, forKey: .currency)
        shippingAddressJson = try c.decodeIfPresent(AnyCodable.self, forKey: .shippingAddressJson)
        trackingUrl = try c.decodeIfPresent(String.self, forKey: .trackingUrl)
        trackingCourier = try c.decodeIfPresent(String.self, forKey: .trackingCourier)
        magicLinkToken = try c.decodeIfPresent(String.self, forKey: .magicLinkToken)
        fulfillmentMethod = try c.decodeIfPresent(FulfillmentMethod.self, forKey: .fulfillmentMethod)
        designId = try c.decodeIfPresent(UUID.self, forKey: .designId)
        eventDate = try c.decodeIfPresent(String.self, forKey: .eventDate)
        alterationBufferDays = try c.decodeIfPresent(Int.self, forKey: .alterationBufferDays) ?? 7
        placedAt = try c.decodeIfPresent(Date.self, forKey: .placedAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
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
    /// H13 fix: explicit per-line GST rate. Source of truth — gstAmount can be
    /// re-derived as `qty * unitPrice * gstRate / 100`. Backfilled by migration 0026.
    var gstRate: Double?
    var gstAmount: Double
    var lineDescription: String?

    enum CodingKeys: String, CodingKey {
        case id, qty
        case orderId = "order_id"
        case boutiqueId = "boutique_id"
        case productId = "product_id"
        case variantId = "variant_id"
        case unitPrice = "unit_price"
        case gstRate = "gst_rate"
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
    let event_date: String?            // R1 — YYYY-MM-DD or nil
    let alteration_buffer_days: Int    // R1 — RPC coalesces if a stale build omits it
}

struct NewOrderItem: Encodable {
    let order_id: UUID
    let boutique_id: UUID
    let product_id: UUID?
    let variant_id: UUID?
    let qty: Int
    let unit_price: Double
    /// H13 fix: explicit GST rate per line (source of truth).
    let gst_rate: Double?
    let gst_amount: Double
    let line_description: String?
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
