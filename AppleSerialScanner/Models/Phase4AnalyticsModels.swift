import Foundation

/// Detailed analytics for Phase 4 rejection tracking
struct Phase4RejectionAnalytics: Codable {
    let sessionId: UUID
    let timestamp: Date
    
    // Per-step rejection counters
    var rejectionsByStage: [String: Int]
    var rejectionsByReason: [String: Int]
    
    // Stage timing metrics
    var stageTimings: [String: TimeInterval]
    
    // Final acceptance metrics
    var totalCandidates: Int
    var acceptedCandidates: Int
    var finalAcceptanceRate: Double
    
    // Confidence distribution
    var confidenceDistribution: ConfidenceDistribution
    
    init(sessionId: UUID = UUID(),
         rejectionsByStage: [String: Int] = [:],
         rejectionsByReason: [String: Int] = [:],
         stageTimings: [String: TimeInterval] = [:],
         totalCandidates: Int = 0,
         acceptedCandidates: Int = 0,
         confidenceDistribution: ConfidenceDistribution = ConfidenceDistribution()) {
        self.sessionId = sessionId
        self.timestamp = Date()
        self.rejectionsByStage = rejectionsByStage
        self.rejectionsByReason = rejectionsByReason
        self.stageTimings = stageTimings
        self.totalCandidates = totalCandidates
        self.acceptedCandidates = acceptedCandidates
        self.finalAcceptanceRate = totalCandidates > 0 ? Double(acceptedCandidates) / Double(totalCandidates) : 0.0
        self.confidenceDistribution = confidenceDistribution
    }
}

/// Confidence distribution metrics for Phase 4
struct ConfidenceDistribution: Codable {
    var veryLow: Int = 0    // 0.0-0.3
    var low: Int = 0        // 0.3-0.5
    var medium: Int = 0     // 0.5-0.7
    var high: Int = 0       // 0.7-0.9
    var veryHigh: Int = 0   // 0.9-1.0
    
    init(veryLow: Int = 0, low: Int = 0, medium: Int = 0, high: Int = 0, veryHigh: Int = 0) {
        self.veryLow = veryLow
        self.low = low
        self.medium = medium
        self.high = high
        self.veryHigh = veryHigh
    }
    
    init(values: [Float]) {
        for value in values {
            switch value {
            case 0.0..<0.3: veryLow += 1
            case 0.3..<0.5: low += 1
            case 0.5..<0.7: medium += 1
            case 0.7..<0.9: high += 1
            case 0.9...1.0: veryHigh += 1
            default: break
            }
        }
    }
    
    mutating func add(_ confidence: Float) {
        switch confidence {
        case 0.0..<0.3: veryLow += 1
        case 0.3..<0.5: low += 1
        case 0.5..<0.7: medium += 1
        case 0.7..<0.9: high += 1
        case 0.9...1.0: veryHigh += 1
        default: break
        }
    }
}

/// Per-stage rejection event tracking
struct StageRejectionEvent: Codable {
    let timestamp: Date
    let stage: String
    let reason: String
    let inputText: String
    let confidence: Float
    let processingTime: TimeInterval
}

/// Stage timing tracker
struct StageTimingTracker: Codable {
    let stageName: String
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let success: Bool
}

/// Rejection insights analysis
struct Phase4RejectionInsights: Codable {
    let totalSessions: Int
    let overallAcceptanceRate: Double
    let topRejectionReasons: [String: Int]
    let stagePerformance: [String: Double]
    let confidenceTrends: [Date: ConfidenceDistribution]
    let recommendations: [String]
    
    init(analytics: [Phase4RejectionAnalytics]) {
        self.totalSessions = analytics.count
        self.overallAcceptanceRate = analytics.reduce(0.0) { $0 + $1.finalAcceptanceRate } / Double(max(analytics.count, 1))
        
        // Aggregate rejection reasons
        var reasons: [String: Int] = [:]
        analytics.forEach { session in
            session.rejectionsByReason.forEach { reason, count in
                reasons[reason, default: 0] += count
            }
        }
        self.topRejectionReasons = reasons
        
        // Calculate stage performance
        var performance: [String: Double] = [:]
        analytics.forEach { session in
            session.stageTimings.forEach { stage, time in
                performance[stage, default: 0.0] += time
            }
        }
        self.stagePerformance = performance.mapValues { $0 / Double(analytics.count) }
        
        // Track confidence trends over time
        var trends: [Date: ConfidenceDistribution] = [:]
        analytics.forEach { session in
            trends[session.timestamp] = session.confidenceDistribution
        }
        self.confidenceTrends = trends
        
        // Generate recommendations
        self.recommendations = Self.generateRecommendations(
            acceptanceRate: overallAcceptanceRate,
            rejectionReasons: reasons,
            stagePerformance: performance
        )
    }
    
    private static func generateRecommendations(
        acceptanceRate: Double,
        rejectionReasons: [String: Int],
        stagePerformance: [String: Double]
    ) -> [String] {
        var recommendations: [String] = []
        
        if acceptanceRate < 0.7 {
            recommendations.append("Low overall acceptance rate (\(Int(acceptanceRate * 100))%) - Review validation criteria")
        }
        
        if let topReason = rejectionReasons.max(by: { $0.value < $1.value }) {
            recommendations.append("Most common rejection reason: \(topReason.key)")
        }
        
        if let slowestStage = stagePerformance.max(by: { $0.value < $1.value }),
           slowestStage.value > 1.0 {
            recommendations.append("Stage '\(slowestStage.key)' is slow (avg. \(String(format: "%.2f", slowestStage.value))s)")
        }
        
        return recommendations
    }
}

extension AnalyticsDashboardData {
    mutating func updateRejectionData(_ analytics: Phase4RejectionAnalytics) {
        // Update relevant dashboard metrics with Phase 4 data
        // This would typically update specific sections of the dashboard
        // that track rejection patterns and validation performance
    }
}
