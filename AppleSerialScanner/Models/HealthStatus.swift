import Foundation

struct HealthStatus: Codable {
    let status: String
    let phase: String?
    let timestamp: Date?
    let database: String?
    let totalSerials: Int?
    let recentActivity: RecentActivity?

    enum CodingKeys: String, CodingKey {
        case status, phase, timestamp, database
        case totalSerials = "total_serials"
        case recentActivity = "recent_activity"
    }
}

struct RecentActivity: Codable {
    let iosSubmissions: Int?
    let macSubmissions: Int?
    let serverSubmissions: Int?

    enum CodingKeys: String, CodingKey {
        case iosSubmissions = "ios_submissions"
        case macSubmissions = "mac_submissions"
        case serverSubmissions = "server_submissions"
    }
}
