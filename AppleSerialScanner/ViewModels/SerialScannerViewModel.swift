import SwiftUI
import Vision
import VisionKit
@preconcurrency import AVFoundation
import Combine
@preconcurrency  import CoreImage
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import os.log

// MARK: - SerialScannerViewModel

@MainActor
class SerialScannerViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isProcessing = false
    @Published var guidanceText = "Position the serial number within the frame"
    @Published var showingResultAlert = false
    @Published var resultMessage = ""
    @Published var bestConfidence: Float = 0.0
    @Published var processedFrames = 0
    @Published var isFlashOn = false
    @Published var validationResult: ValidationResult?
    @Published var showValidationAlert = false
    @Published var validationAlertMessage: String = ""
    @Published var showingPresetSelector = false
    @Published var recognizedText = ""
    @Published var isPowerSavingModeActive = false
    @Published var isScanning = false
    @Published var currentScanningMode: ScanningMode = .screen
    
    // Phase 0: Baseline metrics properties
    @Published var currentBaselineMetrics: BaselineMetricsCollector.BaselineReport?
    @Published var showBaselineMetrics = false
    
    // MARK: - Performance Optimization
    private(set) var backgroundProcessingManager = BackgroundProcessingManager()
    let powerManagementService = PowerManagementService()
    
    // MARK: - Auto Capture Properties
    private var isAutoCapturing = false
    private var processingStartTime: Date?
    private var frameResults: [FrameResult] = []
    
    // MARK: - Service Properties
    private let backendService = BackendService()
    private let validator = AppleSerialValidator()
    private let surfaceDetector = SurfaceDetector()
    private let lightingAnalyzer = LightingAnalyzer()
    private let angleDetector = AngleDetector()
    
    // MARK: - Enhanced Pipeline Integration
    private let scannerPipeline = SerialScannerPipeline()
    
    // Phase 0: Baseline metrics integration
    private var metricsRefreshTimer: Timer?
    
    // MARK: - Camera Integration
    private let cameraManager = CameraManager()
    
    // MARK: - Logger
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "SerialScannerViewModel")
    
    override init() {
        super.init()
        setupCameraDelegate()
        startMetricsRefreshTimer()
    }
    
    deinit {
        Task { @MainActor in
            stopMetricsRefreshTimer()
        }
    }
    
    private func setupCameraDelegate() {
        cameraManager.frameDelegate = self
    }
    
    // MARK: - Phase 0: Baseline Metrics Methods
    
    func refreshBaselineMetrics() {
        currentBaselineMetrics = scannerPipeline.getBaselineReport()
    }
    
    func exportBaselineMetrics() -> Data? {
        return scannerPipeline.exportMetricsData()
    }
    
    func resetBaselineMetrics() {
        // Reset the pipeline which will reset the metrics
        scannerPipeline.reset()
        currentBaselineMetrics = nil
    }
    
    func toggleBaselineMetrics() {
        showBaselineMetrics.toggle()
    }
    
    private func startMetricsRefreshTimer() {
        metricsRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshBaselineMetrics()
            }
        }
    }
    
    private func stopMetricsRefreshTimer() {
        metricsRefreshTimer?.invalidate()
        metricsRefreshTimer = nil
    }
    
    // MARK: - Camera Control Methods
    
    func startScanning() {
        isScanning = true
        cameraManager.startSession()
    }
    
    func stopScanning() {
        isScanning = false
        cameraManager.stopSession()
    }
    
    // MARK: - Helper Methods for Phase 0
    
    /// Creates a CVPixelBuffer from a CGImage for the enhanced pipeline
    private func createPixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            image.width,
            image.height,
            kCVPixelFormatType_32ARGB,
            attrs,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: pixelData,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return buffer
    }
    
    /// Validates if a string matches Apple serial number format
    private func isValidAppleSerialFormat(_ text: String) -> Bool {
        // Basic length check (Apple serials are typically 10-12 characters)
        guard text.count >= 8 && text.count <= 15 else { return false }
        
        // Must be alphanumeric only
        let alphanumericSet = CharacterSet.alphanumerics
        guard text.unicodeScalars.allSatisfy({ alphanumericSet.contains($0) }) else { return false }
        
        // Apple serial patterns
        let serialPatterns = [
            "^[A-Z]{1,3}[A-Z0-9]{8,10}$",     // 1-3 letters + 8-10 alphanumeric
            "^[A-Z0-9]{10,12}$",              // All alphanumeric, 10-12 chars
            "^[0-9A-Z]{10}$",                 // Exactly 10 characters
            "^[A-Z]{2}[0-9]{8}$"              // 2 letters + 8 numbers (older format)
        ]
        
        for pattern in serialPatterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        return false
    }
    
    private func submitSerial(_ serial: String) {
        // Implementation for submitting the serial
        Task {
            do {
                let submission = SerialSubmission(
                    serialNumber: serial,
                    confidence: bestConfidence,
                    deviceType: "iOS",
                    source: "camera"
                )
                let result = try await backendService.submitSerial(submission)
                await MainActor.run {
                    self.resultMessage = "Serial submitted successfully: \(result.message)"
                    self.showingResultAlert = true
                }
            } catch {
                await MainActor.run {
                    self.resultMessage = "Failed to submit serial: \(error.localizedDescription)"
                    self.showingResultAlert = true
                }
            }
        }
    }
}

