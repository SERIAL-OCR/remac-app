import Foundation

struct AnalyticsConfiguration: Codable {
    let enableDataCollection: Bool
    let retentionPeriod: TimeInterval // in days
    let enableRemoteSync: Bool
    let anonymizeData: Bool
    let enablePerformanceTracking: Bool
    let enableErrorTracking: Bool
    
    static let `default` = AnalyticsConfiguration(
        enableDataCollection: true,
        retentionPeriod: 30,
        enableRemoteSync: false,
        anonymizeData: true,
        enablePerformanceTracking: true,
        enableErrorTracking: true
    )
}
