import Foundation
#if os(iOS)
import UIKit
#endif

/// Struct representing comprehensive system health metrics for monitoring app performance and resource usage
struct SystemHealthMonitor: Codable, Equatable {
    // System resources
    let cpuUsage: Double
    let memoryUsage: Double
    let diskSpace: DiskSpace
    let batteryLevel: Double?
    
    // App performance
    let appUptime: TimeInterval
    let scanPerformance: ScanPerformance
    let networkStatus: NetworkStatus
    let timestamp: Date
    
    // Initializer with default values
    init(
        cpuUsage: Double = 0.0,
        memoryUsage: Double = 0.0,
        diskSpace: DiskSpace = DiskSpace(),
        batteryLevel: Double? = nil,
        appUptime: TimeInterval = 0.0,
        scanPerformance: ScanPerformance = ScanPerformance(),
        networkStatus: NetworkStatus = .unknown,
        timestamp: Date = Date()
    ) {
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.diskSpace = diskSpace
        self.batteryLevel = batteryLevel
        self.appUptime = appUptime
        self.scanPerformance = scanPerformance
        self.networkStatus = networkStatus
        self.timestamp = timestamp
    }
    
    // MARK: - Disk Space
    
    /// Information about available and total disk space
    struct DiskSpace: Codable, Equatable {
        let totalSpace: Int64
        let availableSpace: Int64
        
        var usedPercentage: Double {
            guard totalSpace > 0 else { return 0 }
            return Double(totalSpace - availableSpace) / Double(totalSpace) * 100.0
        }
        
        init(totalSpace: Int64 = 0, availableSpace: Int64 = 0) {
            self.totalSpace = totalSpace
            self.availableSpace = availableSpace
        }
        
        func formattedTotal() -> String {
            return formatBytes(totalSpace)
        }
        
        func formattedAvailable() -> String {
            return formatBytes(availableSpace)
        }
        
