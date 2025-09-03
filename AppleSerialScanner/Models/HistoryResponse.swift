import Foundation

struct HistoryResponse: Codable {
    let totalScans: Int
    let filteredScans: Int
    let pagination: Pagination
    let filters: Filters
    let sorting: Sorting
    let recentScans: [ScanHistory]
    let statistics: SystemStats
    let exportUrl: String

    enum CodingKeys: String, CodingKey {
        case totalScans = "total_scans"
        case filteredScans = "filtered_scans"
        case pagination
        case filters
        case sorting
        case recentScans = "recent_scans"
        case statistics
        case exportUrl = "export_url"
    }
}
