import Foundation

struct SerialResponse: Codable {
    let success: Bool
    let serial_id: String?
    let message: String
    let validation_passed: Bool
    let confidence_acceptable: Bool
    let timestamp: Date
}

