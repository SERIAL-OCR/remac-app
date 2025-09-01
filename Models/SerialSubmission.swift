import Foundation

struct SerialSubmission: Codable {
    let serial: String
    let confidence: Float
    let device_type: String?
    let source: String
    let ts: Date
    let notes: String?

    init(serial: String, confidence: Float, device_type: String? = nil, source: String, ts: Date? = nil, notes: String? = nil) {
        self.serial = serial
        self.confidence = confidence
        self.device_type = device_type
        self.source = source
        self.ts = ts ?? Date()
        self.notes = notes
    }
}
