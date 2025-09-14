import AVFoundation
import Combine
import os
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// Frame delegate protocol expected by ViewModel and pipeline
protocol CameraFrameDelegate: AnyObject {
    func didCaptureFrame(pixelBuffer: CVPixelBuffer, cameraMetadata: [String: Any])
}

// Enhanced CameraManager with comprehensive baseline metrics collection
class CameraManager: NSObject, ObservableObject, ErrorMonitor {
    @Published var isAuthorized = false
    @Published var error: String?
    @Published var previewBounds: CGRect = .zero
    @Published var isSessionRunning = false
    
    private let session = AVCaptureSession()
    private var videoOutput = AVCaptureVideoDataOutput()
    private var photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    // Camera metadata tracking for baseline metrics
    private var currentDevice: AVCaptureDevice?
    private var frameMetadataQueue = DispatchQueue(label: "camera.metadata", qos: .utility)
    
    // Frame processing delegate
    weak var frameDelegate: CameraFrameDelegate?
    
    // Camera control and quality analysis
    private let cameraControl = CameraControlService()
    private let qualityAnalyzer = FrameQualityAnalyzer()
    
    // Frame quality tracking
    @Published var currentFrameQuality: FrameQualityMetrics?
    @Published var isFrameStable: Bool = false
    @Published var frameQualityGuidance: String?
    
    // Auto-adjustment state
    @Published var isAutoAdjustEnabled: Bool = true {
        didSet {
            cameraControl.setAutoAdjustment(enabled: isAutoAdjustEnabled)
        }
    }
    
    // Error handling and recovery
    private let errorHandler: ErrorHandlingService = ErrorHandlingService()
    private let recoveryCoordinator: RecoveryCoordinator
    
    // Session health monitoring
    private var frameDropCount = 0
    private var lastFrameTime: TimeInterval = 0
    private let frameDropThreshold = 10
    private let frameTimeoutThreshold: TimeInterval = 1.0
    
    private var cancellables = Set<AnyCancellable>()

    // Phase 7: Error handling and recovery services
    private let healthMonitoring: HealthMonitoringService
    private let diagnostics: DiagnosticsService
    private let recoveryManager: SerialScannerRecoveryManager
    
    private let logger = Logger(subsystem: "com.appleserialscanner.camera", category: "CameraManager")
    
    override init() {
        // Initialize Phase 7 services
        self.healthMonitoring = HealthMonitoringService()
        self.diagnostics = DiagnosticsService(
            healthMonitoring: healthMonitoring,
            errorHandler: errorHandler
        )
        self.recoveryManager = SerialScannerRecoveryManager(
            diagnostics: diagnostics,
            healthMonitoring: healthMonitoring,
            errorHandler: errorHandler
        )
        
        super.init()
        
        setupErrorHandling()
        setupHealthMonitoring()
        checkAuthorization()
    }
    