        private func formatBytes(_ bytes: Int64) -> String {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useAll]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: bytes)
        }
    }
    
    // MARK: - Scan Performance
    
    /// Performance metrics specific to the scanning functionality
    struct ScanPerformance: Codable, Equatable {
        let averageScanTime: TimeInterval
        let scanSuccessRate: Double
        let framesPerSecond: Double
        let recognitionLatency: TimeInterval
        let processingOverhead: Double
        
        init(
            averageScanTime: TimeInterval = 0.0,
            scanSuccessRate: Double = 0.0,
            framesPerSecond: Double = 0.0,
            recognitionLatency: TimeInterval = 0.0,
            processingOverhead: Double = 0.0
        ) {
            self.averageScanTime = averageScanTime
            self.scanSuccessRate = scanSuccessRate
            self.framesPerSecond = framesPerSecond
            self.recognitionLatency = recognitionLatency
            self.processingOverhead = processingOverhead
        }
    }
    
    // MARK: - Network Status
    
    /// Network connectivity state
    enum NetworkStatus: String, Codable, CaseIterable {
        case wifi
        case cellular
        case offline
        case unknown
    }
    
    // MARK: - Health Status
    
    /// Overall system health status based on metrics
    var healthStatus: HealthStatus {
        if cpuUsage > 80 || memoryUsage > 90 || diskSpace.usedPercentage > 95 {
            return .critical
        } else if cpuUsage > 60 || memoryUsage > 70 || diskSpace.usedPercentage > 85 {
            return .warning
        } else if networkStatus == .offline {
            return .degraded
        } else {
            return .healthy
        }
    }
    
    /// System health status classification
    enum HealthStatus: String {
        case healthy
        case degraded
        case warning
        case critical
        
        var description: String {
            switch self {
            case .healthy:
                return "System operating normally"
            case .degraded:
                return "Reduced functionality (network issues)"
            case .warning:
                return "Performance degradation detected"
            case .critical:
                return "Critical resource constraints"
            }
        }
    }
    
    // MARK: - Static Methods

    /// Creates a metrics snapshot of the current system state.
    /// - NOTE: This is a placeholder implementation. In a real implementation, this would gather actual system metrics.
    static func captureCurrentMetrics() -> SystemHealthMonitor {
        // In a real implementation, this would gather actual system metrics
        // For now, using placeholder values that would be replaced with actual system calls
        
        #if os(iOS)
        let batteryLevel = UIDevice.current.isBatteryMonitoringEnabled ?
            Double(UIDevice.current.batteryLevel) * 100 : nil
        #else
        let batteryLevel: Double? = nil
        #endif
        
        // CPU and memory would be gathered using process info APIs
        let cpuUsage = Double.random(in: 10...40) // Placeholder
        let memoryUsage = Double.random(in: 20...60) // Placeholder
        
        // Disk space would use FileManager APIs
        let totalSpace: Int64 = 512 * 1024 * 1024 * 1024 // 512 GB placeholder
        let availableSpace: Int64 = 256 * 1024 * 1024 * 1024 // 256 GB placeholder
        let diskSpace = DiskSpace(totalSpace: totalSpace, availableSpace: availableSpace)
        
        // App uptime would be calculated from app launch time
        let appUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
        
        // Scan performance metrics would be gathered from analytics
        let scanPerformance = ScanPerformance(
            averageScanTime: 1.2,
            scanSuccessRate: 0.95,
            framesPerSecond: 30,
            recognitionLatency: 0.3,
            processingOverhead: 0.15
        )
        
        // Network status would be determined using NWPathMonitor
        let networkStatus = NetworkStatus.wifi
        
        return SystemHealthMonitor(
            cpuUsage: cpuUsage,
            memoryUsage: memoryUsage,
            diskSpace: diskSpace,
            batteryLevel: batteryLevel,
            appUptime: appUptime,
            scanPerformance: scanPerformance,
            networkStatus: networkStatus,
            timestamp: Date()
        )
    }
    
    /// Returns a description of any detected performance issues
    func getPerformanceIssues() -> [String] {
        var issues = [String]()
        
        if cpuUsage > 80 {
            issues.append("High CPU usage: \(String(format: "%.1f", cpuUsage))%")
        }
        
        if memoryUsage > 80 {
            issues.append("High memory usage: \(String(format: "%.1f", memoryUsage))%")
        }
        
        if diskSpace.usedPercentage > 90 {
            issues.append("Low disk space: \(String(format: "%.1f", 100 - diskSpace.usedPercentage))% available")
        }
        
        if let batteryLevel = batteryLevel, batteryLevel < 20 {
            issues.append("Low battery: \(String(format: "%.1f", batteryLevel))%")
        }
        
        if scanPerformance.framesPerSecond < 15 {
            issues.append("Low frame rate: \(String(format: "%.1f", scanPerformance.framesPerSecond)) FPS")
        }
        
        if scanPerformance.scanSuccessRate < 0.7 {
            issues.append("Low scan success rate: \(String(format: "%.1f", scanPerformance.scanSuccessRate * 100))%")
        }
        
        if networkStatus == .offline {
            issues.append("No network connectivity")
        }
        
        return issues
    }
    
    // MARK: - Conversion Methods
    
    /// Convert the comprehensive monitor to the simplified metrics struct used elsewhere
    func toSystemHealthMetrics() -> SystemHealthMetrics {
        var battery: Float? = nil
        if let batteryLevel = batteryLevel {
            battery = Float(batteryLevel / 100.0)
        }
        return SystemHealthMetrics(
            batteryLevel: battery,
            thermalState: cpuUsage > 70 ? "Warning" : "Normal",
            networkConnectivity: networkStatus.rawValue,
            storageAvailable: UInt64(diskSpace.availableSpace),
            appCrashes: 0, // Placeholder
            systemWarnings: getPerformanceIssues().count
        )
    }
}
