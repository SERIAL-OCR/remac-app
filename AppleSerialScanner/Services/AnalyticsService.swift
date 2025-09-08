import Foundation
import Combine

/// Comprehensive analytics service for OCR performance tracking and insights
@MainActor
class AnalyticsService: ObservableObject {
    // MARK: - Published Properties
    @Published var dashboardData: AnalyticsDashboardData?
    @Published var isLoading = false
    @Published var lastUpdate: Date?

    // MARK: - Private Properties
    private let configuration: AnalyticsConfiguration
    private var analyticsData: [AnalyticsData] = []
    private var cancellables = Set<AnyCancellable>()
    private let dataQueue = DispatchQueue(label: "com.appleserial.analytics", qos: .background)

    // MARK: - Initialization
    init(configuration: AnalyticsConfiguration = .default) {
        self.configuration = configuration
        loadExistingData()
        setupPeriodicUpdates()
    }

    // MARK: - Data Collection

    /// Record a complete scan session analytics
    func recordScanSession(_ analytics: AnalyticsData) {
        dataQueue.async { [weak self] in
            guard let self = self else { return }

            self.analyticsData.append(analytics)
            self.saveAnalyticsData()
            self.updateDashboardData()
        }
    }

    /// Record a partial scan event
    func recordScanEvent(_ event: AnalyticsEvent) {
        dataQueue.async { [weak self] in
            guard let self = self else { return }

            // Convert event to analytics data or update existing session
            // Implementation would merge with existing session data
            self.saveAnalyticsData()
            self.updateDashboardData()
        }
    }

    /// Record system health metrics
    func recordSystemHealth(_ metrics: SystemHealthMetrics) {
        dataQueue.async { [weak self] in
            guard let self = self else { return }

            // Store system health data for trending
            // Implementation would store in separate collection
            self.updateDashboardData()
        }
    }

    // MARK: - Data Processing

