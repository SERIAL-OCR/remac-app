import Foundation
import Combine
import os

/// Coordinates recovery actions across different subsystems
class RecoveryCoordinator {
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "Recovery")
    private let errorHandler: ErrorHandlingService
    
    // Recovery state tracking
    private var activeRecoveries: [String: RecoveryAction] = [:]
    private var subsystemStatus: [SubsystemType: SubsystemHealth] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // Subsystem managers
    private let cameraManager: CameraManager
    private let serialValidator: SerialValidator
    private let consensusEngine: MultiFrameConsensusEngine
    
    init(
        errorHandler: ErrorHandlingService,
        cameraManager: CameraManager,
        serialValidator: SerialValidator,
        consensusEngine: MultiFrameConsensusEngine
    ) {
        self.errorHandler = errorHandler
        self.cameraManager = cameraManager
        self.serialValidator = serialValidator
        self.consensusEngine = consensusEngine
        
        setupSubsystemMonitoring()
    }
    
    /// Initiate recovery for a subsystem
    func initiateRecovery(for subsystem: SubsystemType, error: ScanningError) -> AnyPublisher<RecoveryResult, Never> {
        logger.info("Initiating recovery for \(subsystem.rawValue)")
        
        // Create recovery subject
        let recoverySubject = PassthroughSubject<RecoveryResult, Never>()
        
        // Create and store recovery action
        let action = RecoveryAction(
            id: UUID().uuidString,
            subsystem: subsystem,
            error: error,
            status: .preparing,
            subject: recoverySubject
        )
        
        activeRecoveries[action.id] = action
        
        // Start recovery process
        performRecovery(action)
        
        return recoverySubject.eraseToAnyPublisher()
    }
    
    /// Reset all subsystems
    func resetAllSubsystems() {
        logger.info("Resetting all subsystems")
        
        // Cancel any active recoveries
        activeRecoveries.forEach { $0.value.subject.send(.cancelled) }
        activeRecoveries.removeAll()
        
        // Reset subsystems
        cameraManager.stopSession()
        consensusEngine.reset()
        
        // Reset subsystem health status
        subsystemStatus.removeAll()
        
        // Restart camera session
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.cameraManager.startSession()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupSubsystemMonitoring() {
        // Monitor camera health
        cameraManager.$isSessionRunning
            .sink { [weak self] isRunning in
                self?.updateSubsystemHealth(.camera, isRunning ? .healthy : .failing)
            }
            .store(in: &cancellables)
        
        // Monitor system resources
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkSystemResources()
            }
            .store(in: &cancellables)
    }
    
    private func performRecovery(_ action: RecoveryAction) {
        logger.info("Performing recovery for \(action.subsystem.rawValue)")
        
        // Update action status
        action.status = .inProgress
        
        switch action.subsystem {
        case .camera:
            recoverCamera(action)
        case .recognition:
            recoverRecognition(action)
        case .validation:
            recoverValidation(action)
        case .consensus:
            recoverConsensus(action)
        }
    }
    
    private func recoverCamera(_ action: RecoveryAction) {
        // Stop camera session
        cameraManager.stopSession()
        
        // Wait briefly before restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            
            // Attempt to restart camera
            self.cameraManager.startSession()
            
            // Check if recovery was successful
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.cameraManager.isSessionRunning {
                    self.completeRecovery(action, success: true)
                } else {
                    self.completeRecovery(action, success: false)
                }
            }
        }
    }
    
    private func recoverRecognition(_ action: RecoveryAction) {
        // Reset recognition pipeline
        consensusEngine.reset()
        
        // Recovery is considered successful if reset completes
        completeRecovery(action, success: true)
    }
    
    private func recoverValidation(_ action: RecoveryAction) {
        // Reset validation state
        serialValidator.reset()
        
        // Recovery is considered successful if reset completes
        completeRecovery(action, success: true)
    }
    
    private func recoverConsensus(_ action: RecoveryAction) {
        // Reset consensus engine
        consensusEngine.reset()
        
        // Recovery is considered successful if reset completes
        completeRecovery(action, success: true)
    }
    
    private func completeRecovery(_ action: RecoveryAction, success: Bool) {
        logger.info("Recovery \(success ? "succeeded" : "failed") for \(action.subsystem.rawValue)")
        
        let result: RecoveryResult = success ? .succeeded : .failed
        action.subject.send(result)
        action.subject.send(completion: .finished)
        
        activeRecoveries.removeValue(forKey: action.id)
        
        // Update subsystem health
        updateSubsystemHealth(action.subsystem, success ? .healthy : .failing)
    }
    
    private func updateSubsystemHealth(_ subsystem: SubsystemType, _ health: SubsystemHealth) {
        subsystemStatus[subsystem] = health
        
        // Check if system is degraded
        let isSystemDegraded = subsystemStatus.values.contains(.failing)
        if isSystemDegraded {
            errorHandler.handleError(
                .systemResource(
                    code: "DEGRADED_PERFORMANCE",
                    description: "One or more subsystems are not functioning optimally"
                )
            )
        }
    }
    
    private func checkSystemResources() {
        // Capture current system metrics using the monitor helper
        let monitor = SystemHealthMonitor.captureCurrentMetrics()
        
        if monitor.memoryUsage > 0.9 || monitor.cpuUsage > 0.8 {
            // Trigger system resource recovery
            let error = ScanningError.systemResource(
                code: "RESOURCE_CRITICAL",
                description: "System resources critically low"
            )
            
            // Consume the returned publisher to avoid unused-result warnings
            initiateRecovery(for: .camera, error: error)
                .sink { _ in }
                .store(in: &cancellables)
        }
    }
}

/// Types of subsystems that can be recovered
enum SubsystemType: String {
    case camera = "Camera"
    case recognition = "Recognition"
    case validation = "Validation"
    case consensus = "Consensus"
}

/// Health status of a subsystem
enum SubsystemHealth {
    case healthy
    case degraded
    case failing
}

/// Result of a recovery attempt
enum RecoveryResult {
    case succeeded
    case failed
    case cancelled
}

/// Status of a recovery action
enum RecoveryState {
    case preparing
    case inProgress
    case completed
    case failed
}

/// Represents an active recovery action
class RecoveryAction {
    let id: String
    let subsystem: SubsystemType
    let error: ScanningError
    var status: RecoveryState
    let subject: PassthroughSubject<RecoveryResult, Never>
    
    init(
        id: String,
        subsystem: SubsystemType,
        error: ScanningError,
        status: RecoveryState,
        subject: PassthroughSubject<RecoveryResult, Never>
    ) {
        self.id = id
        self.subsystem = subsystem
        self.error = error
        self.status = status
        self.subject = subject
    }
}
