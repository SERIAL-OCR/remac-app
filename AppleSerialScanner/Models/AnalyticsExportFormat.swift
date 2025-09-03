import Foundation

/// Format options for analytics data export
enum AnalyticsExportFormat: String, Codable {
    case csv = "CSV"
    case json = "JSON"
    case excel = "Excel"
    case pdf = "PDF"
    
    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        case .excel: return "xlsx"
        case .pdf: return "pdf"
        }
    }
    
    var mimeType: String {
        switch self {
        case .csv: return "text/csv"
        case .json: return "application/json"
        case .excel: return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case .pdf: return "application/pdf"
        }
    }
}
