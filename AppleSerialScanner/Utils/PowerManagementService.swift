import Foundation
import UIKit
import AVFoundation
import Vision

/// Manages power consumption and battery optimization for extended scanning sessions
class PowerManagementService: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isLowPowerModeEnabled = false
    @Published var batteryLevel: Float = 1.0
    @Published var batteryState: UIDevice.BatteryState = .unknown
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    
    // MARK: - Power Management Settings
    private var powerSavingThreshold: Float = 0.20 // Enable power saving at 20% battery
    private var aggressivePowerSavingThreshold: Float = 0.10 // More aggressive at 10% battery
    private var scanningTimeoutInterval: TimeInterval = 120.0 // 2 minutes default timeout
    private var lowPowerTimeoutInterval: TimeInterval = 60.0 // 1 minute in low power mode
    
    // MARK: - Timers
    private var scanningTimeoutTimer: Timer?
    private var batteryMonitorTimer: Timer?
    
    // MARK: - Delegates
    weak var powerDelegate: PowerManagementDelegate?
    
    // MARK: - Initialization
    init() {
        setupBatteryMonitoring()
        setupThermalStateMonitoring()
        startBatteryMonitoring()
    }
    
    deinit {
        stopBatteryMonitoring()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Battery Monitoring Setup
    private func setupBatteryMonitoring() {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryLevelDidChange),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryStateDidChange),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateDidChange),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        #endif
    }
    
    private func setupThermalStateMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateDidChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }
    
    // MARK: - Battery Monitoring
    private func startBatteryMonitoring() {
        batteryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.updateBatteryStatus()
        }
        updateBatteryStatus()
    }
    
    private func stopBatteryMonitoring() {
        batteryMonitorTimer?.invalidate()
        batteryMonitorTimer = nil
        
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = false
        #endif
    }
    
    private func updateBatteryStatus() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            #if os(iOS)
            self.batteryLevel = UIDevice.current.batteryLevel
            self.batteryState = UIDevice.current.batteryState
            #else
            // For macOS, assume good battery status
            self.batteryLevel = 1.0
            self.batteryState = .full
            #endif
            
            self.thermalState = ProcessInfo.processInfo.thermalState
            self.evaluatePowerSavingMode()
        }
    }
    
    // MARK: - Notification Handlers
    @objc private func batteryLevelDidChange() {
        updateBatteryStatus()
    }
    
    @objc private func batteryStateDidChange() {
        updateBatteryStatus()
    }
    
    @objc private func powerStateDidChange() {
        #if os(iOS)
        DispatchQueue.main.async { [weak self] in
            self?.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            self?.evaluatePowerSavingMode()
        }
        #endif
    }
    
    @objc private func thermalStateDidChange() {
        updateBatteryStatus()
    }
    
    // MARK: - Power Saving Mode Evaluation
    private func evaluatePowerSavingMode() {
        let shouldEnablePowerSaving = shouldEnablePowerSavingMode()
        
        if shouldEnablePowerSaving && !isLowPowerModeEnabled {
            enablePowerSavingMode()
        } else if !shouldEnablePowerSaving && isLowPowerModeEnabled {
            disablePowerSavingMode()
        }
    }
    
    private func shouldEnablePowerSavingMode() -> Bool {
        // Enable power saving if:
        // 1. Battery is below threshold
        // 2. Device is in low power mode
        // 3. Thermal state is high
        return batteryLevel < powerSavingThreshold ||
               ProcessInfo.processInfo.isLowPowerModeEnabled ||
               thermalState == .serious ||
               thermalState == .critical
    }
    
    // MARK: - Power Saving Mode Control
    private func enablePowerSavingMode() {
        isLowPowerModeEnabled = true
        powerDelegate?.powerManagementDidEnablePowerSaving()
        
        // Adjust scanning timeout for power saving
        if batteryLevel < aggressivePowerSavingThreshold {
            scanningTimeoutInterval = 30.0 // Very short timeout for critically low battery
        } else {
            scanningTimeoutInterval = lowPowerTimeoutInterval
        }
        
        AppLogger.power.debug("Power saving enabled - Battery: \(Int(batteryLevel * 100))%, Thermal: \(String(describing: thermalState.rawValue))")
    }
    
    private func disablePowerSavingMode() {
        isLowPowerModeEnabled = false
        powerDelegate?.powerManagementDidDisablePowerSaving()
        
        // Restore normal scanning timeout
        scanningTimeoutInterval = 120.0
        
        AppLogger.power.debug("Power saving disabled")
    }
    
    // MARK: - Scanning Session Management
    func startScanningSession() {
        stopScanningTimeout() // Clear any existing timeout
        
        let timeoutInterval = isLowPowerModeEnabled ? lowPowerTimeoutInterval : scanningTimeoutInterval
        
        scanningTimeoutTimer = Timer.scheduledTimer(withTimeInterval: timeoutInterval, repeats: false) { [weak self] _ in
            self?.handleScanningTimeout()
        }
        
        AppLogger.power.debug("Scanning session started with \(Int(timeoutInterval))s timeout")
    }
    
    func stopScanningSession() {
        stopScanningTimeout()
        AppLogger.power.debug("Scanning session stopped")
    }
    
    private func stopScanningTimeout() {
        scanningTimeoutTimer?.invalidate()
        scanningTimeoutTimer = nil
    }
    
    private func handleScanningTimeout() {
        powerDelegate?.powerManagementDidTimeoutScanning()
        AppLogger.power.debug("Scanning session timed out")
    }
    
    // MARK: - Power Optimization Recommendations
    func getOptimizedCameraSettings() -> PowerOptimizedCameraSettings {
        if isLowPowerModeEnabled {
            return PowerOptimizedCameraSettings(
                sessionPreset: .medium, // Lower resolution to save power
                frameRate: 15, // Reduced frame rate
                enableTorch: false, // Disable torch to save battery
                processingInterval: 0.1 // Process fewer frames
            )
        } else if thermalState == .serious || thermalState == .critical {
            return PowerOptimizedCameraSettings(
                sessionPreset: .high,
                frameRate: 20, // Slightly reduced frame rate for thermal management
                enableTorch: false, // Disable torch when overheating
                processingInterval: 0.075
            )
        } else {
            return PowerOptimizedCameraSettings(
                sessionPreset: .high,
                frameRate: 30, // Full frame rate
                enableTorch: true, // Allow torch usage
                processingInterval: 0.05
            )
        }
    }
    
    func getOptimizedProcessingSettings() -> PowerOptimizedProcessingSettings {
        if isLowPowerModeEnabled {
            return PowerOptimizedProcessingSettings(
                maxConcurrentTasks: 2,
                enableSurfaceDetection: false,
                enableLightingAnalysis: false,
                enableAngleDetection: false,
                ocrAccuracyLevel: VNRequestTextRecognitionLevel.fast,
                maxFramesToProcess: 20
            )
        } else if thermalState == .serious || thermalState == .critical {
            return PowerOptimizedProcessingSettings(
                maxConcurrentTasks: 3,
                enableSurfaceDetection: false,
                enableLightingAnalysis: true,
                enableAngleDetection: false,
                ocrAccuracyLevel: VNRequestTextRecognitionLevel.fast,
                maxFramesToProcess: 40
            )
        } else {
            return PowerOptimizedProcessingSettings(
                maxConcurrentTasks: 5,
                enableSurfaceDetection: true,
                enableLightingAnalysis: true,
                enableAngleDetection: true,
                ocrAccuracyLevel: VNRequestTextRecognitionLevel.accurate,
                maxFramesToProcess: 60
            )
        }
    }
    
    // MARK: - Battery Status Information
    func getBatteryStatusDescription() -> String {
        #if os(iOS)
        let percentage = Int(batteryLevel * 100)
        let stateDescription: String
        
        switch batteryState {
        case .charging:
            stateDescription = "Charging"
        case .full:
            stateDescription = "Full"
        case .unplugged:
            stateDescription = "On Battery"
        case .unknown:
            stateDescription = "Unknown"
        @unknown default:
            stateDescription = "Unknown"
        }
        
        return "\(percentage)% - \(stateDescription)"
        #else
        return "Power OK"
        #endif
    }
    
    func getThermalStatusDescription() -> String {
        switch thermalState {
        case .nominal:
            return "Normal Temperature"
        case .fair:
            return "Warm"
        case .serious:
            return "Hot - Performance Reduced"
        case .critical:
            return "Very Hot - Emergency Mode"
        @unknown default:
            return "Unknown Temperature"
        }
    }
}

// MARK: - Power Management Delegate
protocol PowerManagementDelegate: AnyObject {
    func powerManagementDidEnablePowerSaving()
    func powerManagementDidDisablePowerSaving()
    func powerManagementDidTimeoutScanning()
}

// MARK: - Power Optimization Settings
struct PowerOptimizedCameraSettings {
    let sessionPreset: AVCaptureSession.Preset
    let frameRate: Int
    let enableTorch: Bool
    let processingInterval: TimeInterval
}

struct PowerOptimizedProcessingSettings {
    let maxConcurrentTasks: Int
    let enableSurfaceDetection: Bool
    let enableLightingAnalysis: Bool
    let enableAngleDetection: Bool
    let ocrAccuracyLevel: VNRequestTextRecognitionLevel
    let maxFramesToProcess: Int
}
