import Foundation
import AVFoundation
import UIKit
import CoreMedia
import CoreVideo

class CameraConfigurator {
    
    static func configureCameraForOptimalScanning(captureSession: AVCaptureSession, device: AVCaptureDevice?) {
        guard let device = device else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Set higher resolution for iPad
            if UIDevice.current.userInterfaceIdiom == .pad {
                // Find the highest resolution format available
                if let highResFormat = device.formats
                    .filter({ CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange })
                    .filter({ CMVideoFormatDescriptionGetDimensions($0.formatDescription).width >= 1920 })
                    .max(by: { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width }) {
                    
                    // Use high resolution format for iPad
                    device.activeFormat = highResFormat
                    
                    // Set frame rate to balance quality and performance
                    // Set frame rate to balance quality and performance
                    let frameRateRange = highResFormat.videoSupportedFrameRateRanges.first!
                    let frameRate = min(frameRateRange.maxFrameRate, 30.0)
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
                    device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
                }
            }
            
            // Optimize focus for text
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            
            // For text scanning, use auto focus range restriction to near if available
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            
            // Optimize exposure for better text readability
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            // Enable smooth autofocus for better text scanning
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            
            // Enable low light boost if available
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
            
            device.unlockForConfiguration()
        } catch {
            AppLogger.camera.error("Error configuring camera: \(error.localizedDescription)")
        }
    }
    
    static func optimizeVideoOutput(_ videoOutput: AVCaptureVideoDataOutput) {
        // Ensure we use a high-quality pixel format
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        // Process frames in real-time, dropping old frames if necessary
        videoOutput.alwaysDiscardsLateVideoFrames = true
    }
}
