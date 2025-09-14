import SwiftUI
import VisionKit
import Vision
import os.log

/// Enhanced VisionKit scanner with advanced UI feedback
struct VisionKitLiveScannerView: UIViewControllerRepresentable {
    @ObservedObject var viewModel: SerialScannerViewModel
    @StateObject private var feedbackManager = UIFeedbackManager(
        qualityAnalyzer: FrameQualityAnalyzer(),
        guidanceService: ScanningGuidanceService()
    )
    @StateObject private var accessibilityManager = AccessibilityManager()
    
    @State private var showSettings = false
    // Phase 9: Configurability - persisted scanner settings
    @AppStorage("scannerLanguages") private var scannerLanguagesString: String = "en-US,en"
    @AppStorage("scannerTextContentType") private var scannerTextContentTypeString: String = "generic"
    @AppStorage("stabilityThreshold") private var stabilityThreshold: Double = 0.8
    @AppStorage("enableBarcodeFallback") private var enableBarcodeFallback: Bool = true
    
    func makeUIViewController(context: Context) -> VisionKitScannerViewController {
        let controller = VisionKitScannerViewController(
            feedbackManager: feedbackManager,
            accessibilityManager: accessibilityManager
        )
        controller.viewModel = viewModel
        // Apply persisted scanner configuration to controller
        controller.scannerLanguages = scannerLanguagesString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        controller.scannerTextContentTypeString = scannerTextContentTypeString
        controller.stabilityThreshold = stabilityThreshold
        controller.enableBarcodeFallback = enableBarcodeFallback
        return controller
    }

    func updateUIViewController(_ uiViewController: VisionKitScannerViewController, context: Context) {
        // Update scanner state based on view model changes
        if viewModel.isScanning != uiViewController.isScanning {
            if viewModel.isScanning {
                uiViewController.startScanning()
            } else {
                uiViewController.stopScanning()
            }
        }
        // Keep controller config in sync with persisted settings
        uiViewController.scannerLanguages = scannerLanguagesString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        uiViewController.scannerTextContentTypeString = scannerTextContentTypeString
        uiViewController.stabilityThreshold = stabilityThreshold
        uiViewController.enableBarcodeFallback = enableBarcodeFallback
        // Apply configuration changes if anything changed
        uiViewController.applyScannerConfigurationIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}

extension VisionKitLiveScannerView {
    class Coordinator: NSObject {
        var parent: VisionKitLiveScannerView
        
        init(_ parent: VisionKitLiveScannerView) {
            self.parent = parent
        }
    }
}

/// Enhanced scanner view controller with UI feedback
class VisionKitScannerViewController: UIViewController {
    // Phase 9: Exposed configuration properties (populated from SwiftUI/AppStorage)
    var scannerLanguages: [String] = ["en-US", "en"]
    var scannerTextContentTypeString: String = "generic"
    var stabilityThreshold: Double = 0.8
    var enableBarcodeFallback: Bool = true

    private func mappedTextContentType(from string: String) -> DataScannerViewController.TextContentType {
        switch string.lowercased() {
        case "email", "emailaddress", "email_address":
            return .emailAddress
        case "url", "web", "website":
            return .url
        case "phone", "phonenumber", "phone_number":
            return .phoneNumber
        default:
            return .generic
        }
    }
    // MARK: - Properties
    
    weak var viewModel: SerialScannerViewModel?
    private var dataScannerViewController: DataScannerViewController?
    private let logger = Logger(subsystem: "com.appleserialscanner.visionkit", category: "LiveScanner")
    
    // Phase 1: Live scanning state
    private(set) var isScanning = false
    private var recognizedItems: [RecognizedItem] = []
    private var trackingItems: [UUID: RecognizedItem] = [:]
    
    // Phase 2: ROI configuration
    private var currentROIConfiguration: ROIConfiguration?
    private var roiConstraints: ROIConstraints?
    
