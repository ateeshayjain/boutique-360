import Foundation

enum JobCardStatus: String, Codable, CaseIterable, Identifiable {
    case draft, issued, in_progress, ready, delivered, cancelled
    var id: String { rawValue }
    var label: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

struct FabricLine: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var color: String?
    var quantityMeters: Double
    var supplier: String?
    var role: String?           // 'main' | 'lining' | 'trim' | 'embellishment'

    private enum CodingKeys: String, CodingKey {
        case id, name, color, supplier, role
        case quantityMeters = "quantity_m"
    }
}

struct StageProgress: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var stageName: String
    var completedAt: Date?
    var notes: String?

    private enum CodingKeys: String, CodingKey {
        case id, notes
        case stageName = "stage_name"
        case completedAt = "completed_at"
    }
}

struct JobCard: Identifiable, Codable, Hashable {
    let id: UUID
    var boutiqueId: UUID
    var jobNumber: String
    var designId: UUID?
    var orderId: UUID?
    var customerId: UUID?
    var garmentType: String?
    var occasion: String?
    var assignedKarigarId: UUID?
    var dueDate: String?              // YYYY-MM-DD
    var status: JobCardStatus
    var measurementsJson: [String: Double]?
    var fabricListJson: [FabricLine]
    var embellishments: String?
    var specialInstructions: String?
    var hindiBrief: String?
    var sketchImagePath: String?
    var renderImagePath: String?
    var currentStage: Int
    var stagesProgressJson: [StageProgress]
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, occasion, embellishments
        case boutiqueId = "boutique_id"
        case jobNumber = "job_number"
        case designId = "design_id"
        case orderId = "order_id"
        case customerId = "customer_id"
        case garmentType = "garment_type"
        case assignedKarigarId = "assigned_karigar_id"
        case dueDate = "due_date"
        case measurementsJson = "measurements_json"
        case fabricListJson = "fabric_list_json"
        case specialInstructions = "special_instructions"
        case hindiBrief = "hindi_brief"
        case sketchImagePath = "sketch_image_path"
        case renderImagePath = "render_image_path"
        case currentStage = "current_stage"
        case stagesProgressJson = "stages_progress_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct NewJobCard: Encodable {
    let boutique_id: UUID
    let job_number: String
    let design_id: UUID?
    let order_id: UUID?
    let customer_id: UUID?
    let garment_type: String?
    let occasion: String?
    let assigned_karigar_id: UUID?
    let due_date: String?
    let status: String
    let measurements_json: [String: Double]?
    let fabric_list_json: [FabricLine]
    let embellishments: String?
    let special_instructions: String?
    let hindi_brief: String?
    let sketch_image_path: String?
    let render_image_path: String?
}
