import AVFoundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import CoreImage
import os.log

/// Advanced camera control service with intelligent auto-adjustment
/// and optimal configuration for serial number scanning
class CameraControlService {
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "CameraControl")
    
    // Camera state tracking
    private var currentZoomFactor: CGFloat = 1.0
    private var lastFocusPoint: CGPoint?
    private var lastStabilityScore: Float = 0.0
    private var isAutoAdjusting = false
    
    // Configuration thresholds
    private let maxZoomFactor: CGFloat = 5.0
    private let minZoomFactor: CGFloat = 1.0
    private let optimalBrightnessRange: ClosedRange<Float> = 0.4...0.7
    private let stabilityThreshold: Float = 0.8
    
    // Auto-adjustment settings
    private var autoAdjustmentEnabled = true
    private var lastAdjustmentTime: TimeInterval = 0
    private let adjustmentCooldown: TimeInterval = 0.5
    
    /// Configure device with optimal settings for serial scanning
    func configureDevice(_ device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        // Configure focus system
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
            #if os(iOS) || targetEnvironment(macCatalyst)
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            #endif
        }

        // Configure exposure
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }

        // iOS-only features (optical stabilization / HDR) are intentionally skipped on macOS builds.
        // Leave best-effort hooks here if needed for iOS builds, but avoid referencing unavailable
        // members on macOS to keep the file parseable across platforms.
        #if os(iOS) || targetEnvironment(macCatalyst)
        // On iOS/macCatalyst we could enable optical stabilization or HDR if available.
        // This implementation avoids compile-time references on macOS.
        #endif

        logger.info("Camera configured with optimal settings for serial scanning")
    }

    /// Analyze and adjust camera settings based on frame quality
    func analyzeAndAdjust(device: AVCaptureDevice, frameQuality: FrameQualityMetrics) {
        guard autoAdjustmentEnabled else { return }

        let currentTime = CACurrentMediaTime()
        guard currentTime - lastAdjustmentTime >= adjustmentCooldown else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            // Adjust zoom based on text size and clarity
            let currentZoom: CGFloat
            #if os(iOS) || targetEnvironment(macCatalyst)
            currentZoom = device.videoZoomFactor
            #else
            currentZoom = currentZoomFactor
            #endif

            let optimalZoom = calculateOptimalZoom(
                currentZoom: currentZoom,
                textSize: frameQuality.averageTextSize,
                clarity: frameQuality.clarityScore
            )

            // Smoothly adjust zoom
            let newZoom = max(minZoomFactor, min(optimalZoom, maxZoomFactor))
            #if os(iOS) || targetEnvironment(macCatalyst)
            device.videoZoomFactor = newZoom
            #else
            currentZoomFactor = newZoom
            #endif

            // Adjust focus if text is blurry
            if frameQuality.clarityScore < 0.7 {
                #if os(iOS) || targetEnvironment(macCatalyst)
                if let focusPoint = frameQuality.primaryTextLocation,
                   device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = focusPoint
                    device.focusMode = .autoFocus
                }
                #endif
            }

            // Adjust exposure for optimal text contrast
            #if os(iOS) || targetEnvironment(macCatalyst)
            if !optimalBrightnessRange.contains(frameQuality.brightnessScore),
               device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            }
            #endif

            lastAdjustmentTime = currentTime
            logger.debug("Camera adjusted - Zoom: \(newZoom), Clarity: \(frameQuality.clarityScore)")

        } catch {
            logger.error("Failed to adjust camera: \(error.localizedDescription)")
        }
    }

    /// Reset camera to default settings
    func resetCamera(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            #if os(iOS) || targetEnvironment(macCatalyst)
            device.videoZoomFactor = 1.0
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            #else
            // macOS: best-effort resets (not all properties available)
            #endif

            currentZoomFactor = 1.0
            lastFocusPoint = nil

            logger.info("Camera reset to default settings")
        } catch {
            logger.error("Failed to reset camera: \(error.localizedDescription)")
        }
    }
    
    /// Enable or disable automatic camera adjustments
    func setAutoAdjustment(enabled: Bool) {
        autoAdjustmentEnabled = enabled
        logger.info("Auto-adjustment \(enabled ? "enabled" : "disabled")")
    }
    
    // MARK: - Private Methods
    
    private func calculateOptimalZoom(currentZoom: CGFloat, textSize: CGFloat, clarity: Float) -> CGFloat {
        let targetTextSize: CGFloat = 40.0 // Optimal text size in points
        let zoomAdjustment = targetTextSize / max(textSize, 1.0)
        
        // Apply smaller adjustments when text is clear
        let adjustmentFactor = clarity > 0.8 ? 0.1 : 0.2
        
        return currentZoom * (1.0 + (zoomAdjustment - 1.0) * adjustmentFactor)
    }
}

/// Metrics for frame quality analysis
struct FrameQualityMetrics {
    let clarityScore: Float
    let brightnessScore: Float
    let averageTextSize: CGFloat
    let primaryTextLocation: CGPoint?
    let stabilityScore: Float
    
    init(
        clarityScore: Float,
        brightnessScore: Float,
        averageTextSize: CGFloat,
        primaryTextLocation: CGPoint? = nil,
        stabilityScore: Float
    ) {
        self.clarityScore = clarityScore
        self.brightnessScore = brightnessScore
        self.averageTextSize = averageTextSize
        self.primaryTextLocation = primaryTextLocation
        self.stabilityScore = stabilityScore
    }
}
