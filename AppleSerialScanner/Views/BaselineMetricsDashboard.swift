import SwiftUI
import Foundation

/// Phase 0: Comprehensive baseline metrics dashboard for performance analysis
/// Displays real-time OCR metrics, camera settings, and stability tracking
struct BaselineMetricsDashboard: View {
    @ObservedObject var viewModel: SerialScannerViewModel
    @State private var showExportSheet = false
    @State private var exportData: Data?
    @State private var refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Real-time Performance Overview
                    PerformanceOverviewCard(metrics: viewModel.currentBaselineMetrics)
                    
                    // OCR Metrics Section
                    OCRMetricsCard(metrics: viewModel.currentBaselineMetrics)
                    
                    // Camera Settings Section
                    CameraSettingsCard(metrics: viewModel.currentBaselineMetrics)
                    
                    // Stability Tracking Section
                    StabilityMetricsCard(metrics: viewModel.currentBaselineMetrics)
                    
                    // Performance Insights
                    PerformanceInsightsCard(insights: viewModel.currentBaselineMetrics?.performanceInsights ?? [])
                    
                    // Export Controls
                    ExportControlsCard(
                        onExport: exportMetrics,
                        onReset: resetMetrics
                    )
                }
                .padding()
            }
            .navigationTitle("Phase 0: Baseline Metrics")
            .navigationBarTitleDisplayMode(.large)
            .onReceive(refreshTimer) { _ in
                refreshMetrics()
            }
            .sheet(isPresented: $showExportSheet) {
                MetricsExportSheet(data: exportData)
            }
        }
    }
    
    private func refreshMetrics() {
        viewModel.refreshBaselineMetrics()
    }
    
    private func exportMetrics() {
        exportData = viewModel.exportBaselineMetrics()
        showExportSheet = true
    }
    
    private func resetMetrics() {
        viewModel.resetBaselineMetrics()
    }
}

// MARK: - Performance Overview Card

struct PerformanceOverviewCard: View {
    let metrics: BaselineMetricsCollector.BaselineReport?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Overview")
                .font(.headline)
                .foregroundColor(.primary)
            
