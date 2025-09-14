import Foundation
import os
import Combine

/// Comprehensive error handling and recovery service
class ErrorHandlingService {
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "ErrorHandling")
    
    // Error state publishers
    @Published private(set) var activeErrors: [ScanningError] = []
    @Published private(set) var systemStatus: SystemStatus = .normal
    @Published private(set) var recoveryInProgress = false
    
    // Recovery state tracking
    private var recoveryAttempts: [String: Int] = [:]
    private let maxRecoveryAttempts = 3
    private var recoveryQueue = OperationQueue()
    
    // Error monitorings
    private var errorMonitors: [ErrorMonitor] = []
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupErrorMonitoring()
        recoveryQueue.maxConcurrentOperationCount = 1
        recoveryQueue.qualityOfService = .userInitiated
    }
    
    /// Handle a new error occurrence
    func handleError(_ error: ScanningError) {
        logger.error("Error occurred: \(error.description) - Code: \(error.code)")
        
        // Add to active errors if not already present
        if !activeErrors.contains(where: { $0.id == error.id }) {
            activeErrors.append(error)
            
            // Update system status based on error severity
            updateSystemStatus(with: error)
            
            // Attempt recovery if appropriate
            if error.isRecoverable {
                initiateRecovery(for: error)
            }
            
            // Notify error monitors
            notifyErrorMonitors(of: error)
        }
    }
    
    /// Register a new error monitor
    func registerErrorMonitor(_ monitor: ErrorMonitor) {
        errorMonitors.append(monitor)
    }
    
    /// Clear resolved errors
    func clearResolvedErrors() {
        activeErrors.removeAll { $0.isResolved }
        updateSystemStatus()
    }
    
    /// Reset error handling system
    func reset() {
        activeErrors.removeAll()
        recoveryAttempts.removeAll()
        systemStatus = .normal
        recoveryInProgress = false
        recoveryQueue.cancelAllOperations()
    }
    
    // MARK: - Private Methods
    
    private func setupErrorMonitoring() {
        // Monitor system health
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.performHealthCheck()
            }
            .store(in: &cancellables)
    }
    
    private func updateSystemStatus(with newError: ScanningError? = nil) {
        let currentErrors = activeErrors
        
        if let critical = currentErrors.first(where: { $0.severity == .critical }) {
            systemStatus = .critical(error: critical)
        } else if currentErrors.contains(where: { $0.severity == .high }) {
            systemStatus = .degraded
        } else if currentErrors.isEmpty {
            systemStatus = .normal
        }
        
        // Use explicit String conversion to avoid ambiguity in Logger interpolation overloads
        logger.info("System status updated to: \(String(describing: self.systemStatus))")
    }

    private func initiateRecovery(for error: ScanningError) {
        guard !recoveryInProgress else {
            logger.debug("Recovery already in progress, queueing recovery for: \(error.code)")
            return
        }
        
        let attempts = recoveryAttempts[error.id] ?? 0
        guard attempts < self.maxRecoveryAttempts else {
            logger.error("Max recovery attempts reached for error: \(error.code)")
            return
        }
        
        recoveryInProgress = true
        recoveryAttempts[error.id, default: 0] += 1
        
        let operation = RecoveryOperation(error: error) { [weak self] success in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.recoveryInProgress = false
                
                if success {
                    self.handleRecoverySuccess(for: error)
                } else {
                    self.handleRecoveryFailure(for: error)
                }
            }
        }
        
        recoveryQueue.addOperation(operation)
    }
    
    private func handleRecoverySuccess(for error: ScanningError) {
        logger.info("Recovery successful for error: \(error.code)")
        
        activeErrors.removeAll { $0.id == error.id }
        recoveryAttempts.removeValue(forKey: error.id)
        updateSystemStatus()
        
        // Notify monitors of recovery
        notifyErrorMonitors(of: error, recovered: true)
    }
    
    private func handleRecoveryFailure(for error: ScanningError) {
        logger.error("Recovery failed for error: \(error.code)")
        
        if recoveryAttempts[error.id, default: 0] >= maxRecoveryAttempts {
            error.markUnrecoverable()
            logger.error("Error marked as unrecoverable after \(self.maxRecoveryAttempts) attempts")
        } else {
            // Schedule another recovery attempt with backoff
            let backoffDelay = calculateBackoffDelay(attempts: recoveryAttempts[error.id, default: 0])
            DispatchQueue.main.asyncAfter(deadline: .now() + backoffDelay) { [weak self] in
                self?.initiateRecovery(for: error)
            }
        }
    }
    
    private func calculateBackoffDelay(attempts: Int) -> TimeInterval {
        // Exponential backoff with jitter
        let baseDelay: TimeInterval = 1.0
        let maxDelay: TimeInterval = 30.0
        
        let exponentialDelay = baseDelay * pow(2.0, Double(attempts))
        let jitter = Double.random(in: 0...0.3)
        
        return min(exponentialDelay + jitter, maxDelay)
    }
    
    private func notifyErrorMonitors(of error: ScanningError, recovered: Bool = false) {
        errorMonitors.forEach { monitor in
            if recovered {
                monitor.errorRecovered(error)
            } else {
                monitor.errorOccurred(error)
            }
        }
    }
    
    private func performHealthCheck() {
        // Perform lightweight periodic checks. Defer detailed health checks to HealthMonitoringService.
        analyzeErrorPatterns()
    }
    
    private func analyzeErrorPatterns() {
        // Analyze recent errors for patterns
        let recentErrors = activeErrors.filter {
            $0.timestamp.timeIntervalSinceNow > -300 // Last 5 minutes
        }
        
        // Check for error clusters
        let errorsByType = Dictionary(grouping: recentErrors) { $0.code }
        errorsByType.forEach { (code, errors) in
            if errors.count >= 3 {
                logger.warning("Error pattern detected: \(code) occurred \(errors.count) times")
                // Could trigger additional recovery actions or notifications
            }
        }
    }
    
    // MARK: - Recovery Operation
    final class RecoveryOperation: Operation, @unchecked Sendable {
        private let error: ScanningError
        private let completion: (Bool) -> Void
        
        init(error: ScanningError, completion: @escaping (Bool) -> Void) {
            self.error = error
            self.completion = completion
            super.init()
        }
        
        override func main() {
            guard !isCancelled else { return }
            
            // Implement recovery logic based on error type
            let success = performRecovery()
            
            if !isCancelled {
                completion(success)
            }
        }
        
        private func performRecovery() -> Bool {
            // Implement specific recovery strategies based on error type
            switch error.code.components(separatedBy: "_").first {
            case "CAMERA":
                return recoverCamera()
            case "RECOGNITION":
                return recoverRecognition()
            case "SYSTEM":
                return recoverSystemResource()
            default:
                return false
            }
        }
        
        private func recoverCamera() -> Bool {
            Thread.sleep(forTimeInterval: 1.0)
            return true
        }
        
        private func recoverRecognition() -> Bool {
            Thread.sleep(forTimeInterval: 0.5)
            return true
        }
        
        private func recoverSystemResource() -> Bool {
            Thread.sleep(forTimeInterval: 1.5)
            return true
        }
    }
}

