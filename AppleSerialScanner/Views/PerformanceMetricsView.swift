//
//  PerformanceMetricsView.swift
//  AppleSerialScanner
// Performance Optimization - Metrics Dashboard
//

import SwiftUI

private struct PerformanceMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct PerformanceMetricsView: View {
    @ObservedObject var scannerViewModel: SerialScannerViewModel
    @State private var refreshTimer: Timer?
    @State private var performanceData: [String: Any] = [:]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Performance Monitor")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Real-time app performance metrics and optimization status")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Performance Stats Card
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Image(systemName: "speedometer")
                                .foregroundColor(.blue)
                            Text("Processing Performance")
                                .font(.headline)
                            Spacer()
                        }
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 15) {
                            PerformanceMetricCard(
                                title: "Avg Processing Time",
                                value: "\(String(format: "%.1f", performanceData["avgProcessingTime"] as? Double ?? 0))ms",
                                icon: "clock",
                                color: getProcessingTimeColor()
                            )
                            
                            PerformanceMetricCard(
                                title: "Frames Processed",
                                value: "\(performanceData["framesProcessed"] as? Int ?? 0)",
                                icon: "camera.viewfinder",
                                color: .green
                            )
                            
                            PerformanceMetricCard(
                                title: "Frames Dropped",
                                value: "\(performanceData["framesDropped"] as? Int ?? 0)",
                                icon: "exclamationmark.triangle",
                                color: getDroppedFramesColor()
                            )
                            
                            PerformanceMetricCard(
                                title: "Queue Depth",
                                value: "\(performanceData["queueDepth"] as? Int ?? 0)",
                                icon: "list.bullet",
                                color: getQueueDepthColor()
                            )
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 2)
                    
                    // Power Management Card
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Image(systemName: "battery.100")
                                .foregroundColor(.orange)
                            Text("Power Management")
                                .font(.headline)
                            Spacer()
                        }
                        
                        VStack(spacing: 10) {
                            PowerStatusRow(
                                title: "Power Saving Mode",
                                isActive: scannerViewModel.isPowerSavingModeActive,
                                icon: "power"
                            )
                            
                            PowerStatusRow(
                                title: "Low Power Mode",
                                isActive: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                icon: "battery.25"
                            )
                            
                            HStack {
                                Image(systemName: "thermometer")
                                    .foregroundColor(getThermalStateColor())
                                Text("Thermal State")
                                    .font(.subheadline)
                                Spacer()
                                Text(ProcessInfo.processInfo.thermalState.description)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(getThermalStateColor())
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 2)
                    
                    // Optimization Status Card
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Image(systemName: "gear")
                                .foregroundColor(.purple)
                            Text("Optimization Status")
                                .font(.headline)
                            Spacer()
                            
                            Button("Optimize Now") {
                                scannerViewModel.optimizeForCurrentConditions()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        Text(scannerViewModel.getOptimizationStatus())
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 2)
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Performance")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            startRefreshing()
        }
        .onDisappear {
            stopRefreshing()
        }
    }
    
    private func startRefreshing() {
        refreshData()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            refreshData()
        }
    }
    
    private func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func refreshData() {
        performanceData = scannerViewModel.backgroundProcessingManager.getPerformanceStats()
    }
    
    // Color helpers
    private func getProcessingTimeColor() -> Color {
        let time = performanceData["avgProcessingTime"] as? Double ?? 0
        if time < 50 { return .green }
        else if time < 100 { return .orange }
        else { return .red }
    }
    
    private func getDroppedFramesColor() -> Color {
        let dropped = performanceData["framesDropped"] as? Int ?? 0
        let processed = performanceData["framesProcessed"] as? Int ?? 1
        let dropRate = Double(dropped) / Double(processed) * 100
        
        if dropRate < 5 { return .green }
        else if dropRate < 15 { return .orange }
        else { return .red }
    }
    
    private func getQueueDepthColor() -> Color {
        let depth = performanceData["queueDepth"] as? Int ?? 0
        if depth < 3 { return .green }
        else if depth < 6 { return .orange }
        else { return .red }
    }
    
    private func getThermalStateColor() -> Color {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }
}

struct PowerStatusRow: View {
    let title: String
    let isActive: Bool
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(isActive ? .green : .gray)
            Text(title)
                .font(.subheadline)
            Spacer()
            
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray)
            }
        }
    }
}

#Preview {
    PerformanceMetricsView(scannerViewModel: SerialScannerViewModel())
}
