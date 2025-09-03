import Foundation

struct PerformanceInsight: Identifiable, Codable {
    let id = UUID()
    let type: InsightType
    let title: String
    let description: String
    let impact: InsightImpact
    let recommendation: String
    let confidence: Double
}

enum InsightType: String, Codable {
    case accuracy
    case performance
    case usability
    case reliability
}

enum InsightImpact: String, Codable {
    case low
    case medium
    case high
    case critical
}
