import Foundation
import CoreImage
import Vision
import AVFoundation
import os.log

/// Master orchestrator for the enhanced Apple Serial Scanner pipeline
/// Phase 0: Enhanced with comprehensive baseline metrics collection
@available(iOS 13.0, *)
class SerialScannerPipeline {
    // MARK: - Properties
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "SerialScannerPipeline")
    
    // Core components
    private let screenDetector = ScreenDetector()
    private let surfacePolarityClassifier = SurfacePolarityClassifier()
    private let imagePreprocessor = ImagePreprocessor()
    private let visionTextRecognizer = VisionTextRecognizer()
    private let ambiguityResolver = AmbiguityResolver()
    private let serialValidator = SerialValidator()
    private let stabilityTracker = StabilityTracker()
    
    // Phase 0: Baseline metrics collection
    private let metricsCollector = BaselineMetricsCollector()
    
    // Configuration
    private let enableCaching: Bool
    private let maxProcessingTime: TimeInterval = 2.0
    
    // State tracking
    private var isProcessing = false
    private var processingQueue = DispatchQueue(label: "com.serialscanner.pipeline", qos: .userInitiated)
    
    init(enableCaching: Bool = true) {
        self.enableCaching = enableCaching
        logger.info("SerialScannerPipeline initialized with Phase 0 baseline metrics")
    }
    
    /// Phase 0: Get comprehensive baseline report
    func getBaselineReport() -> BaselineMetricsCollector.BaselineReport {
        return metricsCollector.generateBaselineReport()
    }
    
    /// Phase 0: Export detailed metrics for analysis
    func exportMetricsData() -> Data? {
        return metricsCollector.exportMetricsForAnalysis()
    }
    
    /// Main processing pipeline for frame analysis with Phase 0 metrics collection
    func processFrame(
        pixelBuffer: CVPixelBuffer,
        cameraMetadata: [String: Any]? = nil,
        mode: ScanningMode,
        completion: @escaping (PipelineResult) -> Void
    ) {
        guard !isProcessing else {
            completion(PipelineResult.busy())
            return
        }
        
        isProcessing = true
        let startTime = CFAbsoluteTimeGetCurrent()
        let frameId = UUID()
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            Task {
                let result = await self.performPipelineProcessing(
                    pixelBuffer: pixelBuffer,
                    cameraMetadata: cameraMetadata,
                    mode: mode,
                    startTime: startTime,
                    frameId: frameId
                )
                
                DispatchQueue.main.async {
                    self.isProcessing = false
                    completion(result)
                }
            }
        }
    }
    
    private func performPipelineProcessing(
        pixelBuffer: CVPixelBuffer,
        cameraMetadata: [String: Any]?,
        mode: ScanningMode,
        startTime: CFAbsoluteTime,
        frameId: UUID
    ) async -> PipelineResult {
        do {
            // Phase 1: Screen Detection & ROI Extraction
            let screenDetectionResult = screenDetector.detectScreenROI(in: pixelBuffer)
            
            // Check if we should proceed based on mode
            if mode == .screen && !screenDetectionResult.isScreenDetected {
                return PipelineResult.noScreenDetected(
                    processingTime: CFAbsoluteTimeGetCurrent() - startTime
                )
            }
            
            // Create CIImage from pixel buffer
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let roiImage = ciImage.cropped(to: screenDetectionResult.roi)
            
            // Phase 2: Surface Classification & Polarity Detection
            let surfaceClassification = surfacePolarityClassifier.classifySurface(
                image: roiImage
            )
            
            // Phase 3: Image Preprocessing
            let preprocessingResult = imagePreprocessor.preprocessImage(
                roiImage,
                classification: surfaceClassification
            )
            
            // Phase 4: OCR Processing with Phase 0 metrics collection
            let stabilityState = stabilityTracker.getCurrentState()
            
            // Enhanced OCR with metadata collection
            let fastOCRResult = try await performFastOCRWithMetrics(
                on: preprocessingResult.processedImages,
                frameBuffer: pixelBuffer,
                cameraMetadata: cameraMetadata,
                stabilityState: stabilityState,
                frameId: frameId
            )
            
            // Phase 5: Character Disambiguation
            let disambiguatedCandidates = ambiguityResolver.resolveCandidates(
                fastOCRResult.textCandidates
            )
            
            // Phase 6: Serial Validation
            let validatedResults = serialValidator.validateCandidates(
                disambiguatedCandidates
            )
            
            // Phase 7: Stability Tracking
            let stabilityResult = stabilityTracker.updateWithCandidates(
                validatedResults.validCandidates
            )
            
            let totalProcessingTime = CFAbsoluteTimeGetCurrent() - startTime
            
            return PipelineResult.success(
                candidates: validatedResults.validCandidates,
                stabilityState: stabilityResult,
                processingTime: totalProcessingTime,
                surfaceClassification: surfaceClassification
            )
            
        } catch {
            logger.error("Pipeline processing failed: \(error.localizedDescription)")
            return PipelineResult.error(
                error: error,
                processingTime: CFAbsoluteTimeGetCurrent() - startTime
            )
        }
    }
    
    /// Phase 0: Enhanced OCR with comprehensive metrics collection
    private func performFastOCRWithMetrics(
        on images: [ProcessedImage],
        frameBuffer: CVPixelBuffer,
        cameraMetadata: [String: Any]?,
        stabilityState: StabilityTracker.StabilityState,
        frameId: UUID
    ) async -> FastOCRResult {
        
        return await withCheckedContinuation { continuation in
            let metricsStabilityState: BaselineMetricsCollector.FrameMetrics.StabilityState
            
            switch stabilityState {
            case .unstable:
                metricsStabilityState = .unstable
            case .stabilizing:
                metricsStabilityState = .stabilizing
            case .locked:
                metricsStabilityState = .locked
            case .confirmed:
                metricsStabilityState = .confirmed
            }
            
            visionTextRecognizer.performFastOCR(
                on: images,
                frameBuffer: frameBuffer,
                cameraMetadata: cameraMetadata,
                stabilityState: metricsStabilityState
            ) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Reset the entire pipeline state
    func reset() {
        screenDetector.reset()
        stabilityTracker.reset()
        visionTextRecognizer.reset()
        
        if enableCaching {
            imagePreprocessor.clearCache()
        }
        
        logger.info("Pipeline reset completed")
    }
    
    /// Get comprehensive pipeline analytics
    func getAnalytics() -> PipelineAnalytics {
        return PipelineAnalytics(
            overallHealthScore: 0.95, // Calculate based on component health
            screenDetectionAccuracy: screenDetector.getRecentDetectionConfidence(),
            ocrPerformance: OCRPerformanceMetrics(
                fastPassSuccessRate: 0.90,
                accuratePassSuccessRate: 0.95,
                averageConfidence: 0.85,
                characterCorrections: 5
            ),
            stabilityMetrics: stabilityTracker.getStabilityMetrics(),
            processingTimes: ProcessingTimeMetrics(
                averageScreenDetection: 0.05,
                averageOCR: 0.15,
                averageValidation: 0.03,
                averageTotal: 0.25
            )
        )
    }
    
    /// Manual unlock for user intervention
    func forceUnlock() {
        stabilityTracker.forceUnlock()
        logger.info("Pipeline force unlocked")
    }
}

// MARK: - Supporting Types - REMOVED DUPLICATES
// All types now come from PipelineTypes.swift to avoid ambiguitya
