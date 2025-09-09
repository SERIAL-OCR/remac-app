import Foundation

// MARK: - Batch Processing Models

struct BatchSession: Codable, Identifiable {
    let id: UUID
    let name: String
    let createdAt: Date
    var items: [BatchItem]
    var currentIndex: Int
    var status: BatchStatus
    var settings: BatchSettings
    var completedAt: Date?

    var progress: Double {
        let completedCount = items.filter { $0.status == .completed }.count
        return Double(completedCount) / Double(items.count)
    }

    var completedItems: Int {
        items.filter { $0.status == .completed }.count
    }

    var failedItems: Int {
        items.filter { $0.status == .failed }.count
    }

    var currentItem: BatchItem? {
        guard currentIndex >= 0 && currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    var isComplete: Bool {
        items.allSatisfy { $0.status == .completed || $0.status == .skipped }
    }

    mutating func moveToNextItem() {
        currentIndex += 1
        if currentIndex >= items.count {
            status = .completed
            completedAt = Date()
        }
    }

    mutating func updateItemStatus(itemId: UUID, status: BatchItemStatus, serial: String? = nil, confidence: Float? = nil, errorMessage: String? = nil) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].status = status
            items[index].serialNumber = serial
            items[index].confidence = confidence
            items[index].timestamp = Date()
            items[index].errorMessage = errorMessage
        }
    }
}

struct BatchItem: Codable, Identifiable {
    let id: UUID
    var deviceType: AccessoryType
    var status: BatchItemStatus
    var serialNumber: String?
    var confidence: Float?
    var timestamp: Date?
    var errorMessage: String?
    var retryCount: Int

    init(deviceType: AccessoryType) {
        self.id = UUID()
        self.deviceType = deviceType
        self.status = .pending
        self.retryCount = 0
    }
}

enum BatchStatus: String, Codable {
    case pending = "Pending"
    case inProgress = "In Progress"
    case paused = "Paused"
    case completed = "Completed"
    case cancelled = "Cancelled"
}

enum BatchItemStatus: String, Codable {
    case pending = "Pending"
    case processing = "Processing"
    case completed = "Completed"
    case failed = "Failed"
    case skipped = "Skipped"
}

struct BatchSettings: Codable {
    var autoAdvance: Bool = true
    var autoAdvanceDelay: TimeInterval = 2.0
    var retryFailedItems: Bool = true
    var maxRetries: Int = 3
    var saveProgress: Bool = true
    var exportOnComplete: Bool = false
    var sessionTimeout: TimeInterval = 300.0 // 5 minutes

    static let `default` = BatchSettings()
}

// MARK: - Scan Result Model
struct BatchScanResult {
    let serial: String
    let confidence: Float
    let deviceType: AccessoryType
    let timestamp: Date
    let success: Bool
    let errorMessage: String?

    static func success(serial: String, confidence: Float, deviceType: AccessoryType) -> BatchScanResult {
        BatchScanResult(
            serial: serial,
            confidence: confidence,
            deviceType: deviceType,
            timestamp: Date(),
            success: true,
            errorMessage: nil
        )
    }

    static func failure(deviceType: AccessoryType, errorMessage: String) -> BatchScanResult {
        BatchScanResult(
            serial: "",
            confidence: 0.0,
            deviceType: deviceType,
            timestamp: Date(),
            success: false,
            errorMessage: errorMessage
        )
    }
}

// MARK: - Batch Statistics
struct BatchStatistics {
    let totalItems: Int
    let completedItems: Int
    let failedItems: Int
    let skippedItems: Int
    let averageConfidence: Float
    let averageProcessingTime: TimeInterval
    let startTime: Date
    let endTime: Date?

    var completionRate: Double {
        Double(completedItems) / Double(totalItems)
    }

    var successRate: Double {
        let processedItems = completedItems + failedItems
        return processedItems > 0 ? Double(completedItems) / Double(processedItems) : 0.0
    }

    var totalDuration: TimeInterval {
        guard let endTime = endTime else { return Date().timeIntervalSince(startTime) }
        return endTime.timeIntervalSince(startTime)
    }
}

// MARK: - Persistence Extensions
extension BatchSession {
    static let storageKey = "batch_sessions"

    static func saveSessions(_ sessions: [BatchSession]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(sessions)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            AppLogger.storage.error("Error saving batch sessions: \(error.localizedDescription)")
        }
    }

    static func loadSessions() -> [BatchSession] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode([BatchSession].self, from: data)
        } catch {
            AppLogger.storage.error("Error loading batch sessions: \(error.localizedDescription)")
            return []
        }
    }

    static func saveSession(_ session: BatchSession) {
        var sessions = loadSessions()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        saveSessions(sessions)
    }

    static func deleteSession(id: UUID) {
        var sessions = loadSessions()
        sessions.removeAll { $0.id == id }
        saveSessions(sessions)
    }
}