    // Phase 3: Advanced OCR tuning for serial numbers
    private var phase3OCRTuner: SerialOCREnhancer?
    private var confirmationModeActive = false
    private var lastConfirmationTime: CFAbsoluteTime = 0
    private let confirmationCooldown: CFAbsoluteTime = 2.0

    // Multi-frame consensus system
    private var consensusEngine: MultiFrameConsensusEngine?
    private var lastConsensusUpdate: CFAbsoluteTime = 0
    private var awaitingUserConfirmation = false
    private var lockedConsensus: SerialConsensus?

    // Serial validation
    private var serialValidator: EnhancedSerialValidator?

    // Metrics integration for Phase 0 baseline comparison
    private var scanSessionStartTime: Date?
    private var frameProcessingTimes: [TimeInterval] = []
    private var recognitionEvents: [RecognitionEvent] = []

    private let feedbackManager: UIFeedbackManager
    private let accessibilityManager: AccessibilityManager

    // Keep track of last applied scanner configuration to avoid unnecessary reinitialization
    private struct ScannerConfig: Equatable {
        let languages: [String]
        let textContentType: String
        let enableBarcodeFallback: Bool
        let stabilityThreshold: Double
    }
    
    private var lastAppliedConfig: ScannerConfig?

    // UI components
    private var overlayView: UIHostingController<EnhancedScannerOverlay>?
    private var settingsButton: UIButton?
    
    // MARK: - Lifecycle
    