            if let metrics = metrics {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    MetricTile(
                        title: "Total Frames",
                        value: "\(metrics.totalFrames)",
                        subtitle: "processed",
                        color: .blue
                    )
                    
                    MetricTile(
                        title: "Avg OCR Latency",
                        value: String(format: "%.1fms", metrics.averageOCRLatency * 1000),
                        subtitle: "per frame",
                        color: metrics.averageOCRLatency > 0.1 ? .orange : .green
                    )
                    
                    MetricTile(
                        title: "Avg Confidence",
                        value: String(format: "%.2f", metrics.averageConfidence),
                        subtitle: "recognition",
                        color: metrics.averageConfidence > 0.7 ? .green : .red
                    )
                    
                    MetricTile(
                        title: "Stability Time",
                        value: String(format: "%.1fs", metrics.averageStabilityTimeToLock),
                        subtitle: "to lock",
                        color: metrics.averageStabilityTimeToLock < 2.5 ? .green : .orange
                    )
                }
            } else {
                Text("No baseline metrics available")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// MARK: - OCR Metrics Card

struct OCRMetricsCard: View {
    let metrics: BaselineMetricsCollector.BaselineReport?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OCR Performance Metrics")
                .font(.headline)
                .foregroundColor(.primary)
            
            if let metrics = metrics {
                VStack(spacing: 12) {
                    HStack {
                        Text("Median Latency:")
                        Spacer()
                        Text(String(format: "%.1fms", metrics.medianOCRLatency * 1000))
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("95th Percentile:")
                        Spacer()
                        Text(String(format: "%.1fms", metrics.p95OCRLatency * 1000))
                            .fontWeight(.semibold)
                            .foregroundColor(metrics.p95OCRLatency > 0.2 ? .orange : .primary)
                    }
                    
                    HStack {
                        Text("Average Glyph Height:")
                        Spacer()
                        Text(String(format: "%.1fpx", metrics.averageGlyphHeight))
                            .fontWeight(.semibold)
                            .foregroundColor(metrics.averageGlyphHeight < 20 ? .orange : .primary)
                    }
                    
                    HStack {
                        Text("Failure Rate:")
                        Spacer()
                        Text(String(format: "%.2f%%", metrics.failureRate * 100))
                            .fontWeight(.semibold)
                            .foregroundColor(metrics.failureRate > 0.05 ? .red : .green)
                    }
                    
                    HStack {
                        Text("Frame Drop Rate:")
                        Spacer()
                        Text(String(format: "%.2f%%", metrics.frameDropRate * 100))
                            .fontWeight(.semibold)
                            .foregroundColor(metrics.frameDropRate > 0.1 ? .orange : .green)
                    }
                }
            } else {
                Text("No OCR metrics available")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// MARK: - Camera Settings Card

struct CameraSettingsCard: View {
    let metrics: BaselineMetricsCollector.BaselineReport?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Camera Settings")
                .font(.headline)
                .foregroundColor(.primary)
            
            if let cameraSettings = metrics?.cameraSettings {
                VStack(spacing: 12) {
                    if let avgExposure = cameraSettings.averageExposure {
                        HStack {
                            Text("Average Exposure:")
                            Spacer()
                            Text(String(format: "%.3f", avgExposure))
                                .fontWeight(.semibold)
                        }
                    }
                    
                    if let avgISO = cameraSettings.averageISO {
                        HStack {
                            Text("Average ISO:")
                            Spacer()
                            Text(String(format: "%.0f", avgISO))
                                .fontWeight(.semibold)
                                .foregroundColor(avgISO > 800 ? .orange : .primary)
                        }
                    }
                    
                    HStack {
                        Text("Focus Mode:")
                        Spacer()
                        Text(cameraSettings.focusMode)
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Video Format:")
                        Spacer()
                        Text(cameraSettings.videoFormat)
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Frame Rate:")
                        Spacer()
                        Text(String(format: "%.1f fps", cameraSettings.frameRate))
                            .fontWeight(.semibold)
                    }
                }
            } else {
                Text("No camera settings available")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// MARK: - Stability Metrics Card

struct StabilityMetricsCard: View {
    let metrics: BaselineMetricsCollector.BaselineReport?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stability Tracking")
                .font(.headline)
                .foregroundColor(.primary)
            
            if let metrics = metrics {
                VStack(spacing: 12) {
                    HStack {
                        Text("Session Duration:")
                        Spacer()
                        Text(formatDuration(metrics.endTime.timeIntervalSince(metrics.startTime)))
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Time to Lock:")
                        Spacer()
                        Text(String(format: "%.1fs", metrics.averageStabilityTimeToLock))
                            .fontWeight(.semibold)
                            .foregroundColor(getStabilityColor(metrics.averageStabilityTimeToLock))
                    }
                    
                    // Stability performance indicator
                    HStack {
                        Text("Stability Performance:")
                        Spacer()
                        Text(getStabilityPerformance(metrics.averageStabilityTimeToLock))
                            .fontWeight(.semibold)
                            .foregroundColor(getStabilityColor(metrics.averageStabilityTimeToLock))
                    }
                }
            } else {
                Text("No stability metrics available")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func getStabilityColor(_ timeToLock: TimeInterval) -> Color {
        if timeToLock <= 2.5 { return .green }
        else if timeToLock <= 5.0 { return .orange }
        else { return .red }
    }
    
    private func getStabilityPerformance(_ timeToLock: TimeInterval) -> String {
        if timeToLock <= 2.5 { return "Excellent" }
        else if timeToLock <= 5.0 { return "Good" }
        else { return "Needs Improvement" }
    }
}

// MARK: - Performance Insights Card

struct PerformanceInsightsCard: View {
    let insights: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Insights")
                .font(.headline)
                .foregroundColor(.primary)
            
            if !insights.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(insights, id: \.self) { insight in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                                .padding(.top, 2)
                            
                            Text(insight)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text("No performance insights available")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// MARK: - Export Controls Card

struct ExportControlsCard: View {
    let onExport: () -> Void
    let onReset: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Metrics Controls")
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack(spacing: 16) {
                Button(action: onExport) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export Data")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                Button(action: onReset) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Reset Metrics")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// MARK: - Supporting Views

struct MetricTile: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

struct MetricsExportSheet: View {
    let data: Data?
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let data = data {
                    Text("Metrics data exported successfully")
                        .font(.title2)
                        .foregroundColor(.green)
                    
                    Text("\(data.count) bytes of metrics data ready for analysis")
                        .foregroundColor(.secondary)
                    
                    Button("Save to Files") {
                        saveToFiles(data)
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                } else {
                    Text("Failed to export metrics data")
                        .font(.title2)
                        .foregroundColor(.red)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Export Metrics")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
    
    private func saveToFiles(_ data: Data) {
        // Implementation would save to Files app
        // For now, just dismiss
        presentationMode.wrappedValue.dismiss()
    }
}

#Preview {
    BaselineMetricsDashboard(viewModel: SerialScannerViewModel())
}