    /// Generate dashboard data from collected analytics
    func updateDashboardData() {
        isLoading = true
        
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            
            let todaySummary = self.generateTodaySummary()
            let weeklyTrend = self.generateWeeklyTrend()
            let recentSessions = self.getRecentSessions(limit: 10)
            let systemHealth = self.getLatestSystemHealth()
            let performanceInsights = self.generatePerformanceInsights()

            let dashboard = AnalyticsDashboardData(
                todaySummary: todaySummary,
                weeklyTrend: weeklyTrend,
                recentSessions: recentSessions,
                systemHealth: systemHealth,
                performanceInsights: performanceInsights
            )

            DispatchQueue.main.async { [weak self] in
                self?.dashboardData = dashboard
                self?.lastUpdate = Date()
                self?.isLoading = false
            }
        }
    }

    /// Generate today's analytics summary
    private func generateTodaySummary() -> DailyAnalyticsSummary {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        let todaySessions = analyticsData.filter { session in
            session.timestamp >= today && session.timestamp < tomorrow
        }

        let successfulSessions = todaySessions.filter { session in
            session.accuracyMetrics.validationPassed
        }

        let averageSessionDuration = todaySessions.reduce(0.0) { sum, session in
            sum + session.scanSession.duration
        } / Double(max(todaySessions.count, 1))

        let averageAccuracy = todaySessions.reduce(0.0) { sum, session in
            sum + Double(session.accuracyMetrics.finalConfidence)
        } / Double(max(todaySessions.count, 1))

        let averageProcessingTime = todaySessions.reduce(0.0) { sum, session in
            sum + session.performanceMetrics.averageProcessingTime
        } / Double(max(todaySessions.count, 1))

        // Calculate surface type distribution
        var surfaceTypeCounts: [String: Int] = [:]
        for session in todaySessions {
            let surfaceType = session.scanSession.bestResult?.surfaceType ?? "unknown"
            surfaceTypeCounts[surfaceType, default: 0] += 1
        }

        // Calculate failure reasons
        var failureReasons: [String: Int] = [:]
        for session in todaySessions where !session.accuracyMetrics.validationPassed {
            let reason = session.accuracyMetrics.errorType ?? "unknown"
            failureReasons[reason, default: 0] += 1
        }

        return DailyAnalyticsSummary(
            id: UUID(),
            date: today,
            totalSessions: todaySessions.count,
            successfulSessions: successfulSessions.count,
            averageSessionDuration: averageSessionDuration,
            averageAccuracy: averageAccuracy,
            averageProcessingTime: averageProcessingTime,
            topSurfaceTypes: surfaceTypeCounts,
            topFailureReasons: failureReasons,
            systemHealthScore: calculateSystemHealthScore(todaySessions)
        )
    }

    /// Generate weekly trend data
    private func generateWeeklyTrend() -> WeeklyAnalyticsTrend {
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!

        // Generate data for last 7 days
        var accuracyTrend: [Date: Double] = [:]
        var performanceTrend: [Date: TimeInterval] = [:]
        var usageTrend: [Date: Int] = [:]

        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

            let daySessions = analyticsData.filter { session in
                session.timestamp >= dayStart && session.timestamp < dayEnd
            }

            if !daySessions.isEmpty {
                let avgAccuracy = daySessions.reduce(0.0) { sum, session in
                    sum + Double(session.accuracyMetrics.finalConfidence)
                } / Double(daySessions.count)

                let avgProcessingTime = daySessions.reduce(0.0) { sum, session in
                    sum + session.performanceMetrics.averageProcessingTime
                } / Double(daySessions.count)

                accuracyTrend[dayStart] = avgAccuracy
                performanceTrend[dayStart] = avgProcessingTime
                usageTrend[dayStart] = daySessions.count
            }
        }

        // Calculate surface type distribution for the week
        var surfaceTypeCounts: [String: Int] = [:]
        let weekSessions = analyticsData.filter { session in
            session.timestamp >= weekStart
        }

        for session in weekSessions {
            let surfaceType = session.scanSession.bestResult?.surfaceType ?? "unknown"
            surfaceTypeCounts[surfaceType, default: 0] += 1
        }

        let totalSurfaceDetections = surfaceTypeCounts.values.reduce(0, +)
        var surfaceTypeDistribution: [String: Double] = [:]
        for (type, count) in surfaceTypeCounts {
            surfaceTypeDistribution[type] = Double(count) / Double(max(totalSurfaceDetections, 1))
        }

        return WeeklyAnalyticsTrend(
            id: UUID(),
            weekStart: weekStart,
            accuracyTrend: accuracyTrend,
            performanceTrend: performanceTrend,
            usageTrend: usageTrend,
            surfaceTypeDistribution: surfaceTypeDistribution,
            improvementAreas: identifyImprovementAreas(weekSessions)
        )
    }

    /// Generate performance insights and recommendations
    private func generatePerformanceInsights() -> [PerformanceInsight] {
        var insights: [PerformanceInsight] = []

        guard let dashboard = dashboardData else { return insights }

        // Accuracy insights
        if dashboard.todaySummary.averageAccuracy < 0.8 {
            insights.append(PerformanceInsight(
                type: .accuracy,
                title: "Low Accuracy Detected",
                description: "Today's average accuracy is below 80%. Consider checking lighting conditions or surface types.",
                impact: .high,
                recommendation: "Enable surface detection and ensure good lighting conditions.",
                confidence: 0.9
            ))
        }

        // Performance insights
        if dashboard.todaySummary.averageProcessingTime > 2.0 {
            insights.append(PerformanceInsight(
                type: .performance,
                title: "Slow Processing Time",
                description: "Average processing time is above 2 seconds, which may affect user experience.",
                impact: .medium,
                recommendation: "Consider reducing the number of processing frames or enabling GPU acceleration.",
                confidence: 0.8
            ))
        }

        // Usage insights
        if dashboard.todaySummary.successRate < 0.7 {
            insights.append(PerformanceInsight(
                type: .usability,
                title: "Low Success Rate",
                description: "Only \(Int(dashboard.todaySummary.successRate * 100))% of scans are successful.",
                impact: .high,
                recommendation: "Review common failure reasons and provide better user guidance.",
                confidence: 0.95
            ))
        }

        // Surface type insights
        if let metalCount = dashboard.todaySummary.topSurfaceTypes["metal"] {
            let totalScans = dashboard.todaySummary.totalSessions
            if totalScans > 0 && Double(metalCount) / Double(totalScans) > 0.8 {
                insights.append(PerformanceInsight(
                    type: .usability,
                    title: "Metal Surface Dominance",
                    description: "Most scans are on metal surfaces. Ensure metal surface optimization is enabled.",
                    impact: .low,
                    recommendation: "Metal surface detection is working well for your use case.",
                    confidence: 0.7
                ))
            }
        }

        return insights.sorted { $0.impact.rawValue > $1.impact.rawValue }
    }

    // MARK: - Helper Methods

    private func getRecentSessions(limit: Int) -> [AnalyticsData] {
        return Array(analyticsData.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    private func getLatestSystemHealth() -> SystemHealthMetrics {
        // Return the most recent system health data
        // In a real implementation, this would be stored separately
        return SystemHealthMetrics()
    }

    private func calculateSystemHealthScore(_ sessions: [AnalyticsData]) -> Double {
        guard !sessions.isEmpty else { return 1.0 }

        var score = 1.0

        // Reduce score based on various factors
        let avgAccuracy = sessions.reduce(0.0) { sum, session in
            sum + Double(session.accuracyMetrics.finalConfidence)
        } / Double(sessions.count)

        let avgProcessingTime = sessions.reduce(0.0) { sum, session in
            sum + session.performanceMetrics.averageProcessingTime
        } / Double(sessions.count)

        // Accuracy impact (0.4 weight)
        if avgAccuracy < 0.8 {
            score -= (0.8 - avgAccuracy) * 0.4
        }

        // Performance impact (0.3 weight)
        if avgProcessingTime > 2.0 {
            score -= min(0.3, (avgProcessingTime - 2.0) * 0.1)
        }

        // Success rate impact (0.3 weight)
        let successRate = Double(sessions.filter { $0.accuracyMetrics.validationPassed }.count) / Double(sessions.count)
        if successRate < 0.9 {
            score -= (0.9 - successRate) * 0.3
        }

        return max(0.0, min(1.0, score))
    }

    private func identifyImprovementAreas(_ sessions: [AnalyticsData]) -> [String] {
        var areas: [String] = []

        // Analyze accuracy trends
        let recentSessions = sessions.sorted { $0.timestamp > $1.timestamp }.prefix(10)
        let avgRecentAccuracy = recentSessions.reduce(0.0) { sum, session in
            sum + Double(session.accuracyMetrics.finalConfidence)
        } / Double(max(recentSessions.count, 1))

        let olderSessions = sessions.filter { session in
            session.timestamp < Date().addingTimeInterval(-7*24*3600) // 7 days ago
        }
        let avgOlderAccuracy = olderSessions.reduce(0.0) { sum, session in
            sum + Double(session.accuracyMetrics.finalConfidence)
        } / Double(max(olderSessions.count, 1))

        if avgRecentAccuracy < avgOlderAccuracy - 0.05 {
            areas.append("Accuracy is trending downward - review recent changes")
        }

        // Analyze surface type performance
        let surfacePerformance = Dictionary(grouping: sessions) { session in
            session.scanSession.bestResult?.surfaceType ?? "unknown"
        }.mapValues { sessions in
            sessions.reduce(0.0) { sum, session in
                sum + Double(session.accuracyMetrics.finalConfidence)
            } / Double(sessions.count)
        }

        if let worstSurface = surfacePerformance.min(by: { $0.value < $1.value }),
           worstSurface.value < 0.7 {
            areas.append("Poor performance on \(worstSurface.key) surfaces - consider optimization")
        }

        // Analyze timing issues
        let slowSessions = sessions.filter { $0.performanceMetrics.averageProcessingTime > 3.0 }
        if Double(slowSessions.count) / Double(sessions.count) > 0.2 {
            areas.append("High number of slow processing sessions - review performance bottlenecks")
        }

        return areas
    }

    // MARK: - Data Persistence

    private func loadExistingData() {
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let data = UserDefaults.standard.data(forKey: "analyticsData") {
                do {
                    self.analyticsData = try JSONDecoder().decode([AnalyticsData].self, from: data)
                } catch {
                    AppLogger.storage.error("Error loading analytics data: \(error.localizedDescription)")
                }
            }
            
            DispatchQueue.main.async {
                self.updateDashboardData()
            }
        }
    }

    private func saveAnalyticsData() {
        do {
            let data = try JSONEncoder().encode(analyticsData)
            UserDefaults.standard.set(data, forKey: "analyticsData")
        } catch {
            AppLogger.storage.error("Error saving analytics data: \(error.localizedDescription)")
        }
    }

    // MARK: - Periodic Updates

    private func setupPeriodicUpdates() {
        // Update dashboard every 5 minutes
        Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.dataQueue.async {
                    self?.updateDashboardData()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Export and Analysis

    /// Export analytics data in specified format
    func exportAnalytics(format: AnalyticsExportFormat, filters: AnalyticsFilters? = nil) -> URL? {
        let tempDirectory = FileManager.default.temporaryDirectory
        let filename = "analytics_export.\(format.fileExtension)"
        let fileURL = tempDirectory.appendingPathComponent(filename)

        do {
            let data = try JSONEncoder().encode(analyticsData)
            try data.write(to: fileURL)
            return fileURL
        } catch {
            AppLogger.storage.error("Error exporting analytics data: \(error.localizedDescription)")
            return nil
        }
    }

    /// Clear old analytics data based on retention policy
    func cleanupOldData() {
        let cutoffDate = Date().addingTimeInterval(-configuration.retentionPeriod * 24 * 3600)

        dataQueue.async { [weak self] in
            guard let self = self else { return }

            self.analyticsData = self.analyticsData.filter { session in
                session.timestamp >= cutoffDate
            }

            self.saveAnalyticsData()
            self.updateDashboardData()
        }
    }
}

// MARK: - Analytics Event Types

enum AnalyticsEvent {
    case scanStarted(sessionId: UUID)
    case frameProcessed(sessionId: UUID, processingTime: TimeInterval, confidence: Float)
    case surfaceDetected(sessionId: UUID, surfaceType: String, confidence: Float)
    case lightingChanged(sessionId: UUID, lightingCondition: String, confidence: Float)
    case angleCorrected(sessionId: UUID, angle: Double, confidence: Float)
    case scanCompleted(sessionId: UUID, success: Bool, finalConfidence: Float)
    case scanFailed(sessionId: UUID, error: String)
}
