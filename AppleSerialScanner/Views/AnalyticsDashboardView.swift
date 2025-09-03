import SwiftUI
import Charts

/// Comprehensive analytics dashboard for OCR performance insights
struct AnalyticsDashboardView: View {
    @StateObject private var analyticsService = AnalyticsService()
    @State private var selectedTimeRange: TimeRange = .today
    @State private var selectedMetric: MetricType = .accuracy

    enum TimeRange: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
        case all = "All Time"
    }

    enum MetricType: String, CaseIterable {
        case accuracy = "Accuracy"
        case performance = "Performance"
        case usage = "Usage"
        case reliability = "Reliability"
        case successRate = "Success Rate"
        case processingTime = "Processing Time"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    // Header with controls
                    AnalyticsHeaderView(
                        selectedTimeRange: $selectedTimeRange,
                        selectedMetric: $selectedMetric,
                        analyticsService: analyticsService
                    )

                    if analyticsService.isLoading {
                        ProgressView("Loading analytics...")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let dashboardData = analyticsService.dashboardData {
                        // Main metrics cards
                        AnalyticsMetricsCards(dashboardData: dashboardData)

                        // Charts section
                        AnalyticsChartsSection(
                            dashboardData: dashboardData,
                            selectedTimeRange: selectedTimeRange,
                            selectedMetric: selectedMetric
                        )

                        // Performance insights
                        PerformanceInsightsView(insights: dashboardData.performanceInsights)

                        // Recent sessions
                        RecentSessionsView(sessions: dashboardData.recentSessions)

                        // System health
                        SystemHealthView(systemHealth: dashboardData.systemHealth)

                    } else {
                        EmptyAnalyticsView()
                    }
                }
                .padding()
            }
            .navigationTitle("Analytics Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        analyticsService.updateDashboardData()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .onAppear {
            analyticsService.updateDashboardData()
        }
    }
}

// MARK: - Header View
struct AnalyticsHeaderView: View {
    @Binding var selectedTimeRange: AnalyticsDashboardView.TimeRange
    @Binding var selectedMetric: AnalyticsDashboardView.MetricType
    @ObservedObject var analyticsService: AnalyticsService

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("OCR Performance Analytics")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if let lastUpdate = analyticsService.lastUpdate {
                    Text("Updated \(lastUpdate.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(AnalyticsDashboardView.TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()

                Picker("Metric", selection: $selectedMetric) {
                    ForEach(AnalyticsDashboardView.MetricType.allCases, id: \.self) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
        }
    }
}

// MARK: - Metrics Cards
struct AnalyticsMetricsCards: View {
    let dashboardData: AnalyticsDashboardData

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {

            MetricCard(
                title: "Success Rate",
                value: "\(Int(dashboardData.todaySummary.successRate * 100))%",
                subtitle: "\(dashboardData.todaySummary.successfulSessions)/\(dashboardData.todaySummary.totalSessions) scans",
                icon: "checkmark.circle.fill",
                color: dashboardData.todaySummary.successRate >= 0.9 ? .green : .orange,
                trend: calculateTrend(.successRate)
            )

            MetricCard(
                title: "Avg Accuracy",
                value: "\(Int(dashboardData.todaySummary.averageAccuracy * 100))%",
                subtitle: "Confidence score",
                icon: "target",
                color: dashboardData.todaySummary.averageAccuracy >= 0.8 ? .blue : .red,
                trend: calculateTrend(.accuracy)
            )

            MetricCard(
                title: "Avg Processing",
                value: String(format: "%.2fs", dashboardData.todaySummary.averageProcessingTime),
                subtitle: "Per scan",
                icon: "timer",
                color: dashboardData.todaySummary.averageProcessingTime <= 2.0 ? .green : .orange,
                trend: calculateTrend(.processingTime)
            )

            MetricCard(
                title: "Total Scans",
                value: "\(dashboardData.todaySummary.totalSessions)",
                subtitle: "Today",
                icon: "chart.bar.fill",
                color: .purple,
                trend: calculateTrend(.usage)
            )
        }
    }

    private func calculateTrend(_ metric: AnalyticsDashboardView.MetricType) -> String? {
        // TODO: Calculate trend from weekly data
        // This would be implemented based on historical data
        return "+5.2%" // Placeholder
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    let trend: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 16, weight: .medium))

                if let trend = trend {
                    Text(trend)
                        .font(.caption2)
                        .foregroundColor(.green)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                }

                Spacer()
            }

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Charts Section
struct AnalyticsChartsSection: View {
    let dashboardData: AnalyticsDashboardData
    let selectedTimeRange: AnalyticsDashboardView.TimeRange
    let selectedMetric: AnalyticsDashboardView.MetricType

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Trends")
                .font(.headline)

            ChartContainer(title: "Accuracy Over Time") {
                AccuracyChart(data: prepareAccuracyData())
            }

            ChartContainer(title: "Processing Time Trends") {
                PerformanceChart(data: preparePerformanceData())
            }