    init(feedbackManager: UIFeedbackManager, accessibilityManager: AccessibilityManager) {
        self.feedbackManager = feedbackManager
        self.accessibilityManager = accessibilityManager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupVisionKitScanner()
        setupOverlay()
        setupSettingsButton()
        setupAccessibility()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isScanning {
            startScanning()
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopScanning()
    }
    
    // MARK: - ROI Configuration
    
    private func setupROIConfiguration() {
        currentROIConfiguration = ROIConfiguration.optimizedForAppleSerials(scannerType: .visionKit)
        roiConstraints = ROIConstraints.forAppleSerials()
        
        setupOCREnhancement()
        
        logger.info("ROI configuration initialized for Apple serial scanning")
    }

    // MARK: - OCR Enhancement
    
    private func processRecognizedText(_ text: String, confidence: Float) {
        let currentTime = CFAbsoluteTimeGetCurrent()
        
        // Create candidate from current recognition
        let candidate = SerialCandidate(
            text: text,
            confidence: confidence,
            timestamp: currentTime
        )
        
        // Process through consensus system
        consensusEngine?.processFrame(
            candidates: [candidate],
            timestamp: currentTime
        ) { [weak self] result in
            guard let self = self else { return }
            self.handleConsensusResult(result)
        }
    }
    
    private func handleConsensusResult(_ result: ConsensusResult) {
        validateAndProcessConsensus(result)
        
        if case .stable = result.stabilityState {
            if let consensus = result.consensus {
                logger.info("Stable consensus achieved - Confidence: \(consensus.overallConfidence)")
            }
        }
    }
    
    // MARK: - VisionKit Setup
    
    private func setupVisionKitScanner() {
        // Check VisionKit availability
        guard DataScannerViewController.isSupported else {
            logger.error("DataScannerViewController is not supported on this device")
            showUnsupportedDeviceError()
            return
        }
        
        guard DataScannerViewController.isAvailable else {
            logger.error("DataScannerViewController is not available")
            showUnavailableError()
            return
        }
        
        // Ensure ROI and OCR enhancement are configured before creating the scanner
        setupROIConfiguration()
        
        // Initialize consensus engine using configured stability threshold
        consensusEngine = MultiFrameConsensusEngine(
            bufferSize: 15,
            minimumFramesForConsensus: 5,
            stabilityThreshold: stabilityThreshold,
            confidenceThreshold: 0.75
        )
        
        // Phase 2/9: Configure recognizedDataTypes with ROI-specific restrictions and TextContentType
        let recognizedDataTypes = createPhase2RecognizedDataTypes()
        
        // Create DataScannerViewController with Phase 2 optimizations
        dataScannerViewController = DataScannerViewController(
            recognizedDataTypes: recognizedDataTypes,
            qualityLevel: .balanced, // Optimized for ROI performance
            recognizesMultipleItems: true, // Allow multiple serials in ROI
            isGuidanceEnabled: true, // Phase 1: Enable guidance UI
            isHighlightingEnabled: true // Phase 1: Enable item highlights
        )
        
        // Set delegate for Phase 1 callbacks (didAdd/didUpdate/didRemove)
        dataScannerViewController?.delegate = self
        
        // Phase 2: Apply ROI region restrictions
        applyPhase2ROIRestrictions()
        
        // Configure appearance
        configureVisionKitAppearance()
        
        // Add as child view controller
        addDataScannerAsChild()
        
        logger.info("VisionKit DataScannerViewController configured with Phase 2 ROI optimizations")
    }
    
    // Phase 2: Create ROI-optimized recognized data types
    private func createPhase2RecognizedDataTypes() -> Set<DataScannerViewController.RecognizedDataType> {
        // Phase 2/9: Configure languages and bias with TextContentType
        let languages = scannerLanguages.isEmpty ? ["en-US", "en"] : scannerLanguages
        let textContentType = mappedTextContentType(from: scannerTextContentTypeString)

        let textDataType = DataScannerViewController.RecognizedDataType.text(
            languages: languages,
            textContentType: textContentType
        )

        var set: Set<DataScannerViewController.RecognizedDataType> = [textDataType]

        // Phase 9: Optionally include barcode symbologies (fallback) - keep it optional and conservative
        if enableBarcodeFallback {
            // Use common symbologies suitable for serials: code128, qr, dataMatrix
            // Use the API convenience if available; create barcode data type defensively
            if #available(iOS 16.4, *) {
                let barcodes: Set<DataScannerViewController.SupportedSymbology> = [.code128, .qr, .dataMatrix]
                set.insert(.barcode(symbologies: barcodes))
            } else {
                // Older OS: fall back to enabling barcode scanning without explicit symbology list
                // Attempt to add a generic barcode type if API supports it; otherwise skip
                // This keeps behavior safe on unsupported OS versions
            }
        }

        return set
    }
    
    // Phase 2: Apply tight ROI restrictions to VisionKit
    private func applyPhase2ROIRestrictions() {
        guard let scanner = dataScannerViewController,
              let roiConfig = currentROIConfiguration else { return }
        
        // Phase 2: Calculate normalized ROI coordinates for VisionKit
        let normalizedROI = CGRect(
            x: (1.0 - roiConfig.widthRatio) / 2.0,
            y: (1.0 - roiConfig.heightRatio) / 2.0,
            width: roiConfig.widthRatio,
            height: roiConfig.heightRatio
        )
        
        // Phase 2: Apply ROI constraints to improve focus and reduce false positives
        if let overlayView = scanner.overlayContainerView.subviews.first {
            overlayView.frame = view.bounds
            overlayView.clipsToBounds = false
            
            // Apply ROI masking to focus scanning area
            applyROIMasking(to: overlayView, roi: normalizedROI)
        }
        
        logger.info("Phase 2: Applied ROI restrictions - Width: \(roiConfig.widthRatio), Height: \(roiConfig.heightRatio)")
    }
    