/// Error monitoring protocol
protocol ErrorMonitor {
    func errorOccurred(_ error: ScanningError)
    func errorRecovered(_ error: ScanningError)
}

/// Scanning error types
class ScanningError: Identifiable, Error {
    let id: String
    let code: String
    let description: String
    let severity: ErrorSeverity
    let timestamp: Date
    let isRecoverable: Bool
    
    private(set) var isResolved = false
    private(set) var recoveryAttempts = 0
    
    init(
        code: String,
        description: String,
        severity: ErrorSeverity,
        isRecoverable: Bool = true
    ) {
        self.id = UUID().uuidString
        self.code = code
        self.description = description
        self.severity = severity
        self.timestamp = Date()
        self.isRecoverable = isRecoverable
    }
    
    func markResolved() {
        isResolved = true
    }
    
    func markUnrecoverable() {
        isResolved = false
    }
    
    static func camera(code: String, description: String) -> ScanningError {
        ScanningError(code: "CAMERA_\(code)", description: description, severity: .high)
    }
    
    static func recognition(code: String, description: String) -> ScanningError {
        ScanningError(code: "RECOGNITION_\(code)", description: description, severity: .medium)
    }
    
    static func systemResource(code: String, description: String) -> ScanningError {
        ScanningError(code: "SYSTEM_\(code)", description: description, severity: .high)
    }
}

/// Error severity levels
enum ErrorSeverity {
    case low
    case medium
    case high
    case critical
}

/// System operational status
enum SystemStatus {
    case normal
    case degraded
    case critical(error: ScanningError)
}
