import Foundation

/// Filtering options for analytics data
struct AnalyticsFilters: Codable {
    var dateRange: DateRange?
    var deviceTypes: [String]?
    var surfaceTypes: [String]?
    var minConfidence: Float?
    var successOnly: Bool?
    var source: String?
    
    struct DateRange: Codable {
        let start: Date
        let end: Date
    }
    
    static let empty = AnalyticsFilters()
}
