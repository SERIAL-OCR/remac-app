import Foundation

struct AnalyticsDashboardData: Codable {
    let todaySummary: DailyAnalyticsSummary
    let weeklyTrend: WeeklyAnalyticsTrend
    let recentSessions: [AnalyticsData]
    let systemHealth: SystemHealthMetrics
    let performanceInsights: [PerformanceInsight]
}
