//
//  SerialScannerViewModel+PowerManagement.swift
//  AppleSerialScanner
// Performance Optimization - Power Management Integration
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - PowerManagementDelegate
extension SerialScannerViewModel: @preconcurrency PowerManagementDelegate {
    func powerManagementDidEnablePowerSaving() {
        DispatchQueue.main.async { [weak self] in
            self?.isPowerSavingModeActive = true
            self?.backgroundProcessingManager.enableThrottling()
            // Reduce frame processing rate in power saving mode
            self?.backgroundProcessingManager.setMaxProcessingRate(5) // 5 fps instead of 15
            print("Entered power saving mode - reduced processing rate to 5fps")
        }
    }
    
    func powerManagementDidDisablePowerSaving() {
        DispatchQueue.main.async { [weak self] in
            self?.isPowerSavingModeActive = false
            self?.backgroundProcessingManager.disableThrottling()
            // Restore normal frame processing rate
            self?.backgroundProcessingManager.setMaxProcessingRate(15)
            print("Exited power saving mode - restored processing rate to 15fps")
        }
    }
    
    func powerManagementDidTimeoutScanning() {
        DispatchQueue.main.async { [weak self] in
            self?.isScanning = false
            self?.backgroundProcessingManager.pauseProcessing()
            print("Scanning timeout - paused processing due to inactivity")
        }
    }
}

// MARK: - Performance Monitoring
extension SerialScannerViewModel {
    func startPerformanceMonitoring() {
        // Monitor frame processing performance every 5 seconds
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.logPerformanceMetrics()
                self.adaptProcessingBasedOnPerformance()
            }
        }
    }
    
    private func logPerformanceMetrics() {
        let stats = backgroundProcessingManager.getPerformanceStats()
        let framesProcessed = stats["framesProcessed"] as? Int ?? 0
        let framesDropped = stats["framesDropped"] as? Int ?? 0
        let avgProcessingTime = stats["avgProcessingTime"] as? Double ?? 0.0
        let queueDepth = stats["queueDepth"] as? Int ?? 0
        print("   Performance Stats:")
        print("   Frames processed: \(framesProcessed)")
        print("   Frames dropped: \(framesDropped)")
        print(String(format: "   Average processing time: %.1fms", avgProcessingTime))
        print("   Queue depth: \(queueDepth)")
        let powerStatus = isPowerSavingModeActive ? "ON" : "OFF"
        print("   Power saving: \(powerStatus)")
    }
    
    private func adaptProcessingBasedOnPerformance() {
        let stats = backgroundProcessingManager.getPerformanceStats()
        let avgProcessingTime = stats["avgProcessingTime"] as? Double ?? 0
        let queueDepth = stats["queueDepth"] as? Int ?? 0
        
        // If processing is taking too long or queue is backing up, reduce quality
        if avgProcessingTime > 100 || queueDepth > 5 {
            // Reduce processing complexity
            backgroundProcessingManager.enableFastMode()
            print(" Enabled fast mode due to performance issues")
        } else if avgProcessingTime < 50 && queueDepth < 2 {
            // We can afford higher quality processing
            backgroundProcessingManager.disableFastMode()
            print("Disabled fast mode - performance is good")
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
        let powerState = isPowerSavingModeActive ? "Active" : "Inactive"
        let lines: [String] = [
            "Performance Status:",
            "• Processing Time: \(String(format: "%.1f", avgTime))ms",
            "• Frame Drop Rate: \(String(format: "%.1f", dropRate))%",
            "• Power Saving: \(powerState)",
            "• Thermal State: \(ProcessInfo.processInfo.thermalState.description)"
        ]
        return lines.joined(separator: "\n")
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