    private func setupErrorHandling() {
        // Monitor frame drops
        errorHandler.registerErrorMonitor(self)
        
        // Monitor session interruptions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruption),
            name: .AVCaptureSessionWasInterrupted,
            object: session
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionInterruptionEnded),
            name: .AVCaptureSessionInterruptionEnded,
            object: session
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionRuntimeError),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )
    }
    
    private func setupHealthMonitoring() {
        // Monitor system health
        healthMonitoring.$systemHealth
            .sink { [weak self] health in
                self?.handleHealthUpdate(health)
            }
            .store(in: &cancellables)
        
        // Start diagnostics collection
        diagnostics.startDiagnostics()
    }
    
    private func handleHealthUpdate(_ health: SystemHealthMetrics) {
        // React to health changes using available SystemHealthMetrics fields
        // If storage available is very low or system warnings accumulate, surface an error
        if health.storageAvailable < 50_000_000 || health.systemWarnings > 5 {
            let error = ScanningError.systemResource(
                code: "RESOURCE_WARNING",
                description: "System resources critically low"
            )
            handleError(error)
        }
    }
    
    private func handleError(_ error: ScanningError) {
        errorHandler.handleError(error)
        
        // Start recovery if needed
        if error.requiresImmediateRecovery {
            recoveryManager.handlePipelineFailure(error)
                .sink { [weak self] status in
                    if status == .failed {
                        // If recovery failed, attempt system reset
                        self?.performFullSystemReset()
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    private func performFullSystemReset() {
        logger.warning("Performing full system reset")
        
        // Stop current operations
        stopSession()
        
        // Reset all subsystems
        recoveryManager.reset()
        diagnostics.stopDiagnostics()
        
        // Clear error state
        errorHandler.clearResolvedErrors()
        
        // Restart with fresh configuration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.startSession()
            self?.diagnostics.startDiagnostics()
        }
    }
    
    override func willChangeValue(forKey key: String) {
        super.willChangeValue(forKey: key)
    }
    
    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupSession()
                    } else {
                        self?.error = "Camera access denied"
                    }
                }
            }
        case .denied, .restricted:
            isAuthorized = false
            error = "Camera access is required for scanning serial numbers. Please enable in Settings."
        @unknown default:
            isAuthorized = false
            error = "Unknown camera authorization status"
        }
    }
    
    /// Phase 0: Enhanced camera setup with metadata collection
    private func setupSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        // Configure device with optimal settings
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            error = "No camera device available"
            return
        }
        
        do {
            try cameraControl.configureDevice(device)
            currentDevice = device
            
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            configureVideoOutput()
            configurePhotoOutput()
            
            // Start session on background thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
                DispatchQueue.main.async {
                    self?.isSessionRunning = true
                }
            }
            
        } catch {
            self.error = "Failed to configure camera: \(error.localizedDescription)"
            logger.error("Camera setup failed: \(error.localizedDescription)")
        }
    }
    
    // Enhanced frame processing with quality analysis
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        do {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                throw ScanningError.camera(
                    code: "INVALID_BUFFER",
                    description: "Invalid sample buffer"
                )
            }
            
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            
            // Analyze frame quality
            let qualityMetrics = qualityAnalyzer.analyzeFrame(ciImage)
            
            // Log diagnostics
            diagnostics.logDiagnostic(DiagnosticEntry(
                type: .camera,
                message: "Frame processed",
                metadata: [
                    "quality": qualityMetrics.clarityScore,
                    "stability": qualityMetrics.stabilityScore
                ]
            ))
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.currentFrameQuality = qualityMetrics
                self.isFrameStable = qualityMetrics.stabilityScore > 0.8
                
                // Update guidance based on quality metrics
                self.updateFrameQualityGuidance(metrics: qualityMetrics)
                
                // Adjust camera if needed
                if let device = self.currentDevice {
                    self.cameraControl.analyzeAndAdjust(device: device, frameQuality: qualityMetrics)
                }
            }
            
            // Forward frame to delegate for processing (pixel buffer + metadata)
            let metadata = extractCameraMetadata(from: sampleBuffer)
            frameDelegate?.didCaptureFrame(pixelBuffer: pixelBuffer, cameraMetadata: metadata)
            
        } catch {
            handleError(error as? ScanningError ?? .camera(
                code: "PROCESS_ERROR",
                description: error.localizedDescription
            ))
        }
    }
    
    /// Phase 0: Configure camera settings optimized for text scanning with metrics tracking
    private func configureCameraForTextScanning(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            
            // Focus settings for text scanning
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            
            // Exposure settings for text clarity
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            // White balance for consistent text recognition
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            // Enable video stabilization for clearer text
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
                
                // Set proper orientation
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            
            device.unlockForConfiguration()
        } catch {
            DispatchQueue.main.async {
                self.error = "Failed to configure camera: \(error.localizedDescription)"
            }
        }
    }
    
    /// Phase 0: Extract comprehensive camera metadata for baseline metrics
    private func extractCameraMetadata(from sampleBuffer: CMSampleBuffer) -> [String: Any] {
        var metadata: [String: Any] = [:]
        
        // Extract timestamp
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        metadata["timestamp"] = CMTimeGetSeconds(timestamp)
        
        // Extract camera settings if available
        if let device = currentDevice {
            do {
                try device.lockForConfiguration()
                
                // Exposure settings
                metadata["exposureDuration"] = CMTimeGetSeconds(device.exposureDuration)
                metadata["iso"] = device.iso
                metadata["exposureTargetBias"] = device.exposureTargetBias
                
                // Focus settings
                metadata["focusMode"] = device.focusMode.rawValue
                metadata["lensPosition"] = device.lensPosition
                
                // White balance
                metadata["whiteBalanceMode"] = device.whiteBalanceMode.rawValue
                if device.whiteBalanceMode == .locked {
                    let gains = device.deviceWhiteBalanceGains
                    metadata["whiteBalanceGains"] = [
                        "red": gains.redGain,
                        "green": gains.greenGain,
                        "blue": gains.blueGain
                    ]
                }
                
                device.unlockForConfiguration()
            } catch {
                // Continue without detailed camera settings
            }
        }
        
        // Extract frame format information
        if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
            metadata["frameWidth"] = dimensions.width
            metadata["frameHeight"] = dimensions.height
            
            let codecType = CMFormatDescriptionGetMediaSubType(formatDescription)
            metadata["codecType"] = codecType
        }
        
        return metadata
    }
    
    // MARK: - Video/Photo Output Configuration
    private func configureVideoOutput() {
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        let queue = DispatchQueue(label: "com.appleserialscanner.camera.frames", qos: .userInitiated)
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
    }
    
    private func configurePhotoOutput() {
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
    }
    
    func startSession() {
        guard !session.isRunning else {
            print("Camera session already running")
            return
        }
        
        print("Starting camera session...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            
            DispatchQueue.main.async {
                self?.isSessionRunning = self?.session.isRunning ?? false
                print("Camera session running: \(self?.isSessionRunning ?? false)")
            }
        }
    }
    
    func stopSession() {
        guard session.isRunning else {
            print("Camera session already stopped")
            return
        }
        
        print("Stopping camera session...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
            
            DispatchQueue.main.async {
                self?.isSessionRunning = false
                print("Camera session stopped")
            }
        }
    }
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        guard previewLayer == nil else { return previewLayer }
        
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.needsDisplayOnBoundsChange = true
        
        previewLayer = layer
        return layer
    }
    
    func updatePreviewLayerBounds(_ bounds: CGRect) {
        guard bounds.width > 0 && bounds.height > 0 else {
            print("Invalid preview bounds: \(bounds)")
            return
        }
        
        previewBounds = bounds
        previewLayer?.frame = bounds
        
        print("Updated preview layer bounds: \(bounds)")
    }
    
    func capturePhoto(delegate: AVCapturePhotoCaptureDelegate) {
        guard session.isRunning else {
            print("Cannot capture photo - session not running")
            return
        }
        
        var settings = AVCapturePhotoSettings()
        
        // Configure photo settings for text capture
        if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        }
        
        // Enable flash if available and needed
        if photoOutput.supportedFlashModes.contains(.auto) {
            settings.flashMode = .auto
        }
        
        photoOutput.capturePhoto(with: settings, delegate: delegate)
        print("Photo capture initiated")
    }
    
    // MARK: - Focus and Exposure Control
    
    func focusAt(point: CGPoint) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return
        }
        
        do {
            try device.lockForConfiguration()
            
            if device.isFocusModeSupported(.autoFocus) && device.isFocusPointOfInterestSupported {
                device.focusMode = .autoFocus
                device.focusPointOfInterest = point
            }
            
            if device.isExposureModeSupported(.autoExpose) && device.isExposurePointOfInterestSupported {
                device.exposureMode = .autoExpose
                device.exposurePointOfInterest = point
            }
            
            device.unlockForConfiguration()
            print("Focus/exposure set to point: \(point)")
        } catch {
            print("Failed to set focus: \(error.localizedDescription)")
        }
    }
    
    // MARK: - ErrorMonitor conformance
    func errorOccurred(_ error: ScanningError) {
        logger.warning("Error occurred: \(error.code) - \(error.description)")
    }
    
    func errorRecovered(_ error: ScanningError) {
        logger.info("Error recovered: \(error.code)")
    }
    
    // MARK: - Session interruption handlers
    @objc private func handleSessionInterruption(_ notification: Notification) {
        logger.warning("Camera session was interrupted: \(notification)")
        DispatchQueue.main.async {
            self.isSessionRunning = false
        }
    }
    
    @objc private func handleSessionInterruptionEnded(_ notification: Notification) {
        logger.info("Camera session interruption ended: \(notification)")
    }
    
    @objc private func handleSessionRuntimeError(_ notification: Notification) {
        logger.error("Camera session runtime error: \(notification)")
    }
    
    // MARK: - Helpers
    private func updateFrameQualityGuidance(metrics: FrameQualityMetrics) {
         // Provide basic guidance mapping for metrics
         if metrics.stabilityScore < 0.5 {
             frameQualityGuidance = "Hold device steady"
         } else if metrics.clarityScore < 0.6 {
             frameQualityGuidance = "Move closer"
         } else if metrics.brightnessScore < 0.4 {
             frameQualityGuidance = "Enable torch or move to brighter area"
         } else {
             frameQualityGuidance = nil
         }
     }
}
