import Foundation

// Adding Identifiable and Codable for compatibility with AnalyticsModels.swift
struct WeeklyAnalyticsTrend: Identifiable, Codable {
    let id: UUID
    let weekStart: Date
    let accuracyTrend: [Date: Double]
    let performanceTrend: [Date: TimeInterval]
    let usageTrend: [Date: Int]
    let surfaceTypeDistribution: [String: Double]
    let improvementAreas: [String]
}
