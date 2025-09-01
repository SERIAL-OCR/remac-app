import Foundation

struct HistoryResponse: Codable {
    let totalScans: Int
    let filteredScans: Int
    let pagination: Pagination
    let filters: Filters
    let sorting: Sorting
    let recentScans: [ScanHistory]
    let statistics: Statistics
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

struct Pagination: Codable {
    let limit: Int
    let offset: Int
    let hasMore: Bool
    let totalPages: Int
    let currentPage: Int

    enum CodingKeys: String, CodingKey {
        case limit
        case offset
        case hasMore = "has_more"
        case totalPages = "total_pages"
        case currentPage = "current_page"
    }
}

struct Filters: Codable {
    let source: String?
    let deviceType: String?
    let validationStatus: String?
    let search: String?

    enum CodingKeys: String, CodingKey {
        case source
        case deviceType = "device_type"
        case validationStatus = "validation_status"
        case search
    }
}

struct Sorting: Codable {
    let sortBy: String
    let sortOrder: String

    enum CodingKeys: String, CodingKey {
        case sortBy = "sort_by"
        case sortOrder = "sort_order"
    }
}
