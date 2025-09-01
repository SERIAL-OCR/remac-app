import SwiftUI
import Vision
import VisionKit
import AVFoundation
import Combine
import CoreImage

@MainActor
class SerialScannerViewModel: ObservableObject {
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

        analyticsService.recordScanEvent(.scanStarted(sessionId: currentSessionId!))
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

        let systemHealth = SystemHealthMetrics()

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
            serialNumber: validationResult.serialNumber,
            confidence: confidence,
            processingTime: 0.0, // Would need to track actual processing time
            surfaceType: detectedSurfaceType.rawValue,
            lightingCondition: detectedLightingCondition.rawValue,
            angleCorrection: angleCorrectionApplied,
            frameCount: processedFrames,
            timestamp: Date(),
            validationStatus: validationResult.isValid ? "valid" : "invalid"
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
    
    init() {
        #if os(iOS)
        self.deviceType = UIDevice.current.model
        #else
        self.deviceType = "Mac"
        #endif

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
    private var frameResults: [FrameResult] = []
    private var processingStartTime: Date?
    private var isAutoCapturing = false
    
    // MARK: - Backend Integration
    private let backendService = BackendService()
    private let validator = AppleSerialValidator()
    private let surfaceDetector = SurfaceDetector()
    private let lightingAnalyzer = LightingAnalyzer()
    private let angleDetector = AngleDetector()

    // MARK: - Batch Processing
    private(set) lazy var batchProcessor: BatchProcessor = {
        BatchProcessor(scannerViewModel: self)
    }()

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

        processingQueue.async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }
    
    func stopScanning() {
        // Complete analytics session if one is active
        if let confidence = bestConfidence > 0 ? bestConfidence : nil {
            completeAnalyticsSession(success: validationResult?.isValid ?? false, finalConfidence: confidence)
        }

        // Reset scanning state
        isProcessing = false

        processingQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
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
    
    // MARK: - Frame Processing
    private func processFrame(_ image: CGImage) {
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
    
    // MARK: - Text Recognition Handler
    private func handleTextRecognition(request: VNRequest, error: Error?) {
        let processingStartTime = Date()

        guard error == nil else {
            print("Text recognition error: \(error!)")
            // Record failed frame processing
            recordFrameProcessing(processingTime: Date().timeIntervalSince(processingStartTime), confidence: 0.0)
            return
        }

        guard let observations = request.results as? [VNRecognizedTextObservation] else {
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
        guard !frameResults.isEmpty else {
            updateGuidanceText("No serial number detected. Try again.")
            return
        }
        
        let bestResult = frameResults.max { $0.confidence < $1.confidence }!
        
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
                    resultMessage = "Serial submitted: \(response.serial)"
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
        // Perform lighting analysis on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let illuminationProfile = self.lightingAnalyzer.analyzeIllumination(in: image)
            let lightingCondition = self.lightingAnalyzer.classifyLightingCondition(illuminationProfile)

            DispatchQueue.main.async {
                // Update detected lighting condition and confidence
                self.detectedLightingCondition = lightingCondition
                self.lightingDetectionConfidence = illuminationProfile.averageBrightness

                // Update guidance text with lighting info
                self.updateGuidanceTextWithLightingInfo()

                // Log lighting analysis for debugging
                print("Lighting detected: \(lightingCondition.description) (brightness: \(Int(illuminationProfile.averageBrightness * 100))%)")
            }
        }
    }

    private func detectAngleAsync(in image: CIImage) {
        // Perform angle detection on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let textOrientation = self.angleDetector.detectTextOrientation(in: image)

            DispatchQueue.main.async {
                // Update detected text orientation
                self.detectedTextOrientation = textOrientation

                // Update guidance text with angle info
                self.updateGuidanceTextWithAngleInfo()

                // Log angle detection for debugging
                if textOrientation.confidence > 0.5 {
                    print("Angle detected: \(Int(textOrientation.rotationAngle))° (confidence: \(Int(textOrientation.confidence * 100))%)")
                }
            }
        }
    }

    // MARK: - Guidance Text Updates

    private func updateGuidanceTextWithLightingInfo() {
        guard isLightingDetectionEnabled else { return }

        let lightingGuidance = getLightingGuidanceText()
        let surfaceGuidance = getSurfaceGuidanceText()
        let angleGuidance = getAngleGuidanceText()

        var components: [String] = []

        if detectedSurfaceType != .unknown {
            components.append("Surface: \(detectedSurfaceType.description)")
        }
        if detectedLightingCondition != .unknown {
            components.append("Lighting: \(detectedLightingCondition.description)")
        }
        if let orientation = detectedTextOrientation, orientation.confidence > 0.5 {
            components.append("Angle: \(Int(orientation.rotationAngle))°")
        }

        let header = components.isEmpty ? "" : components.joined(separator: " | ")
        let guidance = [lightingGuidance, angleGuidance].filter { !$0.isEmpty }.joined(separator: " ")

        if !header.isEmpty {
            guidanceText = "\(header)\n\(guidance)"
        } else {
            guidanceText = guidance
        }
    }

    private func updateGuidanceTextWithAngleInfo() {
        updateGuidanceTextWithLightingInfo() // Consolidated method
    }

    private func getLightingGuidanceText() -> String {
        switch detectedLightingCondition {
        case .optimal:
            return "Optimal lighting detected. Position the serial number within the frame."
        case .bright:
            return "Bright light detected. Try to reduce direct light for better results."
        case .dim:
            return "Low light detected. Ensure adequate lighting for best results."
        case .uneven:
            return "Uneven lighting detected. Try to position for more uniform illumination."
        case .glare:
            return "Glare detected. Adjust angle to minimize reflections."
        case .mixed:
            return "Mixed lighting detected. Find a more consistent light source."
        case .unknown:
            return "Analyzing lighting conditions..."
        }
    }

    private func getAngleGuidanceText() -> String {
        guard let orientation = detectedTextOrientation, orientation.confidence > 0.5 else {
            return "Analyzing text orientation..."
        }

        let angle = abs(orientation.rotationAngle)
        if angle < 5 {
            return "Text appears horizontal. Good orientation detected."
        } else if angle < 30 {
            return "Slight angle detected. Minor adjustment may improve results."
        } else if angle < 60 {
            return "Moderate angle detected. Consider adjusting device position."
        } else {
            return "Significant angle detected. Rotate device for better alignment."
        }
    }

    // MARK: - Surface-Adaptive OCR Settings
    private func updateOCRSettingsForSurface() {
        // Combine surface detection with accessory preset settings
        let accessorySettings = accessoryPresetManager.currentOCRSettings

        if isSurfaceDetectionEnabled && detectedSurfaceType != .unknown {
            let surfaceSettings = OCRSettings.settingsFor(surface: detectedSurfaceType)

            // Use the more restrictive settings between surface and accessory
            textRecognitionRequest?.recognitionLevel = max(accessorySettings.recognitionLevel, surfaceSettings.recognitionLevel)
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

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension SerialScannerViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        processFrame(cgImage)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension SerialScannerViewModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            return
        }
        
        processFrame(cgImage)
    }
}
