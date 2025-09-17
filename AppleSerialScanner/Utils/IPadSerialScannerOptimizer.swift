import Foundation
import Vision
import AVFoundation
import CoreMedia
import CoreVideo
import CoreGraphics

/// Specialized optimizations for iPad serial scanning
class IPadSerialScannerOptimizer {
    
    /// Configure iPad-specific scanning parameters
    /// - Parameters:
    ///   - captureSession: The AVCaptureSession to configure
    ///   - textRecognitionRequest: The Vision text recognition request to optimize
    static func optimizeForIPad(
        captureSession: AVCaptureSession,
        textRecognitionRequest: VNRecognizeTextRequest
    ) {
        // 1. Set optimal resolution for iPad
        if let connection = captureSession.connections.first,
           connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }
        
        // 2. Set rectangular ROI optimized for serial numbers (wider than tall)
        let iPadRoiWidth: CGFloat = 0.8  // Wide ROI for iPad
        let iPadRoiHeight: CGFloat = 0.2 // Shorter height (4:1 aspect ratio)
        let roiRect = CGRect(
            x: (1.0 - iPadRoiWidth) / 2.0,
            y: (1.0 - iPadRoiHeight) / 2.0,
            width: iPadRoiWidth,
            height: iPadRoiHeight
        )
        textRecognitionRequest.regionOfInterest = roiRect
        
        // 3. Set iPad-specific text recognition parameters
        textRecognitionRequest.minimumTextHeight = 0.03 // Better for iPad's higher resolution
        textRecognitionRequest.recognitionLevel = .accurate
        
        // 4. Disable language correction for serial numbers
        textRecognitionRequest.usesLanguageCorrection = false
        
        // 5. Add common Apple serial number patterns
        textRecognitionRequest.customWords = [
            // Common prefixes for Apple serial numbers
            "C02", "FVFG", "FVFC", "FVFD", "FVFF", "FVFH", "FVFJ", "FVFK", "FVFL", "FVFM", "FVFN", "FVFP",
            "FVFQ", "FVFR", "FVFT", "FVFV", "FVFW", "FVFY", "FVG0", "FVG1", "FVG2", "FVG3", "FVG4", "C32",
            "C39", "C3G", "C3T", "C3V", "C3X", "C4W", "F9F", "F9G", "F9H", "F9J", "F9K", "F9L", "F9M", "F9N",
            "DKQ", "DKR", "DKT", "DKV", "DKW", "DKX", "DKY", "DL0", "DL1", "DL2", "DL3", "DL4", "G0L", "G0M",
            "G0N", "G0P"
        ]
    }
    
    /// Get iPad-specific guidance text
    /// - Returns: A string with guidance text optimized for iPad's larger screen
    static func getIPadGuidanceText() -> String {
        return "Position serial number in the rectangular area"
    }
    
    /// Optimize the camera configuration for iPad
    /// - Parameter device: The camera device to configure
    static func optimizeCameraForIPad(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            
            // Find the highest resolution format available
            if let highResFormat = device.formats
                .filter({ CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange })
                .filter({ CMVideoFormatDescriptionGetDimensions($0.formatDescription).width >= 1920 })
                .max(by: { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width }) {
                
                // Use high resolution format for iPad
                device.activeFormat = highResFormat
                
                // Set frame rate to balance quality and performance
                let frameRateRange = highResFormat.videoSupportedFrameRateRanges.first!
                let frameRate = min(frameRateRange.maxFrameRate, 30.0)
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
            }
            
            // Enable smooth autofocus for better text scanning
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            
            // For text scanning, use auto focus range restriction to near if available
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            
            device.unlockForConfiguration()
        } catch {
            AppLogger.camera.error("Error configuring camera for iPad: \(error.localizedDescription)")
        }
    }
}
