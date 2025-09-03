import SwiftUI
import Vision
import VisionKit
import AVFoundation
import Combine
@preconcurrency import CoreImage

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
    @Published var validationAlertMessage = ""
    
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
    
    // MARK: - Batch Processing Property
    lazy var batchProcessor = BatchProcessor(scannerViewModel: self)

    // MARK: - Analytics Properties
    private let analyticsService = AnalyticsService()
    private var currentSessionId: UUID?
    private var sessionStartTime: Date?
    private var surfaceDetectionEvents: [SurfaceDetectionEvent] = []
    private var lightingConditionEvents: [LightingConditionEvent] = []
    private var angleCorrectionEvents: [AngleCorrectionEvent] = []

    // MARK: - Surface Detection Properties
    @Published var detectedSurfaceType: SurfaceType = .unknown
    @Published var surfaceDetectionConfidence: Float = 0.0
    @Published var isSurfaceDetectionEnabled = true

    // MARK: - Lighting Detection Properties
    @Published var detectedLightingCondition: LightingCondition = .unknown
    @Published var lightingDetectionConfidence: Float = 0.0
    @Published var isLightingDetectionEnabled = true

    // MARK: - Angle Detection Properties
    @Published var detectedTextOrientation: TextOrientation?
    @Published var isAngleDetectionEnabled = true
    @Published var angleCorrectionApplied = false
    
    // MARK: - Camera Properties
    var previewLayer: AVCaptureVideoPreviewLayer?
    private var captureSession: AVCaptureSession?
    private var videoOutput = AVCaptureVideoDataOutput()
    private var photoOutput = AVCapturePhotoOutput()

    

    // MARK: - Analytics Methods
    private func startAnalyticsSession() {
        currentSessionId = UUID()
        sessionStartTime = Date()
        surfaceDetectionEvents.removeAll()
        lightingConditionEvents.removeAll()
        angleCorrectionEvents.removeAll()

        if let sessionId = currentSessionId {
            analyticsService.recordScanEvent(.scanStarted(sessionId: sessionId))
        }
    }

    private func recordFrameProcessing(processingTime: TimeInterval, confidence: Float) {
        guard let sessionId = currentSessionId else { return }
        analyticsService.recordScanEvent(.frameProcessed(
            sessionId: sessionId,
            processingTime: processingTime,
            confidence: confidence
        ))
    }

    private func recordSurfaceDetection(surfaceType: String, confidence: Float) {
        guard let sessionId = currentSessionId else { return }

        let event = SurfaceDetectionEvent(
            timestamp: Date(),
            surfaceType: surfaceType,
            confidence: confidence,
            changedFrom: surfaceDetectionEvents.last?.surfaceType
        )
        surfaceDetectionEvents.append(event)

        analyticsService.recordScanEvent(.surfaceDetected(
            sessionId: sessionId,
            surfaceType: surfaceType,
            confidence: confidence
        ))
    }

    private func recordLightingChange(lightingCondition: String, confidence: Float) {
        guard let sessionId = currentSessionId else { return }

        let event = LightingConditionEvent(
            timestamp: Date(),
            lightingCondition: lightingCondition,
            confidence: confidence,
            changedFrom: lightingConditionEvents.last?.lightingCondition
        )
        lightingConditionEvents.append(event)

        analyticsService.recordScanEvent(.lightingChanged(
            sessionId: sessionId,
            lightingCondition: lightingCondition,
            confidence: confidence
        ))
    }

    private func recordAngleCorrection(angle: Double, confidence: Float) {
        guard let sessionId = currentSessionId else { return }

        let event = AngleCorrectionEvent(
            timestamp: Date(),
            angleDegrees: angle,
            correctionApplied: true,
            confidence: confidence
        )
        angleCorrectionEvents.append(event)

        analyticsService.recordScanEvent(.angleCorrected(
            sessionId: sessionId,
            angle: angle,
            confidence: confidence
        ))
    }

    private func completeAnalyticsSession(success: Bool, finalConfidence: Float, error: String? = nil) {
        guard let sessionId = currentSessionId,
              let startTime = sessionStartTime else { return }

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        if success {
            analyticsService.recordScanEvent(.scanCompleted(
                sessionId: sessionId,
                success: true,
                finalConfidence: finalConfidence
            ))
        } else {
            analyticsService.recordScanEvent(.scanFailed(
                sessionId: sessionId,
                error: error ?? "Unknown error"
            ))
        }

        // Create comprehensive analytics data
        let analyticsData = createAnalyticsData(
            sessionId: sessionId,
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            success: success,
            finalConfidence: finalConfidence
        )

        analyticsService.recordScanSession(analyticsData)

        // Reset session
        currentSessionId = nil
        sessionStartTime = nil
    }

    private func createAnalyticsData(sessionId: UUID, startTime: Date, endTime: Date, duration: TimeInterval, success: Bool, finalConfidence: Float) -> AnalyticsData {
        let deviceInfo = DeviceInfo()

        let scanSession = ScanSessionAnalytics(
            sessionId: sessionId,
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            totalFrames: processedFrames,
            successfulFrames: success ? processedFrames : 0,
            bestResult: createScanResult(finalConfidence),
            surfaceDetectionResults: surfaceDetectionEvents,
            lightingConditionChanges: lightingConditionEvents,
            angleCorrectionEvents: angleCorrectionEvents
        )

        let performanceMetrics = PerformanceMetrics(
            averageProcessingTime: duration / Double(max(processedFrames, 1)),
            minProcessingTime: 0.0, // Would need to track per frame
            maxProcessingTime: duration,
            framesPerSecond: Double(processedFrames) / duration,
            memoryUsage: MemoryUsage(peakUsage: 0, averageUsage: 0, currentUsage: 0, availableMemory: 0),
            cpuUsage: CPUUsage(averageUsage: 0.0, peakUsage: 0.0, coreCount: 0),
            gpuUsage: nil
        )

        let accuracyMetrics = AccuracyMetrics(
            initialConfidence: 0.0, // Would need to track initial confidence
            finalConfidence: finalConfidence,
            confidenceImprovement: finalConfidence,
            validationPassed: success,
            errorType: success ? nil : "validation_failed",
            retryCount: 0,
            surfaceAdaptationApplied: isSurfaceDetectionEnabled,
            lightingAdaptationApplied: isLightingDetectionEnabled,
            angleCorrectionApplied: isAngleDetectionEnabled
        )

        let systemHealth = SystemHealthMonitor.captureCurrentMetrics().toSystemHealthMetrics()

        return AnalyticsData(
            deviceInfo: deviceInfo,
            scanSession: scanSession,
            performanceMetrics: performanceMetrics,
            accuracyMetrics: accuracyMetrics,
            systemHealth: systemHealth
        )
    }

    private func createScanResult(_ confidence: Float) -> ScanResult? {
        guard let validationResult = validationResult else { return nil }

        return ScanResult(
            serialNumber: validationResult.serial,
            confidence: confidence,
            processingTime: 0.0, // Would need to track actual processing time
            surfaceType: detectedSurfaceType.rawValue,
            lightingCondition: detectedLightingCondition.rawValue,
            angleCorrection: angleCorrectionApplied,
            frameCount: processedFrames,
            timestamp: Date(),
            validationStatus: validationResult.level == .ACCEPT ? "valid" : "invalid"
        )
    }
    
    // MARK: - Vision Properties
    private var textRecognitionRequest: VNRecognizeTextRequest?
    private var processingQueue = DispatchQueue(label: "com.appleserial.processing", qos: .userInitiated)
    private var roiRectNormalized: CGRect = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
    
    // MARK: - Configuration
    var maxFrames: Int { accessoryPresetManager.getMaxFrames() }
    var processingWindow: TimeInterval { accessoryPresetManager.getProcessingWindow() }
    let minConfidence: Float = 0.7
    let deviceType: String
    
    override init() {
        #if os(iOS)
        self.deviceType = UIDevice.current.model
        #else
        self.deviceType = "Mac"
        #endif

        // All stored properties are initialized at this point; call super.init() before using self
        super.init()

        // Set up accessory preset manager first
        _ = accessoryPresetManager // Initialize the manager

        setupVision()
        setupCamera()

        // Apply initial accessory preset settings
        applyAccessoryPresetSettings()

        // Observe accessory preset changes
        setupAccessoryPresetObserver()
    }

    private func setupAccessoryPresetObserver() {
        // This will be called when accessory preset changes
        // Since AccessoryPresetManager is an ObservableObject, we can observe its changes
        // For now, we'll handle preset changes in the UI when needed
    }

    func handleAccessoryPresetChange() {
        applyAccessoryPresetSettings()

        // Reset surface detection state when preset changes
        detectedSurfaceType = .unknown
        surfaceDetectionConfidence = 0.0

        // Update guidance text
        updateGuidanceText(accessoryPresetManager.getGuidanceText())
    }
    
    // Accessory preset manager
    let accessoryPresetManager = AccessoryPresetManager()
    
    // MARK: - Frame Processing
    // make internal so delegate extensions in a separate file can call it
    func processFrame(_ image: CGImage) {
        guard isAutoCapturing,
              let processingStartTime = processingStartTime,
              Date().timeIntervalSince(processingStartTime) < processingWindow,
              processedFrames < maxFrames else {
            if isAutoCapturing {
                stopAutoCapture()
            }
            return
        }

        processedFrames += 1

        // Convert CGImage to CIImage for surface detection
        let ciImage = CIImage(cgImage: image)

        // Perform surface detection if enabled (async to avoid blocking main thread)
        if isSurfaceDetectionEnabled && processedFrames <= 3 {
            // Only detect surface on first few frames to avoid performance impact
            detectSurfaceAsync(in: ciImage)
        }

        // Perform lighting analysis if enabled
        if isLightingDetectionEnabled && processedFrames <= 3 {
            // Analyze lighting conditions for adaptive processing
            analyzeLightingAsync(in: ciImage)
        }

        // Perform angle detection if enabled
        if isAngleDetectionEnabled && processedFrames <= 3 {
            // Detect text orientation for angle correction
            detectAngleAsync(in: ciImage)
        }

        // Apply surface-adaptive OCR settings
        updateOCRSettingsForSurface()

        guard let textRecognitionRequest = textRecognitionRequest else { return }

        textRecognitionRequest.regionOfInterest = roiRectNormalized
        let handler = VNImageRequestHandler(cgImage: image, orientation: currentCGImageOrientation(), options: [:])

        do {
            try handler.perform([textRecognitionRequest])
        } catch {
            print("Vision processing error: \(error)")
        }
    }
    
    // MARK: - Vision Setup
    private func setupVision() {
        textRecognitionRequest = VNRecognizeTextRequest { [weak self] request, error in
            self?.handleTextRecognition(request: request, error: error)
        }

        // Apply initial accessory preset settings
        let settings = accessoryPresetManager.currentOCRSettings
        textRecognitionRequest?.recognitionLevel = settings.recognitionLevel
        textRecognitionRequest?.usesLanguageCorrection = true
        textRecognitionRequest?.recognitionLanguages = ["en-US"]
        textRecognitionRequest?.minimumTextHeight = settings.minimumTextHeight
        textRecognitionRequest?.regionOfInterest = roiRectNormalized

        // Set up allowlist if specified
        if let allowlist = settings.allowlist {
            textRecognitionRequest?.customWords = Array(allowlist).map { String($0) }
        }
    }

    // MARK: - Accessory Preset Settings
    private func applyAccessoryPresetSettings() {
        let settings = accessoryPresetManager.currentOCRSettings

        // Update Vision request settings
        textRecognitionRequest?.recognitionLevel = settings.recognitionLevel
        textRecognitionRequest?.minimumTextHeight = settings.minimumTextHeight

        // Update ROI based on accessory settings
        let roiSize = settings.roiSize
        roiRectNormalized = CGRect(
            x: (1.0 - roiSize.width) / 2.0,
            y: (1.0 - roiSize.height) / 2.0,
            width: roiSize.width,
            height: roiSize.height
        )
        textRecognitionRequest?.regionOfInterest = roiRectNormalized

        // Update allowlist if specified
        if let allowlist = settings.allowlist {
            textRecognitionRequest?.customWords = Array(allowlist).map { String($0) }
        }

        // Update guidance text
        updateGuidanceText(accessoryPresetManager.getGuidanceText())
    }
    
    private func getMinimumTextHeight() -> Float {
        return accessoryPresetManager.currentOCRSettings.minimumTextHeight
    }
    
    // MARK: - Camera Setup
    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high
        
        guard let captureSession = captureSession else { return }
        
        #if os(iOS)
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return
        }
        #else
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else {
            return
        }
        #endif
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            
            photoOutput = AVCapturePhotoOutput()
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }
            
            // Setup preview layer
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer?.videoGravity = .resizeAspectFill
            
        } catch {
            print("Camera setup error: \(error)")
        }
    }
    
    // MARK: - Camera Control
    func startScanning() {
        // Start analytics session
        startAnalyticsSession()

        // Reset scanning state
        isProcessing = true
        processedFrames = 0
        bestConfidence = 0.0
        guidanceText = "Scanning for serial number..."
        updateGuidanceText(accessoryPresetManager.getGuidanceText())

        // Reset detection states
        detectedSurfaceType = .unknown
        surfaceDetectionConfidence = 0.0
        detectedLightingCondition = .unknown
        lightingDetectionConfidence = 0.0
        detectedTextOrientation = nil
        angleCorrectionApplied = false

        Task { [weak self] in
            await MainActor.run {
                self?.captureSession?.startRunning()
            }
        }
    }
    
    func stopScanning() {
        // Complete analytics session if one is active
        if bestConfidence > 0 {
            completeAnalyticsSession(success: (validationResult?.level == .ACCEPT), finalConfidence: bestConfidence)
        }

        // Reset scanning state
        isProcessing = false

        Task { [weak self] in
            await MainActor.run {
                self?.captureSession?.stopRunning()
            }
        }
    }
    
    func manualCapture() {
        guard !isProcessing else { return }
        
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func toggleFlash() {
        #if os(iOS)
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return
        }
        
        do {
            try device.lockForConfiguration()
            if device.hasTorch {
                if isFlashOn {
                    device.torchMode = .off
                } else {
                    device.torchMode = .on
                }
                isFlashOn.toggle()
            }
            device.unlockForConfiguration()
        } catch {
            print("Flash toggle error: \(error)")
        }
        #else
        isFlashOn = false
        #endif
    }
    
    // MARK: - Auto Capture
    private func startAutoCapture() {
        isAutoCapturing = true
        processingStartTime = Date()
        frameResults.removeAll()
        processedFrames = 0
        bestConfidence = 0.0

        // Reset surface detection for new scan
        detectedSurfaceType = .unknown
        surfaceDetectionConfidence = 0.0

        updateGuidanceText(getPresetGuidanceText())
    }
    
    private func getPresetGuidanceText() -> String {
        return accessoryPresetManager.getGuidanceText()
    }
    
    private func stopAutoCapture() {
        isAutoCapturing = false
        processBestResult()
    }
    
    // MARK: - Text Recognition Handler
    private func handleTextRecognition(request: VNRequest, error: Error?) {
        let processingStartTime = Date()

        guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
            print("Text recognition error: \(error?.localizedDescription ?? "Unknown error")")
            recordFrameProcessing(processingTime: Date().timeIntervalSince(processingStartTime), confidence: 0.0)
            return
        }

        var bestConfidenceInFrame: Float = 0.0

        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }

            let text = topCandidate.string.uppercased()
            let confidence = topCandidate.confidence

            if isValidAppleSerialFormat(text) {
                let frameResult = FrameResult(
                    text: text,
                    confidence: confidence,
                    timestamp: Date()
                )
                frameResults.append(frameResult)

                if confidence > bestConfidence {
                    bestConfidence = confidence
                }

                if confidence > bestConfidenceInFrame {
                    bestConfidenceInFrame = confidence
                }

                // Early stop if we have high confidence
                if confidence >= 0.9 {
                    let processingTime = Date().timeIntervalSince(processingStartTime)
                    recordFrameProcessing(processingTime: processingTime, confidence: confidence)
                    stopAutoCapture()
                    return
                }
            }
        }

        // Record frame processing analytics
        let processingTime = Date().timeIntervalSince(processingStartTime)
        recordFrameProcessing(processingTime: processingTime, confidence: bestConfidenceInFrame)
    }
    
    // MARK: - Best Result Processing
    private func processBestResult() {
        guard let bestResult = frameResults.max(by: { $0.confidence < $1.confidence }) else {
            updateGuidanceText("No serial number detected. Try again.")
            return
        }
        
        // Use client-side validation
        let validationResult = validator.validate_with_corrections(bestResult.text, bestResult.confidence)
        
        switch validationResult.level {
        case .ACCEPT:
            submitSerial(validationResult.serial, validationResult.confidence)
        case .BORDERLINE:
            self.validationResult = validationResult
            validationAlertMessage = "Borderline confidence (\(Int(validationResult.confidence * 100))%). Submit anyway?"
            showValidationAlert = true
        case .REJECT:
            updateGuidanceText("Invalid serial detected. Try again.")
        }
    }
    
    // MARK: - Validation Confirmation
    func handleValidationConfirmation(confirmed: Bool) {
        guard let validationResult = validationResult else { return }
        
        if confirmed {
            submitSerial(validationResult.serial, validationResult.confidence)
        }
        
        self.validationResult = nil
        showValidationAlert = false
    }
    
    // MARK: - Backend Submission
    private func submitSerial(_ serial: String, _ confidence: Float) {
        Task {
            do {
                let submission = SerialSubmission(
                    serial: serial,
                    confidence: confidence,
                    device_type: deviceType,
                    source: PlatformDetector.current == .iOS ? "ios" : "mac"
                )

                let response = try await backendService.submitSerial(submission)

                await MainActor.run {
                    // response.message is non-optional in SerialResponse, prefer serial_id then message
                    resultMessage = "Serial submitted: \(response.serial_id ?? response.message)"
                    showingResultAlert = true
                    updateGuidanceText("Serial submitted successfully!")
                }
            } catch {
                await MainActor.run {
                    resultMessage = "Submission failed: \(error.localizedDescription)"
                    showingResultAlert = true
                    updateGuidanceText("Submission failed. Try again.")
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func updateGuidanceText(_ text: String) {
        guidanceText = text
    }
    
    private func isValidAppleSerialFormat(_ text: String) -> Bool {
        let pattern = accessoryPresetManager.getSerialValidationPattern()
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex?.firstMatch(in: text, range: range) != nil
    }
    
    // MARK: - Orientation Helpers
    private func currentCGImageOrientation() -> CGImagePropertyOrientation {
        if let connection = videoOutput.connection(with: .video) {
            #if os(iOS)
            switch connection.videoOrientation {
            case .portrait:
                return .right
            case .portraitUpsideDown:
                return .left
            case .landscapeRight:
                return .down
            case .landscapeLeft:
                return .up
            @unknown default:
                break
            }
            #endif
        }

        #if os(iOS)
        switch UIDevice.current.orientation {
        case .portrait:
            return .right
        case .portraitUpsideDown:
            return .left
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        default:
            return .right
        }
        #else
        return .right
        #endif
    }
    
    // MARK: - Surface Detection
    private func detectSurface(in image: CIImage) {
        surfaceDetector.detectSurface(in: image) { [weak self] result in
            guard let self = self else { return }

            // Update detected surface type and confidence
            self.detectedSurfaceType = result.surfaceType
            self.surfaceDetectionConfidence = result.confidence

            // Record surface detection event for analytics
            self.recordSurfaceDetection(
                surfaceType: result.surfaceType.rawValue,
                confidence: result.confidence
            )

            // Update guidance text with surface info
            self.updateGuidanceTextWithSurfaceInfo()

            // Log surface detection for debugging
            print("Surface detected: \(result.surfaceType.description) (confidence: \(Int(result.confidence * 100))%)")
        }
    }

    private func detectSurfaceAsync(in image: CIImage) {
        surfaceDetector.detectSurface(in: image) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                // Update detected surface type and confidence
                self.detectedSurfaceType = result.surfaceType
                self.surfaceDetectionConfidence = result.confidence

                // Update guidance text with surface info
                self.updateGuidanceTextWithSurfaceInfo()

                // Log surface detection for debugging
                print("Surface detected: \(result.surfaceType.description) (confidence: \(Int(result.confidence * 100))%)")
            }
        }
    }

    private func analyzeLightingAsync(in image: CIImage) {
        // Run lighting analysis on main actor to avoid Sendable capture issues
        let illuminationProfile = lightingAnalyzer.analyzeIllumination(in: image)
        let lightingCondition = lightingAnalyzer.classifyLightingCondition(illuminationProfile)

        // Update UI on main actor
        detectedLightingCondition = lightingCondition
        lightingDetectionConfidence = illuminationProfile.averageBrightness
        updateGuidanceTextWithLightingInfo()
        print("Lighting detected: \(lightingCondition.description) (brightness: \(Int(illuminationProfile.averageBrightness * 100))%)")
    }

    private func detectAngleAsync(in image: CIImage) {
        // Run angle detection on main actor to avoid Sendable capture issues
        let textOrientation = angleDetector.detectTextOrientation(in: image)

        detectedTextOrientation = textOrientation
        updateGuidanceTextWithAngleInfo()
        if textOrientation.confidence > 0.5 {
            print("Angle detected: \(Int(textOrientation.rotationAngle))° (confidence: \(Int(textOrientation.confidence * 100))%)")
        }
    }

    // MARK: - Surface-Adaptive OCR Settings
    private func updateOCRSettingsForSurface() {
        // Combine surface detection with accessory preset settings
        let accessorySettings = accessoryPresetManager.currentOCRSettings

        if isSurfaceDetectionEnabled && detectedSurfaceType != .unknown {
            let surfaceSettings = OCRSettings.settingsFor(surface: detectedSurfaceType)

            // Prefer accurate if either setting requests it, otherwise use fast
            if accessorySettings.recognitionLevel == .accurate || surfaceSettings.recognitionLevel == .accurate {
                textRecognitionRequest?.recognitionLevel = .accurate
            } else {
                textRecognitionRequest?.recognitionLevel = .fast
            }
            textRecognitionRequest?.minimumTextHeight = max(accessorySettings.minimumTextHeight, surfaceSettings.minimumTextHeight)
        } else {
            // Use accessory preset settings only
            textRecognitionRequest?.recognitionLevel = accessorySettings.recognitionLevel
            textRecognitionRequest?.minimumTextHeight = accessorySettings.minimumTextHeight
        }

        // Update ROI based on accessory settings
        let roiSize = accessorySettings.roiSize
        roiRectNormalized = CGRect(
            x: (1.0 - roiSize.width) / 2.0,
            y: (1.0 - roiSize.height) / 2.0,
            width: roiSize.width,
            height: roiSize.height
        )
        textRecognitionRequest?.regionOfInterest = roiRectNormalized
    }

    // MARK: - Surface-Aware Guidance
    private func updateGuidanceTextWithSurfaceInfo() {
        var guidance = getPresetGuidanceText()

        if detectedSurfaceType != .unknown && surfaceDetectionConfidence > 0.6 {
            let surfaceInfo = "Detected: \(detectedSurfaceType.description)"
            guidance += "\n\(surfaceInfo)"

            // Add surface-specific guidance
            switch detectedSurfaceType {
            case .metal:
                guidance += "\n💡 Metal surface - Hold steady for engraved text"
            case .plastic:
                guidance += "\n💡 Plastic surface - Good lighting helps"
            case .glass:
                guidance += "\n💡 Glass surface - Reduce glare if possible"
            case .screen:
                guidance += "\n💡 Screen detected - Ensure display is bright"
            case .paper:
                guidance += "\n💡 Paper label - Keep text in focus"
            case .unknown:
                break
            @unknown default:
                break
            }
        }

        updateGuidanceText(guidance)
    }

    // Provide lighting guidance text
    private func updateGuidanceTextWithLightingInfo() {
        var guidance = getPresetGuidanceText()

        if detectedLightingCondition != .unknown && lightingDetectionConfidence > 0.01 {
            let lightingInfo = "Lighting: \(detectedLightingCondition.description)"
            guidance += "\n\(lightingInfo)"

            switch detectedLightingCondition {
            case .bright:
                guidance += "\n💡 Lighting is good. Ensure even illumination."
            case .dim:
                guidance += "\n💡 Low light detected - increase lighting or enable flash."
            case .mixed:
                guidance += "\n💡 Mixed lighting - try to reduce strong shadows or reflections."
            default:
                break
            }
        }

        updateGuidanceText(guidance)
    }

    // Provide angle guidance text
    private func updateGuidanceTextWithAngleInfo() {
        var guidance = getPresetGuidanceText()

        if let orientation = detectedTextOrientation {
            let angleInfo = "Rotate: \(Int(orientation.rotationAngle))° (confidence: \(Int(orientation.confidence * 100))%)"
            guidance += "\n\(angleInfo)"

            if orientation.confidence > 0.5 {
                guidance += "\n🔧 Try rotating the device slightly to improve alignment."
            }
        }

        updateGuidanceText(guidance)
    }

    // MARK: - Surface Detection Controls
    func toggleSurfaceDetection() {
        isSurfaceDetectionEnabled.toggle()
        if !isSurfaceDetectionEnabled {
            detectedSurfaceType = .unknown
            surfaceDetectionConfidence = 0.0
        }
    }

    func toggleLightingDetection() {
        isLightingDetectionEnabled.toggle()
        if !isLightingDetectionEnabled {
            detectedLightingCondition = .unknown
            lightingDetectionConfidence = 0.0
        }
    }

    func toggleAngleDetection() {
        isAngleDetectionEnabled.toggle()
        if !isAngleDetectionEnabled {
            detectedTextOrientation = nil
            angleCorrectionApplied = false
        }
    }

    // MARK: - ROI Updates from UI
    func updateRegionOfInterest(from rectInView: CGRect, in viewBounds: CGRect) {
        guard viewBounds.width > 0, viewBounds.height > 0 else { return }

        let x = rectInView.origin.x / viewBounds.width
        let yTop = rectInView.origin.y / viewBounds.height
        let width = rectInView.width / viewBounds.width
        let height = rectInView.height / viewBounds.height
        let y = 1.0 - yTop - height
        let normalized = CGRect(x: x, y: y, width: width, height: height)

        // Constrain ROI to accessory preset limits
        let accessorySettings = accessoryPresetManager.currentOCRSettings
        let constrainedRect = normalized.intersection(CGRect(
            x: (1.0 - accessorySettings.roiSize.width) / 2.0,
            y: (1.0 - accessorySettings.roiSize.height) / 2.0,
            width: accessorySettings.roiSize.width,
            height: accessorySettings.roiSize.height
        ))

        roiRectNormalized = constrainedRect
        textRecognitionRequest?.regionOfInterest = constrainedRect
        textRecognitionRequest?.minimumTextHeight = getMinimumTextHeight()
    }
}

// MARK: - Frame Result Model
struct FrameResult {
    let text: String
    let confidence: Float
    let timestamp: Date
}

// Delegate methods moved to DelegateExtensions.swift (nonisolated implementations)