            ChartContainer(title: "Surface Type Distribution") {
                SurfaceTypeChart(data: prepareSurfaceData())
            }
        }
    }

    private func prepareAccuracyData() -> [(Date, Double)] {
        // Convert weekly trend data to chart format
        dashboardData.weeklyTrend.accuracyTrend.map { (date, accuracy) in
            (date, accuracy)
        }.sorted { $0.0 < $1.0 }
    }

    private func preparePerformanceData() -> [(Date, TimeInterval)] {
        dashboardData.weeklyTrend.performanceTrend.map { (date, time) in
            (date, time)
        }.sorted { $0.0 < $1.0 }
    }

    private func prepareSurfaceData() -> [(String, Double)] {
        dashboardData.weeklyTrend.surfaceTypeDistribution.map { (type, percentage) in
            (type.capitalized, percentage)
        }.sorted { $0.1 > $1.1 }
    }
}

struct ChartContainer<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            content
                .frame(height: 200)
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct AccuracyChart: View {
    let data: [(Date, Double)]

    var body: some View {
        Chart {
            ForEach(data, id: \.0) { date, accuracy in
                LineMark(
                    x: .value("Date", date),
                    y: .value("Accuracy", accuracy)
                )
                .foregroundStyle(.blue)
                .symbol(.circle)
            }
        }
        .chartYAxis {
            AxisMarks(format: Decimal.FormatStyle.Percent.percent.scale(1))
        }
        .chartXAxis {
            AxisMarks(format: .dateTime.day().month())
        }
    }
}

struct PerformanceChart: View {
    let data: [(Date, TimeInterval)]

    var body: some View {
        Chart {
            ForEach(data, id: \.0) { date, time in
                LineMark(
                    x: .value("Date", date),
                    y: .value("Time", time)
                )
                .foregroundStyle(.orange)
                .symbol(.circle)
            }
        }
        .chartYAxis {ho
            AxisMarks(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1)))
        }
        .chartXAxis {
            AxisMarks(format: .dateTime.day().month())
        }
    }
}

struct SurfaceTypeChart: View {
    let data: [(String, Double)]

    var body: some View {
        Chart {
            ForEach(data, id: \.0) { type, percentage in
                SectorMark(
                    angle: .value("Percentage", percentage),
                    innerRadius: .ratio(0.5),
                    angularInset: 1
                )
                .foregroundStyle(by: .value("Surface Type", type))
            }
        }
        .chartLegend(position: .bottom)
    }
}

// MARK: - Performance Insights
struct PerformanceInsightsView: View {
    let insights: [PerformanceInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Insights")
                .font(.headline)

            if insights.isEmpty {
                Text("No insights available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
            } else {
                ForEach(insights) { insight in
                    InsightCard(insight: insight)
                }
            }
        }
    }
}

struct InsightCard: View {
    let insight: PerformanceInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(insight.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                ImpactBadge(impact: insight.impact)
            }

            Text(insight.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Text(insight.recommendation)
                .font(.caption)
                .foregroundColor(.blue)
                .fontWeight(.medium)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct ImpactBadge: View {
    let impact: InsightImpact

    var body: some View {
        Text(impact.rawValue.capitalized)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(impactColor.opacity(0.1))
            .foregroundColor(impactColor)
            .cornerRadius(4)
    }

    private var impactColor: Color {
        switch impact {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        case .critical: return .red
        }
    }
}

// MARK: - Recent Sessions
struct RecentSessionsView: View {
    let sessions: [AnalyticsData]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Sessions")
                .font(.headline)

            if sessions.isEmpty {
                Text("No recent sessions")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(sessions.prefix(5), id: \.sessionId) { session in
                    SessionRow(session: session)
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: AnalyticsData

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(session.accuracyMetrics.validationPassed ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.scanSession.bestResult?.serialNumber ?? "No result")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(session.timestamp.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(Int(session.accuracyMetrics.finalConfidence * 100))%")
                    .font(.subheadline)
                    .foregroundColor(session.accuracyMetrics.finalConfidence >= 0.8 ? .green : .orange)

                Text(String(format: "%.2fs", session.performanceMetrics.averageProcessingTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - System Health
struct SystemHealthView: View {
    let systemHealth: SystemHealthMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("System Health")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                SystemHealthCard(
                    title: "Storage",
                    value: "850GB free",
                    icon: "internaldrive",
                    color: .blue
                )

                SystemHealthCard(
                    title: "Battery",
                    value: batteryLevelValue(systemHealth.batteryLevel),
                    icon: "battery.100",
                    color: .green
                )

                SystemHealthCard(
                    title: "Network",
                    value: systemHealth.networkConnectivity.capitalized,
                    icon: "wifi",
                    color: .purple
                )

                SystemHealthCard(
                    title: "Thermal State",
                    value: systemHealth.thermalState.capitalized,
                    icon: "thermometer",
                    color: systemHealth.thermalState == "nominal" ? .green : .orange
                )
            }
        }
    }

    private func batteryLevelValue(_ batteryLevel: Float?) -> String {
        if let level = batteryLevel {
            return "\(Int(level * 100))%"
        }
        return "N/A"
    }
}

struct SystemHealthCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 16))

                Spacer()
            }

            Text(value)
                .font(.headline)
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Empty State
struct EmptyAnalyticsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Analytics Data Yet")
                .font(.headline)

            Text("Start scanning to see performance insights and analytics.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Preview
struct AnalyticsDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        AnalyticsDashboardView()
    }
}
