import Foundation

struct ScanHistory: Codable {
    let id: Int
    let timestamp: Date
    let serial: String
    let device_type: String
    let confidence: Double
    let source: String
    let notes: String?
    let validation_passed: Bool
    let confidence_acceptable: Bool
    let status: String

    // Computed properties for UI
    var confidencePercentage: String {
        "\(Int(confidence * 100))%"
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    var statusColor: String {
        if validation_passed && confidence_acceptable {
            return "green"
        } else if validation_passed {
            return "orange"
        } else {
            return "red"
        }
    }
}