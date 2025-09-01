import Foundation

struct SystemStats: Codable {
    let database: DatabaseStats
    let system: SystemHealth

    var totalScans: Int {
        return database.totalSerials
    }

    var successfulScans: Int {
        return database.validationStats.valid
    }

    var failedScans: Int {
        return database.totalSerials - database.validationStats.valid
    }

    var averageConfidence: Double {
        return database.avgConfidence
    }

    var iosScans: Int {
        return database.bySource.ios
    }

    var macScans: Int {
        return database.bySource.mac
    }

    var successRate: Double {
        guard totalScans > 0 else { return 0.0 }
        return Double(successfulScans) / Double(totalScans)
    }

    var lastScanTime: Date? {
        // TODO: Parse from system.lastActivity if available
        return nil
    }
}

struct DatabaseStats: Codable {
    let totalSerials: Int
    let bySource: SourceStats
    let validationStats: ValidationStats
    let avgConfidence: Double

    enum CodingKeys: String, CodingKey {
        case totalSerials = "total_serials"
        case bySource = "by_source"
        case validationStats = "validation_stats"
        case avgConfidence = "avg_confidence"
    }
}

struct SourceStats: Codable {
    let ios: Int
    let mac: Int
    let server: Int
}

struct ValidationStats: Codable {
    let valid: Int
    let confidenceAcceptable: Int

    enum CodingKeys: String, CodingKey {
        case valid
        case confidenceAcceptable = "confidence_acceptable"
    }
}

struct SystemHealth: Codable {
    let uptime: String?
    let lastActivity: String?
}

