import Foundation
import Combine
import os.log

/// System health monitoring and reporting service
class HealthMonitoringService {
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "HealthMonitoring")
    
    // Internal monitor snapshot (rich metrics)
    private var systemHealthMonitor: SystemHealthMonitor = SystemHealthMonitor.captureCurrentMetrics()

    // Health metrics published for consumers (simplified view)
    @Published private(set) var systemHealth = SystemHealthMetrics()
    @Published private(set) var subsystemStatuses: [String: SubsystemStatus] = [:]
    @Published private(set) var performanceMetrics = HealthPerformanceMetrics()
    
    // Monitoring configuration
    private let monitoringInterval: TimeInterval = 30.0
    private let healthThresholds = HealthThresholds()
    private var healthChecks: [HealthCheck] = []
    private var cancellables = Set<AnyCancellable>()
    
    // Error tracking
    private var errorHistory: [ErrorRecord] = []
    private let maxErrorHistorySize = 100
    
    init() {
        setupHealthChecks()
        startMonitoring()
    }
    
    /// Register a subsystem for health monitoring
    func registerSubsystem(_ name: String, checks: [HealthCheck]) {
        subsystemStatuses[name] = .normal
        healthChecks.append(contentsOf: checks)
        logger.info("Registered subsystem: \(name) with \(checks.count) health checks")
    }
    
    /// Report an error for tracking
    func reportError(_ error: Error, subsystem: String) {
        let record = ErrorRecord(
            timestamp: Date(),
            subsystem: subsystem,
            error: error
        )
        
        // Add to history with size limit
        errorHistory.append(record)
        if errorHistory.count > maxErrorHistorySize {
            errorHistory.removeFirst()
        }
        
        // Update subsystem status
        updateSubsystemStatus(subsystem)
        
        // Analyze error patterns
        analyzeErrorPatterns()
    }
    
    /// Get health report for a time period
    func getHealthReport(for period: TimeInterval) -> HealthReport {
        let startDate = Date().addingTimeInterval(-period)
        
        // Filter relevant data
        let relevantErrors = errorHistory.filter { $0.timestamp >= startDate }
        let errorRates = calculateErrorRates(from: relevantErrors)
        let recommendations = generateRecommendations(
            errors: relevantErrors,
            monitor: systemHealthMonitor
        )
        
        return HealthReport(
            timestamp: Date(),
            period: period,
            systemHealth: systemHealth,
            subsystemStatuses: subsystemStatuses,
            performanceMetrics: performanceMetrics,
            errorRates: errorRates,
            recommendations: recommendations
        )
    }
    
    // MARK: - Private Methods
    
    private func setupHealthChecks() {
        // Memory usage check (use monitor for raw metrics)
        healthChecks.append(HealthCheck(
            name: "Memory Usage",
            check: { [weak self] in
                guard let self = self else { return .failed(error: nil) }
                return self.systemHealthMonitor.memoryUsage < self.healthThresholds.maxMemoryUsage
                    ? .passed
                    : .warning(message: "High memory usage")
            }
        ))
        
        // CPU usage check
        healthChecks.append(HealthCheck(
            name: "CPU Usage",
            check: { [weak self] in
                guard let self = self else { return .failed(error: nil) }
                return self.systemHealthMonitor.cpuUsage < self.healthThresholds.maxCPUUsage
                    ? .passed
                    : .warning(message: "High CPU usage")
            }
        ))
        
        // Frame rate check
        healthChecks.append(HealthCheck(
            name: "Frame Rate",
            check: { [weak self] in
                guard let self = self else { return .failed(error: nil) }
                return self.performanceMetrics.frameRate >= self.healthThresholds.minFrameRate
                    ? .passed
                    : .warning(message: "Low frame rate")
            }
        ))
    }
    
    private func startMonitoring() {
        // Regular health checks
        Timer.publish(every: monitoringInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.performHealthChecks()
            }
            .store(in: &cancellables)
        
        // Update system metrics
        Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateSystemMetrics()
            }
            .store(in: &cancellables)
    }
    
    private func performHealthChecks() {
        for check in healthChecks {
            let result = check.check()
            
            switch result {
            case .failed(let error):
                logger.error("\(check.name) failed: \(error?.localizedDescription ?? "Unknown error")")
                if let error = error {
                    reportError(error, subsystem: check.name)
                }
            case .warning(let message):
                logger.warning("\(check.name) warning: \(message)")
            case .passed:
                logger.debug("\(check.name) passed")
            }
        }
    }
    
    private func updateSystemMetrics() {
        // Capture latest monitor snapshot and publish simplified view
        systemHealthMonitor = SystemHealthMonitor.captureCurrentMetrics()
        systemHealth = systemHealthMonitor.toSystemHealthMetrics()

        // Update performance metrics
        performanceMetrics.update()
    }
    
    private func updateSubsystemStatus(_ subsystem: String) {
        let recentErrors = errorHistory.filter {
            $0.subsystem == subsystem &&
            $0.timestamp.timeIntervalSinceNow > -300 // Last 5 minutes
        }
        
        let status: SubsystemStatus
        switch recentErrors.count {
        case 0:
            status = .normal
        case 1...3:
            status = .degraded
        default:
            status = .failing
        }
        
        subsystemStatuses[subsystem] = status
    }
    
    private func analyzeErrorPatterns() {
        let recentErrors = errorHistory.filter {
            $0.timestamp.timeIntervalSinceNow > -3600 // Last hour
        }
        
        // Group errors by subsystem
        let errorsBySubsystem = Dictionary(grouping: recentErrors) { $0.subsystem }
        
        // Check for error clusters
        errorsBySubsystem.forEach { (subsystem, errors) in
            if errors.count >= 5 {
                logger.warning("Error cluster detected in \(subsystem): \(errors.count) errors in the last hour")
            }
        }
    }
    
    private func calculateErrorRates(from errors: [ErrorRecord]) -> [String: ErrorRate] {
        var rates: [String: ErrorRate] = [:]
        
        let errorsBySubsystem = Dictionary(grouping: errors) { $0.subsystem }
        errorsBySubsystem.forEach { (subsystem, errors) in
            let total = errors.count
            let unique = Set(errors.map { String(describing: type(of: $0.error)) }).count
            
            rates[subsystem] = ErrorRate(
                total: total,
                unique: unique,
                timespan: errors.last?.timestamp.timeIntervalSince(errors.first?.timestamp ?? Date()) ?? 0
            )
        }
        
        return rates
    }
    
    private func generateRecommendations(errors: [ErrorRecord], monitor: SystemHealthMonitor) -> [HealthRecommendation] {
        var recommendations: [HealthRecommendation] = []
        
        // Check system resources
        if monitor.memoryUsage > healthThresholds.maxMemoryUsage {
            recommendations.append(
                HealthRecommendation(
                    priority: .high,
                    message: "High memory usage detected. Consider implementing memory optimization.",
                    action: .optimize("memory")
                )
            )
        }
        
        if monitor.cpuUsage > healthThresholds.maxCPUUsage {
            recommendations.append(
                HealthRecommendation(
                    priority: .high,
                    message: "High CPU usage detected. Review processing intensive operations.",
                    action: .optimize("cpu")
                )
            )
        }
        
        // Check error patterns
        let errorsBySubsystem = Dictionary(grouping: errors) { $0.subsystem }
        errorsBySubsystem.forEach { (subsystem, errors) in
            if errors.count >= 5 {
                recommendations.append(
                    HealthRecommendation(
                        priority: .medium,
                        message: "Multiple errors detected in \(subsystem). Consider maintenance.",
                        action: .investigate(subsystem)
                    )
                )
            }
        }
        
        return recommendations
    }
}