// MARK: - Phase 0: Enhanced Camera Frame Delegate with Metrics Collection

extension SerialScannerViewModel: CameraFrameDelegate {
    nonisolated func didCaptureFrame(pixelBuffer: CVPixelBuffer, cameraMetadata: [String: Any]) {
        Task { @MainActor in
            guard isScanning else { return }
            
            processedFrames += 1
            
            // Process frame through enhanced pipeline with metadata
            scannerPipeline.processFrame(
                pixelBuffer: pixelBuffer,
                cameraMetadata: cameraMetadata,
                mode: currentScanningMode
            ) { [weak self] result in
                Task { @MainActor in
                    self?.handlePipelineResult(result)
                }
            }
        }
    }
    
    private func handlePipelineResult(_ result: PipelineResult) {
        switch result {
        case .success(let data):
            // Extract the validation result from the pipeline data
            let validation = data.validation
            if let bestCandidate = validation.bestCandidate {
                recognizedText = bestCandidate.candidate.text
                bestConfidence = bestCandidate.compositeScore
                
                // Update guidance based on stability state
                updateGuidanceText(for: data.stability.isStable, confidence: bestCandidate.compositeScore)
                
                // Auto-submit if confidence is high and stable
                if bestCandidate.compositeScore > 0.85 && data.stability.isStable {
                    submitSerial(bestCandidate.candidate.text)
                }
            }
            
        case .noScreenDetected(let processingTime):
            guidanceText = "Point camera at a screen or device"
            
        case .busy:
            // Frame was skipped due to processing load
            break
            
        case .error(let error, let processingTime):
            guidanceText = "Processing error - try adjusting lighting"
            
        @unknown default:
            break
        }
    }
    
    private func updateGuidanceText(for isStable: Bool, confidence: Float) {
        if isStable {
            guidanceText = confidence > 0.7 ? "Serial number confirmed!" : "Low quality - adjust lighting or distance"
        } else {
            guidanceText = "Hold steady - detecting text..."
        }
    }
}

// MARK: - Phase 1: VisionKit Integration Support

extension SerialScannerViewModel {
    /// Handles high confidence serial detection from VisionKit
    func handleHighConfidenceSerial(_ serial: String, confidence: Float) {
        // Update recognition state
        recognizedText = serial
        bestConfidence = confidence
        
        // Validate the serial using existing validation logic
        let appleValidationResult = validator.validate_with_corrections(serial, confidence)
        
        switch appleValidationResult.level {
        case .ACCEPT:
            // Auto-submit high confidence serials
            submitSerial(serial)
            guidanceText = "Serial confirmed - submitting..."
            
        case .BORDERLINE:
            // Show confirmation for borderline serials
            validationAlertMessage = "Serial found with \(Int(confidence * 100))% confidence. Submit \(serial)?"
            showValidationAlert = true
            guidanceText = "Serial detected - confirm to submit"
            
        case .REJECT:
            // Continue scanning for rejected serials
            guidanceText = "Invalid format detected - continue scanning"
        }
        
        logger.info("VisionKit high confidence serial processed: \(serial) -> \(appleValidationResult.level)")
    }
    
    /// Checks if VisionKit is available on the current device
    static func isVisionKitAvailable() -> Bool {
        if #available(iOS 16.0, *) {
            return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        }
        return false
    }
    
    /// Gets the recommended scanner implementation based on device capabilities
    func getRecommendedScannerType() -> ScannerType {
        if Self.isVisionKitAvailable() {
            return .visionKit
        } else {
            return .legacy
        }
    }
}

// MARK: - Frame Result Model
struct FrameResult {
    let text: String
    let confidence: Float
    let timestamp: Date
}