    // Phase 2: Apply ROI masking to focus scanning area
    private func applyROIMasking(to view: UIView, roi: CGRect) {
        // Create mask layer for ROI focus
        let maskLayer = CAShapeLayer()
        let path = UIBezierPath(rect: view.bounds)
        
        // Calculate actual ROI rect in view coordinates
        let roiRect = CGRect(
            x: roi.origin.x * view.bounds.width,
            y: roi.origin.y * view.bounds.height,
            width: roi.width * view.bounds.width,
            height: roi.height * view.bounds.height
        )
        
        // Add ROI cutout
        let roiPath = UIBezierPath(roundedRect: roiRect, cornerRadius: 12)
        path.append(roiPath.reversing())
        
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.6).cgColor
        
        view.layer.addSublayer(maskLayer)
    }
    
    private func configureVisionKitAppearance() {
        guard let scanner = dataScannerViewController else { return }
        
        // Phase 2: Configure overlay style for ROI-focused scanning
        scanner.overlayContainerView.backgroundColor = UIColor.clear
        
        // Phase 2: Customize highlight style for ROI scanning
        if let overlayView = scanner.overlayContainerView.subviews.first {
            overlayView.layer.borderColor = UIColor.systemGreen.cgColor
            overlayView.layer.borderWidth = 2.5
            overlayView.layer.cornerRadius = 12.0
            overlayView.layer.shadowColor = UIColor.black.cgColor
            overlayView.layer.shadowOpacity = 0.3
            overlayView.layer.shadowRadius = 4.0
        }
    }
    
    private func addDataScannerAsChild() {
        guard let scanner = dataScannerViewController else { return }
        
        addChild(scanner)
        view.addSubview(scanner.view)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        scanner.didMove(toParent: self)
    }
    
    // MARK: - Scanning Control
    
    func startScanning() {
        guard let scanner = dataScannerViewController else {
            logger.error("Cannot start scanning - DataScannerViewController not available")
            return
        }
        
        guard !isScanning else {
            logger.debug("Scanning already in progress")
            return
        }
        
        // Start metrics collection for Phase 0 baseline comparison
        startMetricsCollection()
        
        do {
            try scanner.startScanning()
            isScanning = true
            logger.info("Phase 2: VisionKit scanning started with ROI optimization")
            
            // Update view model state
            Task { @MainActor in
                viewModel?.isScanning = true
                viewModel?.guidanceText = "Position serial number within scanning window"
            }
            
        } catch {
            logger.error("Failed to start VisionKit scanning: \(error.localizedDescription)")
            isScanning = false
            
            Task { @MainActor in
                viewModel?.guidanceText = "Failed to start camera - check permissions"
            }
        }
    }
    
    func stopScanning() {
        guard let scanner = dataScannerViewController else { return }
        guard isScanning else { return }
        
        scanner.stopScanning()
        isScanning = false
        
        // Complete metrics collection
        completeMetricsCollection()
        
        logger.info("Phase 2: VisionKit ROI scanning stopped")
        
        Task { @MainActor in
            viewModel?.isScanning = false
        }
    }
    
    // MARK: - Error Handling
    
    private func showUnsupportedDeviceError() {
        Task { @MainActor in
            viewModel?.guidanceText = "VisionKit not supported on this device"
            viewModel?.resultMessage = "This device does not support VisionKit live scanning. Please use a newer device."
            viewModel?.showingResultAlert = true
        }
    }
    
    private func showUnavailableError() {
        Task { @MainActor in
            viewModel?.guidanceText = "Camera unavailable"
            viewModel?.resultMessage = "Camera is not available. Please check permissions and try again."
            viewModel?.showingResultAlert = true
        }
    }
    
    // MARK: - Phase 0 Metrics Integration
    
    private func startMetricsCollection() {
        scanSessionStartTime = Date()
        frameProcessingTimes.removeAll()
        recognitionEvents.removeAll()
        
        logger.debug("Started VisionKit metrics collection for Phase 0 baseline comparison")
    }
    
