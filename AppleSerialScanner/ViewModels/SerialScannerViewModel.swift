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
    @Published var zoomFactor: CGFloat = 1.0
    // Device-supported zoom bounds exposed for UI
    @Published var minSupportedZoom: CGFloat = 1.0
    @Published var maxSupportedZoom: CGFloat = 5.0
    // Smooth UI display value for zoom (interpolated to match camera ramp)
    @Published var displayedZoom: CGFloat = 1.0

    // Expose previewLayer so SwiftUI views can show the camera only inside the ROI
    @Published var previewLayer: AVCaptureVideoPreviewLayer?

    // --- New: Accessory preset manager exposed so views/services can read/update presets ---
    @Published var accessoryPresetManager = AccessoryPresetManager()

    // --- New: Lighting detection state (used by LightingIndicatorView) ---
    enum LightingCondition: Equatable {
        case optimal, bright, dim, uneven, glare, mixed, unknown

        var iconName: String {
            switch self {
            case .optimal: return "sun.max"
            case .bright: return "sun.max.fill"
            case .dim: return "cloud.moon"
            case .uneven: return "slash.circle"
            case .glare: return "sun.dust"
            case .mixed: return "circle.lefthalf.fill"
            case .unknown: return "questionmark"
            }
        }

        var description: String {
            switch self {
            case .optimal: return "Optimal"
            case .bright: return "Bright"
            case .dim: return "Dim"
            case .uneven: return "Uneven"
            case .glare: return "Glare"
            case .mixed: return "Mixed"
            case .unknown: return "Unknown"
            }
        }
    }

    @Published var detectedLightingCondition: LightingCondition = .unknown
    @Published var lightingDetectionConfidence: Float = 0.0
    @Published var isLightingDetectionEnabled: Bool = true

    // Surface detection state (added to match UI usage in SurfaceIndicatorView)
    @Published var detectedSurfaceType: SurfaceType = .unknown
    @Published var surfaceDetectionConfidence: Float = 0.0
    @Published var isSurfaceDetectionEnabled: Bool = true

    // Angle detection toggle used by UI
    @Published var isAngleDetectionEnabled: Bool = true

    // Frame limits and counters exposed to UI
    @Published var maxFrames: Int = 9999

    // MARK: - Performance Optimization
    private(set) var backgroundProcessingManager = BackgroundProcessingManager()
    let powerManagementService = PowerManagementService()
    
    // MARK: - Auto Capture Properties
    private var isAutoCapturing = false
    private var processingStartTime: Date?
    private var frameResults: [FrameResult] = []
    
    // MARK: - Service Properties
    private let backendService = BackendService()
    private let validator = SerialValidator()
    private let surfaceDetector = SurfaceDetector()
    private let lightingAnalyzer = LightingAnalyzer()
    private let angleDetector = AngleDetector()
    
    // MARK: - Enhanced Pipeline Integration
    private let scannerPipeline = SerialScannerPipeline()
    
    // Phase 0: Baseline metrics integration
    private var metricsRefreshTimer: Timer?
    
    // MARK: - Camera Integration
    private let cameraManager = CameraManager()
    private var vmCancellables = Set<AnyCancellable>()

    // MARK: - Logger
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "SerialScannerViewModel")
    
    override init() {
        super.init()
        setupCameraDelegate()
        startMetricsRefreshTimer()
        
        // Keep view model zoomFactor in sync with camera manager
        cameraManager.$zoomFactor
            .receive(on: RunLoop.main)
            .sink { [weak self] z in
                guard let self = self else { return }
                self.zoomFactor = z
                // Update smoothing target and start interpolation toward the authoritative camera value
                self.displayedZoomTarget = z
                self.startSmoothingIfNeeded()
            }
            .store(in: &vmCancellables)

        // Subscribe to device-supported zoom bounds
        cameraManager.$minSupportedZoom
            .receive(on: RunLoop.main)
            .sink { [weak self] v in
                self?.minSupportedZoom = v
            }
            .store(in: &vmCancellables)

        cameraManager.$maxSupportedZoom
            .receive(on: RunLoop.main)
            .sink { [weak self] v in
                self?.maxSupportedZoom = v
            }
            .store(in: &vmCancellables)

        // Initialize and expose the preview layer for UI preview wrappers
        if let layer = cameraManager.getPreviewLayer() {
            self.previewLayer = layer
        }

        // Keep preview layer frame in sync with camera manager preview bounds
        cameraManager.$previewBounds
            .receive(on: RunLoop.main)
            .sink { [weak self] bounds in
                guard let layer = self?.previewLayer else { return }
                // Update frame on main thread (layer is a CALayer subclass)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.frame = bounds
                CATransaction.commit()
            }
            .store(in: &vmCancellables)

        // Ensure accessory preset manager changes are observed and applied
        accessoryPresetManager.$selectedAccessoryType
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleAccessoryPresetChange()
                }
            }
            .store(in: &vmCancellables)
    }
    
    deinit {
        Task { @MainActor in
            stopMetricsRefreshTimer()
        }
        // Clean up smoothing timer
        stopSmoothingTimer()
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
    
    /// Request a zoom change from the UI (proxies to CameraManager)
    func setZoomFactor(_ factor: CGFloat) {
        // Request camera to change zoom (animated ramp on device when supported)
        cameraManager.setZoomFactor(factor, animated: true)
        // Optimistically update the view model's zoomFactor and smoothing target so the UI responds immediately.
        DispatchQueue.main.async {
            self.zoomFactor = factor
            self.displayedZoomTarget = factor
            self.startSmoothingIfNeeded()
        }
    }
    
    // Allow UI to set the smoothing target (used by Slider binding)
    func setDisplayedZoomTarget(_ factor: CGFloat) {
        DispatchQueue.main.async {
            self.displayedZoomTarget = factor
            self.startSmoothingIfNeeded()
        }
    }
    
    private func startSmoothingIfNeeded() {
        // If a timer is already running, keep it. Otherwise start one to interpolate displayedZoom.
        if smoothingTimer != nil { return }
        // Ensure displayedZoom has a sensible initial value
        if displayedZoom == 0 { displayedZoom = zoomFactor }
        smoothingTimer = Timer.scheduledTimer(withTimeInterval: smoothingFrameDuration, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            // Interpolate exponentially toward the target
            let delta = self.displayedZoomTarget - self.displayedZoom
            // If very close, snap to target and stop timer
            if abs(delta) < 0.001 {
                // Animate final snap so UI thumb doesn't jump abruptly
                DispatchQueue.main.async {
                    withAnimation(.linear(duration: self.smoothingFrameDuration * 1.5)) {
                        self.displayedZoom = self.displayedZoomTarget
                    }
                }
                self.stopSmoothingTimer()
                return
            }
            // Compute interpolated value
            let newValue = self.displayedZoom + delta * self.smoothingRate
            // Animate to the new interpolated value so Slider thumb and label animate smoothly
            DispatchQueue.main.async {
                withAnimation(.linear(duration: self.smoothingFrameDuration * 1.5)) {
                    self.displayedZoom = newValue
                }
            }
        }
        // Add to run loop common modes so it continues during UI interactions
        RunLoop.main.add(smoothingTimer!, forMode: .common)
    }

    private func stopSmoothingTimer() {
        smoothingTimer?.invalidate()
        smoothingTimer = nil
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
        
        guard status == kCFReturnSuccess, let buffer = pixelBuffer else {
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

    // Public API for the UI to submit the currently recognized/edited text
    @MainActor
    func submitRecognizedText() {
        let text = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            guidanceText = "No text to submit"
            return
        }

        // If format looks valid, submit; otherwise attempt submission and update guidance
        if isValidAppleSerialFormat(text) {
            guidanceText = "Submitting \(text)..."
            submitSerial(text)
        } else {
            guidanceText = "Text may not match expected serial format — submitting anyway..."
            submitSerial(text)
        }
    }

    // MARK: - Auto Capture Controls (exposed to UI/selector)
    @objc func startAutoCapture() {
        guard !isAutoCapturing else { return }
        isAutoCapturing = true
        logger.debug("Auto capture started")

        if !isScanning {
            startScanning()
        }
    }

    @objc func stopAutoCapture() {
        guard isAutoCapturing else { return }
        isAutoCapturing = false
        logger.debug("Auto capture stopped")
    }

    // MARK: - Validation confirmation handler used by several views
    @MainActor
    func handleValidationConfirmation(confirmed: Bool) {
        if confirmed {
            if let best = validationResult?.bestCandidate {
                submitSerial(best.candidate.text)
            } else if !recognizedText.isEmpty {
                submitSerial(recognizedText)
            } else {
                guidanceText = "Nothing to submit"
            }
        } else {
            // User cancelled; update guidance
            guidanceText = "Submission cancelled"
        }
    }

    // Apply accessory preset changes to scanner pipeline / guidance
    @MainActor
    func handleAccessoryPresetChange() {
        // Update guidance based on selected preset
        guidanceText = accessoryPresetManager.getGuidanceText()

        // Apply OCR settings to the pipeline if available (best-effort, scanner pipeline should expose configuration API)
        let settings = accessoryPresetManager.currentOCRSettings
        // Example: inform scannerPipeline or validator about allowlist/confidence threshold where APIs exist
        // scannerPipeline.applyOCRSettings(settings) // (commented; implement when pipeline supports it)

        // Adjust camera or timing heuristics if necessary
        // For now, update UI-exposed timeouts/frames via guidance text / logs
        AppLogger.ui.debug("Accessory preset changed to \(accessoryPresetManager.selectedAccessoryType.rawValue)")
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
        
        // Validate the serial using ML-backed validator
        let validation = validator.validateSerial(serial)
        let decisionLevel: ValidationDecisionLevel
        if validation.isValid {
            // Map to prior levels using combined confidence (VisionKit/conf + validator.confidence)
            let combinedConfidence = max(confidence, validation.confidence)
            decisionLevel = combinedConfidence >= 0.9 ? .ACCEPT : .BORDERLINE
        } else {
            decisionLevel = .REJECT
        }
        
        switch decisionLevel {
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
        
        logger.info("VisionKit high confidence serial processed: \(serial) -> \(decisionLevel)")
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

// Local mapping to preserve previous semantic levels
private enum ValidationDecisionLevel { case ACCEPT, BORDERLINE, REJECT }

// MARK: - Frame Result Model
struct FrameResult {
    let text: String
    let confidence: Float
    let timestamp: Date
}

extension SerialScannerViewModel {
    /// Process a CGImage through the scanner pipeline (non-async wrapper)
    func processFrame(_ cgImage: CGImage) {
        guard let buffer = createPixelBuffer(from: cgImage) else { return }

        scannerPipeline.processFrame(pixelBuffer: buffer, cameraMetadata: nil, mode: currentScanningMode) { [weak self] result in
            Task { @MainActor in
                self?.handlePipelineResult(result)
            }
        }
    }

    /// Async-optimized processing entry used by delegates that run on a Task context.
    @MainActor
    func processFrameOptimized(_ cgImage: CGImage) async {
        guard let buffer = createPixelBuffer(from: cgImage) else { return }

        // Throttle using BackgroundProcessingManager
        guard backgroundProcessingManager.shouldProcessFrame() else { return }
        backgroundProcessingManager.beginFrameProcessing()

        scannerPipeline.processFrame(pixelBuffer: buffer, cameraMetadata: nil, mode: currentScanningMode) { [weak self] result in
            Task { @MainActor in
                self?.handlePipelineResult(result)
                self?.backgroundProcessingManager.endFrameProcessing()
            }
        }
    }
}
