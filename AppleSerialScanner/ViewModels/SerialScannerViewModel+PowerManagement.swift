//
//  SerialScannerViewModel+PowerManagement.swift
//  AppleSerialScanner
// Performance Optimization - Power Management Integration
//

import Foundation
import UIKit

// MARK: - PowerManagementDelegate
extension SerialScannerViewModel: PowerManagementDelegate {
    func powerManagementDidEnablePowerSaving() {
        DispatchQueue.main.async { [weak self] in
            self?.isPowerSavingModeActive = true
            self?.backgroundProcessingManager.enableThrottling()
            // Reduce frame processing rate in power saving mode
            self?.backgroundProcessingManager.setMaxProcessingRate(5) // 5 fps instead of 15
            AppLogger.power.debug("Entered power saving mode - reduced processing rate to 5fps")
        }
    }
    
    func powerManagementDidDisablePowerSaving() {
        DispatchQueue.main.async { [weak self] in
            self?.isPowerSavingModeActive = false
            self?.backgroundProcessingManager.disableThrottling()
            // Restore normal frame processing rate
            self?.backgroundProcessingManager.setMaxProcessingRate(15)
            AppLogger.power.debug("Exited power saving mode - restored processing rate to 15fps")
        }
    }
    
    func powerManagementDidTimeoutScanning() {
        DispatchQueue.main.async { [weak self] in
            self?.isScanning = false
            self?.backgroundProcessingManager.pauseProcessing()
            AppLogger.power.debug("Scanning timeout - paused processing due to inactivity")
        }
    }
}

// MARK: - Performance Monitoring
extension SerialScannerViewModel {
    func startPerformanceMonitoring() {
        // Monitor frame processing performance every 5 seconds
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.logPerformanceMetrics()
            self?.adaptProcessingBasedOnPerformance()
        }
    }
    
    private func logPerformanceMetrics() {
        let stats = backgroundProcessingManager.getPerformanceStats()
        AppLogger.power.debug("Performance Stats - framesProcessed=\(stats["framesProcessed"] ?? 0), framesDropped=\(stats["framesDropped"] ?? 0), avgProcessingMs=\(stats["avgProcessingTime"] ?? 0), queueDepth=\(stats["queueDepth"] ?? 0), powerSaving=\(isPowerSavingModeActive ? "ON" : "OFF")")
    }
    
    private func adaptProcessingBasedOnPerformance() {
        let stats = backgroundProcessingManager.getPerformanceStats()
        let avgProcessingTime = stats["avgProcessingTime"] as? Double ?? 0
        let queueDepth = stats["queueDepth"] as? Int ?? 0
        
        // If processing is taking too long or queue is backing up, reduce quality
        if avgProcessingTime > 100 || queueDepth > 5 {
            // Reduce processing complexity
            backgroundProcessingManager.enableFastMode()
            AppLogger.power.debug("Enabled fast mode due to performance issues")
        } else if avgProcessingTime < 50 && queueDepth < 2 {
            // We can afford higher quality processing
            backgroundProcessingManager.disableFastMode()
            AppLogger.power.debug("Disabled fast mode - performance is good")
        }
    }
    
    func optimizeForCurrentConditions() {
        // Check device capabilities and adjust accordingly
        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermalState = ProcessInfo.processInfo.thermalState
        
        if isLowPowerMode || thermalState == .serious || thermalState == .critical {
            shouldEnterPowerSavingMode()
        } else {
            shouldExitPowerSavingMode()
        }
        
        // Adapt processing based on recent performance
        adaptProcessingBasedOnPerformance()
    }
    
    func shouldEnterPowerSavingMode() {
        if !isPowerSavingModeActive {
            powerManagementDidEnablePowerSaving()
        }
    }
    
    func shouldExitPowerSavingMode() {
        if isPowerSavingModeActive {
            powerManagementDidDisablePowerSaving()
        }
    }
    
    func getOptimizationStatus() -> String {
        let stats = backgroundProcessingManager.getPerformanceStats()
        let avgTime = stats["avgProcessingTime"] as? Double ?? 0
        let dropped = stats["framesDropped"] as? Int ?? 0
        let processed = stats["framesProcessed"] as? Int ?? 0
        
        let dropRate = processed > 0 ? Double(dropped) / Double(processed) * 100 : 0
        
        return """
        🚀 Performance Status:
        • Processing Time: \(String(format: "%.1f", avgTime))ms
        • Frame Drop Rate: \(String(format: "%.1f", dropRate))%
        • Power Saving: \(isPowerSavingModeActive ? "Active" : "Inactive")
        • Thermal State: \(ProcessInfo.processInfo.thermalState.description)
        """
    }
}

// MARK: - Thermal State Extension
extension ProcessInfo.ThermalState {
    var description: String {
        switch self {
        case .nominal: return "Normal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