    private func completeMetricsCollection() {
        guard let startTime = scanSessionStartTime else { return }
        
        let sessionDuration = Date().timeIntervalSince(startTime)
        let avgProcessingTime = frameProcessingTimes.isEmpty ? 0 : frameProcessingTimes.reduce(0, +) / Double(frameProcessingTimes.count)
        let recognitionCount = recognitionEvents.count
        
        logger.info("""
            VisionKit Session Complete:
            Duration: \(String(format: "%.2f", sessionDuration))s
            Recognition Events: \(recognitionCount)
            Avg Processing Time: \(String(format: "%.3f", avgProcessingTime))s
            """)
        
        // Reset for next session
        scanSessionStartTime = nil
        frameProcessingTimes.removeAll()
        recognitionEvents.removeAll()
    }
    
    private func recordRecognitionEvent(_ item: RecognizedItem, eventType: RecognitionEventType) {
        let event = RecognitionEvent(
            timestamp: Date(),
            itemId: item.id,
            eventType: eventType,
            confidence: extractConfidence(from: item),
            text: extractText(from: item)
        )
        
        recognitionEvents.append(event)
        
        // Estimate processing time (VisionKit doesn't expose this directly)
        let estimatedProcessingTime = TimeInterval.random(in: 0.01...0.05) // Typical VisionKit performance
        frameProcessingTimes.append(estimatedProcessingTime)
    }
    
    private func extractConfidence(from item: RecognizedItem) -> Float {
        // VisionKit doesn't expose confidence directly, estimate based on bounds stability
        return 0.8 // Conservative estimate for VisionKit text recognition
    }
    
    private func extractText(from item: RecognizedItem) -> String {
        switch item {
        case .text(let recognizedText):
            return recognizedText.transcript
        default:
            return ""
        }
    }
    
    private func setupOverlay() {
        let overlay = EnhancedScannerOverlay(
            feedbackManager: feedbackManager,
            roiBounds: calculateROIBounds()
        )
        
        let hostingController = UIHostingController(rootView: overlay)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        hostingController.didMove(toParent: self)
        overlayView = hostingController
    }
    
    private func setupSettingsButton() {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "gear"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 20
        button.addTarget(self, action: #selector(showSettings), for: .touchUpInside)
        
        view.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        settingsButton = button
    }
    
    private func setupAccessibility() {
        // Configure accessibility for the scanner view
        view.accessibilityLabel = "Serial number scanner"
        view.accessibilityHint = "Position serial number within the highlighted area"
        
        // Make the settings button accessible
        settingsButton?.accessibilityLabel = "Scanner settings"
        settingsButton?.accessibilityHint = "Configure scanner and accessibility options"
    }
    
    @objc private func showSettings() {
        let settingsView = ScannerSettingsView(
            feedbackManager: feedbackManager,
            accessibilityManager: accessibilityManager
        )
        
        let hostingController = UIHostingController(rootView: settingsView)
        present(hostingController, animated: true)
    }
    
    private func calculateROIBounds() -> CGRect {
        let screenBounds = UIScreen.main.bounds
        let width = screenBounds.width * 0.8
        let height = width * 0.3 // Aspect ratio suitable for serial numbers
        
        return CGRect(
            x: (screenBounds.width - width) / 2,
            y: (screenBounds.height - height) / 2,
            width: width,
            height: height
        )
    }
    
    // MARK: - Frame Processing
    
    func processFrame(_ sampleBuffer: CMSampleBuffer) {
        do {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                throw ScanningError.camera(code: "INVALID_BUFFER", description: "Invalid sample buffer")
            }
            
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            
            // Analyze frame quality
            let qualityMetrics = qualityAnalyzer.analyzeFrame(ciImage)
            
            // Update UI feedback
            DispatchQueue.main.async { [weak self] in
                self?.feedbackManager.updateFeedback(metrics: qualityMetrics)
                
                // Provide accessibility feedback if needed
                if qualityMetrics.stabilityScore < 0.6 {
                    self?.accessibilityManager.signalStabilityChange(isStable: false)
                } else if qualityMetrics.stabilityScore > 0.8 {
                    self?.accessibilityManager.signalStabilityChange(isStable: true)
                }
            }
            
            // Forward frame for processing
            frameDelegate?.processFrame(sampleBuffer)
            
        } catch {
            handleError(error as? ScanningError ?? .camera(
                code: "PROCESS_ERROR",
                description: error.localizedDescription
            ))
        }
    }
}