// MARK: - Supporting Types

struct HealthCheck {
    let name: String
    let check: () -> HealthCheckResult
}

enum HealthCheckResult {
    case passed
    case warning(message: String)
    case failed(error: Error?)
}

struct HealthThresholds {
    let maxMemoryUsage: Double = 0.85
    let maxCPUUsage: Double = 0.75
    let minFrameRate: Double = 24.0
}

struct ErrorRecord {
    let timestamp: Date
    let subsystem: String
    let error: Error
}

struct ErrorRate {
    let total: Int
    let unique: Int
    let timespan: TimeInterval
    
    var frequency: Double {
        return timespan > 0 ? Double(total) / timespan : 0
    }
}

struct HealthReport {
    let timestamp: Date
    let period: TimeInterval
    let systemHealth: SystemHealthMetrics
    let subsystemStatuses: [String: SubsystemStatus]
    let performanceMetrics: HealthPerformanceMetrics
    let errorRates: [String: ErrorRate]
    let recommendations: [HealthRecommendation]
}

struct HealthRecommendation {
    enum Priority {
        case low, medium, high
    }
    
    enum Action {
        case optimize(String)
        case investigate(String)
        case restart(String)
    }
    
    let priority: Priority
    let message: String
    let action: Action
}

// Rename local performance metrics to avoid conflicting with analytics PerformanceMetrics
struct HealthPerformanceMetrics {
    private(set) var frameRate: Double = 0
    private(set) var processingTime: TimeInterval = 0
    private(set) var memoryFootprint: Int64 = 0
    
    mutating func update() {
        // Update metrics from system
        // This would be implemented with actual system calls
    }
}

enum SubsystemStatus {
    case normal
    case degraded
    case failing
}
