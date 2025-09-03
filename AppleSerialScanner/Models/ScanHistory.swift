import Foundation

struct ScanHistory: Codable, Identifiable, Hashable {
    var id: UUID
    var serialNumber: String
    var timestamp: Date
    var deviceModel: String?
    var status: String // e.g., "Valid", "Invalid", "Pending"
}