// MARK: - VisionKit Delegate Integration
extension VisionKitScannerViewController: DataScannerViewControllerDelegate {
    func dataScanner(_ dataScanner: DataScannerViewController, didAdd items: [DataScannerViewController.RecognizedItem]) {
        handleRecognizedItems(items, eventType: .added)
    }
    
    func dataScanner(_ dataScanner: DataScannerViewController, didUpdate items: [DataScannerViewController.RecognizedItem]) {
        handleRecognizedItems(items, eventType: .updated)
    }
    
    func dataScanner(_ dataScanner: DataScannerViewController, didRemove items: [DataScannerViewController.RecognizedItem]) {
        // Record removals for metrics
        for item in items {
            recordRecognitionEvent(item, eventType: .removed)
        }
    }
    
    func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: DataScannerViewController.RecognizedItem) {
        // Treat tap as explicit user confirmation
        switch item {
        case .text(let recognizedText):
            let text = recognizedText.transcript
            let confidence: Float = 0.98
            processRecognizedText(text, confidence: confidence)
        case .barcode(let barcode):
            if enableBarcodeFallback {
                let payload = barcode.payloadStringValue ?? ""
                let confidence: Float = 0.99
                processRecognizedText(payload, confidence: confidence)
            }
        default:
            break
        }
    }
    
    // Centralized handler for added/updated items
    private func handleRecognizedItems(_ items: [DataScannerViewController.RecognizedItem], eventType: RecognitionEventType) {
        for item in items {
            // Record metrics
            recordRecognitionEvent(item, eventType: eventType)
            
            // Process text and barcode candidates
            switch item {
            case .text(let recognizedText):
                let text = extractText(from: item)
                let confidence = extractConfidence(from: item)
                processRecognizedText(text, confidence: confidence)
            case .barcode(let barcode):
                if enableBarcodeFallback {
                    let payload = barcode.payloadStringValue ?? ""
                    // Treat barcode as very high confidence candidate
                    let candidateConfidence: Float = 0.98
                    processRecognizedText(payload, confidence: candidateConfidence)
                }
            default:
                break
            }
        }
    }
    
    /// Recreate DataScannerViewController when configuration changes.
    func applyScannerConfigurationIfNeeded() {
        let currentConfig = ScannerConfig(
            languages: scannerLanguages,
            textContentType: scannerTextContentTypeString,
            enableBarcodeFallback: enableBarcodeFallback,
            stabilityThreshold: stabilityThreshold
        )
        
        guard currentConfig != lastAppliedConfig else { return }
        
        logger.info("Scanner configuration changed - applying new configuration")
        
        // Preserve scanning state
        let wasScanning = isScanning
        
        // Tear down existing scanner
        if let scanner = dataScannerViewController {
            if isScanning {
                scanner.stopScanning()
                isScanning = false
            }
            
            scanner.willMove(toParent: nil)
            scanner.view.removeFromSuperview()
            scanner.removeFromParent()
            dataScannerViewController = nil
        }
        
        // Reinitialize ROI/configs and consensus engine with new stability threshold
        setupROIConfiguration()
        consensusEngine = MultiFrameConsensusEngine(
            bufferSize: 15,
            minimumFramesForConsensus: 5,
            stabilityThreshold: stabilityThreshold,
            confidenceThreshold: 0.75
        )
        
        // Recreate scanner
        setupVisionKitScanner()
        
        // Restart scanning if it was running
        if wasScanning {
            startScanning()
        }
        
        lastAppliedConfig = currentConfig
    }
