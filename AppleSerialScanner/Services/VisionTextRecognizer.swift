import Foundation
import Vision
import CoreImage
import os.log

/// High-performance text recognizer with two-stage OCR processing
/// Phase 0: Enhanced with comprehensive baseline metrics collection
@available(iOS 13.0, *)
class VisionTextRecognizer {
    // MARK: - Properties
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "VisionTextRecognizer")
    private let sequenceHandler = VNSequenceRequestHandler()
    private var isProcessing = false
    private let processingQueue = DispatchQueue(label: "com.serialscanner.ocr", qos: .userInitiated)
    
    // Phase 0: Baseline metrics collection
    private let metricsCollector = BaselineMetricsCollector()
    
    // OCR Requests
    private let fastRequest: VNRecognizeTextRequest
    private let accurateRequest: VNRecognizeTextRequest
    
    // Performance tracking
    private var lastProcessingTime: CFAbsoluteTime = 0
    private let minProcessingInterval: CFAbsoluteTime = 0.08 // ~12 FPS max
    
    init() {
        // Configure fast request for real-time feedback
        fastRequest = VNRecognizeTextRequest()
        fastRequest.recognitionLevel = .fast
        fastRequest.usesLanguageCorrection = false
        fastRequest.minimumTextHeight = 0.02
        fastRequest.recognitionLanguages = ["en_US"]
        fastRequest.revision = VNRecognizeTextRequestRevision3
        
        // Configure accurate request for final recognition
        accurateRequest = VNRecognizeTextRequest()
        accurateRequest.recognitionLevel = .accurate
        accurateRequest.usesLanguageCorrection = false
        accurateRequest.minimumTextHeight = 0.015
        accurateRequest.recognitionLanguages = ["en_US"]
        accurateRequest.revision = VNRecognizeTextRequestRevision3
        
        logger.debug("VisionTextRecognizer initialized with baseline metrics collection")
    }
    
    /// Phase 0: Get baseline report for performance analysis
    func getBaselineReport() -> BaselineMetricsCollector.BaselineReport {
        return metricsCollector.generateBaselineReport()
    }
    
    /// Phase 0: Export detailed metrics for analysis
    func exportMetricsData() -> Data? {
        return metricsCollector.exportMetricsForAnalysis()
    }
    
    /// Performs fast OCR pass for real-time feedback with Apple serial focus
    /// Phase 0: Enhanced with comprehensive metrics collection
    func performFastOCR(
        on images: [ProcessedImage],
        frameBuffer: CVPixelBuffer? = nil,
        cameraMetadata: [String: Any]? = nil,
        stabilityState: BaselineMetricsCollector.FrameMetrics.StabilityState = .unstable,
        completion: @escaping (FastOCRResult) -> Void
    ) {
        guard !isProcessing else {
            completion(FastOCRResult(textCandidates: [], processingTime: 0, skippedDueToThrottling: true))
            return
        }
        
        // Throttle processing to maintain performance
        let currentTime = CFAbsoluteTimeGetCurrent()
        guard currentTime - lastProcessingTime >= minProcessingInterval else {
            completion(FastOCRResult(textCandidates: [], processingTime: 0, skippedDueToThrottling: true))
            return
        }
        
        isProcessing = true
        lastProcessingTime = currentTime
        
        // Phase 0: Start timing for baseline metrics
        let ocrStartTime = CFAbsoluteTimeGetCurrent()
        let frameId = UUID()
        
        logger.info("Starting fast OCR on \(images.count) images - Frame: \(frameId)")
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            var allCandidates: [TextCandidate] = []
            var recognitionResults: [VNRecognizedTextObservation] = []
            var failureSnapshot: Data? = nil
            
            for (imageIndex, processedImage) in images.enumerated() {
                do {
                    // Configure fast request for Apple serial numbers
                    self.configureRequestForAppleSerials(self.fastRequest)
                    
                    let handler = VNImageRequestHandler(ciImage: processedImage.image, options: [:])
                    try handler.perform([self.fastRequest])
                    
                    if let observations = self.fastRequest.results {
                        recognitionResults.append(contentsOf: observations)
                        self.logger.debug("Found \(observations.count) text observations in image \(imageIndex)")
                        
                        let candidates = self.extractAppleSerialCandidates(
                            from: observations,
                            source: .fast,
                            imageIndex: imageIndex,
                            isInverted: processedImage.isInverted
                        )
                        
                        self.logger.debug("Filtered to \(candidates.count) potential serial candidates")
                        allCandidates.append(contentsOf: candidates)
                    }
                } catch {
                    self.logger.error("Fast OCR failed for image \(imageIndex): \(error.localizedDescription)")
                    
                    // Phase 0: Capture failure snapshot for analysis
                    if failureSnapshot == nil {
                        failureSnapshot = self.captureFailureSnapshot(
                            image: processedImage.image,
                            error: error,
                            settings: self.fastRequest
                        )
                    }
                }
            }
            
            // Phase 0: Record comprehensive metrics
            let ocrEndTime = CFAbsoluteTimeGetCurrent()
            self.metricsCollector.recordFrameMetrics(
                frameId: frameId,
                ocrStartTime: ocrStartTime,
                ocrEndTime: ocrEndTime,
                recognitionResults: recognitionResults,
                ocrRequest: self.fastRequest,
                cameraMetadata: cameraMetadata,
                frameBuffer: frameBuffer,
                processingMode: .fast,
                stabilityState: stabilityState,
                failureSnapshot: failureSnapshot
            )
            
            let processingTime = ocrEndTime - ocrStartTime
            self.logger.info("Fast OCR completed - found \(allCandidates.count) candidates in \(String(format: "%.2f", processingTime * 1000))ms")
            
            let result = FastOCRResult(
                textCandidates: allCandidates,
                processingTime: processingTime,
                skippedDueToThrottling: false
            )
            
            DispatchQueue.main.async {
                self.isProcessing = false
                completion(result)
            }
        }
    }
    
    /// Performs accurate OCR pass for final recognition with Apple serial focus
    /// Phase 0: Enhanced with comprehensive metrics collection
    func performAccurateOCR(
        on images: [ProcessedImage],
        frameBuffer: CVPixelBuffer? = nil,
        cameraMetadata: [String: Any]? = nil,
        stabilityState: BaselineMetricsCollector.FrameMetrics.StabilityState = .locked,
        completion: @escaping (AccurateOCRResult) -> Void
    ) {
        // Phase 0: Start timing for baseline metrics
        let ocrStartTime = CFAbsoluteTimeGetCurrent()
        let frameId = UUID()
        
        logger.info("Starting accurate OCR on \(images.count) images - Frame: \(frameId)")
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            var allCandidates: [TextCandidate] = []
            var recognitionResults: [VNRecognizedTextObservation] = []
            var failureSnapshot: Data? = nil
            
            for (imageIndex, processedImage) in images.enumerated() {
                do {
                    // Configure accurate request for Apple serial numbers
                    self.configureRequestForAppleSerials(self.accurateRequest)
                    
                    let handler = VNImageRequestHandler(ciImage: processedImage.image, options: [:])
                    try handler.perform([self.accurateRequest])
                    
                    if let observations = self.accurateRequest.results {
                        recognitionResults.append(contentsOf: observations)
                        self.logger.debug("Accurate OCR found \(observations.count) text observations in image \(imageIndex)")
                        
                        let candidates = self.extractAppleSerialCandidates(
                            from: observations,
                            source: .accurate,
                            imageIndex: imageIndex,
                            isInverted: processedImage.isInverted
                        )
                        
                        allCandidates.append(contentsOf: candidates)
                    }
                } catch {
                    self.logger.error("Accurate OCR failed for image \(imageIndex): \(error.localizedDescription)")
                    
                    // Phase 0: Capture failure snapshot for analysis
                    if failureSnapshot == nil {
                        failureSnapshot = self.captureFailureSnapshot(
                            image: processedImage.image,
                            error: error,
                            settings: self.accurateRequest
                        )
                    }
                }
            }
            
            // Phase 0: Record comprehensive metrics
            let ocrEndTime = CFAbsoluteTimeGetCurrent()
            self.metricsCollector.recordFrameMetrics(
                frameId: frameId,
                ocrStartTime: ocrStartTime,
                ocrEndTime: ocrEndTime,
                recognitionResults: recognitionResults,
                ocrRequest: self.accurateRequest,
                cameraMetadata: cameraMetadata,
                frameBuffer: frameBuffer,
                processingMode: .accurate,
                stabilityState: stabilityState,
                failureSnapshot: failureSnapshot
            )
            
            let processingTime = ocrEndTime - ocrStartTime
            
            let result = AccurateOCRResult(
                textCandidates: allCandidates,
                processingTime: processingTime
            )
            
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
    
    // MARK: - Phase 0: Baseline Metrics Implementation
    
    /// Captures failure snapshot for analysis as specified in Phase 0
    private func captureFailureSnapshot(
        image: CIImage,
        error: Error,
        settings: VNRecognizeTextRequest
    ) -> Data? {
        do {
            let context = CIContext()
            guard let cgImage = context.createCGImage(image, from: image.extent) else {
                return nil
            }
            
            // Create failure snapshot with metadata
            let snapshot: [String: Any] = [
                "timestamp": CFAbsoluteTimeGetCurrent(),
                "error": error.localizedDescription,
                "recognitionLevel": settings.recognitionLevel,
                "usesLanguageCorrection": settings.usesLanguageCorrection,
                "minimumTextHeight": settings.minimumTextHeight,
                "recognitionLanguages": settings.recognitionLanguages ?? [],
                "imageSize": [
                    "width": image.extent.width,
                    "height": image.extent.height
                ]
            ]
            
            return try JSONSerialization.data(withJSONObject: snapshot, options: .prettyPrinted)
        } catch {
            logger.error("Failed to capture failure snapshot: \(error)")
            return nil
        }
    }
    
    /// Configures OCR request specifically for Apple serial numbers
    private func configureRequestForAppleSerials(_ request: VNRecognizeTextRequest) {
        // Optimize for Apple serial number characteristics
        request.usesLanguageCorrection = false  // Serial numbers don't need language correction
        request.customWords = []  // Clear any custom words
        
        // Apple serial numbers are typically:
        // - 10-12 characters
        // - Mix of letters and numbers
        // - No special characters or spaces
        // - Often in specific fonts (system fonts, engraved text)
        
        // Adjust text height based on typical Apple serial sizes
        if request.recognitionLevel == .fast {
            request.minimumTextHeight = 0.015  // Smaller to catch more serials
        } else {
            request.minimumTextHeight = 0.012  // Even smaller for accurate pass
        }
        
        // Use latest revision for best accuracy
        request.revision = VNRecognizeTextRequestRevision3
    }
    
    /// Extracts and filters text candidates specifically for Apple serial numbers
    private func extractAppleSerialCandidates(
        from observations: [VNRecognizedTextObservation],
        source: TextCandidate.OCRSource,
        imageIndex: Int = 0,
        isInverted: Bool = false
    ) -> [TextCandidate] {
        var candidates: [TextCandidate] = []
        
        for (observationIndex, observation) in observations.enumerated() {
            for (rank, recognizedText) in observation.topCandidates(5).enumerated() {
                let rawText = recognizedText.string
                let cleanText = cleanTextForSerialAnalysis(rawText)
                
                // Pre-filter: Only consider text that could be an Apple serial
                if isLikelyAppleSerial(cleanText) {
                    let confidence = calculateAppleSerialConfidence(
                        text: cleanText,
                        visionConfidence: recognizedText.confidence
                    )
                    
                    let textCandidate = TextCandidate(
                        text: cleanText,
                        confidence: confidence,
                        boundingBox: observation.boundingBox,
                        source: source
                    )
                    
                    candidates.append(textCandidate)
                    
                    // Log promising candidates
                    if confidence > 0.5 {
                        logger.debug("Promising serial candidate: '\(cleanText)' confidence: \(String(format: "%.2f", confidence))")
                    }
                }
            }
        }
        
        // Sort by confidence and return top candidates
        return candidates.sorted { $0.confidence > $1.confidence }
    }
    
    /// Cleans raw OCR text for serial number analysis
    private func cleanTextForSerialAnalysis(_ text: String) -> String {
        // Remove common OCR artifacts and normalize
        let cleaned = text
            .uppercased()
            .replacingOccurrences(of: " ", with: "")  // Remove spaces
            .replacingOccurrences(of: "-", with: "")  // Remove dashes
            .replacingOccurrences(of: "_", with: "")  // Remove underscores
            .replacingOccurrences(of: ".", with: "")  // Remove dots
            .replacingOccurrences(of: ",", with: "")  // Remove commas
            .replacingOccurrences(of: ":", with: "")  // Remove colons
            .replacingOccurrences(of: ";", with: "")  // Remove semicolons
            .replacingOccurrences(of: "|", with: "1") // Common OCR mistake
            .replacingOccurrences(of: "S", with: "5") // Common in serial contexts
            .replacingOccurrences(of: "O", with: "0") // Common confusion
        
        return cleaned
    }
    
    /// Determines if text is likely to be an Apple serial number
    private func isLikelyAppleSerial(_ text: String) -> Bool {
        // Basic length check (Apple serials are typically 10-12 characters)
        guard text.count >= 8 && text.count <= 15 else { return false }
        
        // Must be alphanumeric only
        let alphanumericSet = CharacterSet.alphanumerics
        guard text.unicodeScalars.allSatisfy({ alphanumericSet.contains($0) }) else { return false }
        
        // Apple serial patterns:
        // Format 1: 3 letters + 8-9 alphanumeric (e.g., "F4K1234567")
        // Format 2: 1-2 letters + 10 alphanumeric (e.g., "C1234567890")
        // Format 3: All alphanumeric, 10-12 chars (newer format)
        
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
        
        // Additional heuristic: Check for common Apple serial prefixes
        let commonApplePrefixes = ["F", "C", "D", "G", "H", "J", "K", "M", "N", "P", "Q", "R", "T", "V", "W", "X", "Y"]
        if commonApplePrefixes.contains(where: { text.hasPrefix($0) }) && text.count >= 10 {
            return true
        }
        
        return false
    }
    
    /// Calculates confidence score specifically for Apple serial numbers
    private func calculateAppleSerialConfidence(text: String, visionConfidence: Float) -> Float {
        var confidence = visionConfidence
        
        // Boost confidence for strong Apple serial patterns
        if text.count == 10 || text.count == 11 || text.count == 12 {
            confidence += 0.1
        }
        
        // Check for Apple-specific patterns
        if text.range(of: "^[A-Z]{1,3}[A-Z0-9]{8,10}$", options: .regularExpression) != nil {
            confidence += 0.15  // Strong Apple pattern
        }
        
        // Penalize non-serial-like characteristics
        if text.contains("MODEL") || text.contains("SERIAL") || text.contains("NUMBER") {
            confidence -= 0.3  // This is likely a label, not the serial
        }
        
        if text.count < 8 || text.count > 15 {
            confidence -= 0.2  // Wrong length for Apple serial
        }
        
        // Check character distribution (Apple serials have good mix of letters/numbers)
        let letterCount = text.filter { $0.isLetter }.count
        let numberCount = text.filter { $0.isNumber }.count
        let totalCount = text.count
        
        if letterCount > 0 && numberCount > 0 {
            let letterRatio = Float(letterCount) / Float(totalCount)
            let numberRatio = Float(numberCount) / Float(totalCount)
            
            // Ideal ratio is roughly 20-40% letters, 60-80% numbers
            if letterRatio >= 0.2 && letterRatio <= 0.5 && numberRatio >= 0.5 && numberRatio <= 0.8 {
                confidence += 0.1
            }
        }
        
        return min(max(confidence, 0.0), 1.0)  // Clamp between 0 and 1
    }
}

// MARK: - Text Recognition Extensions

extension VNRecognizedTextObservation {
    var topCandidates: [VNRecognizedText] {
        return self.topCandidates(3)
    }
}

extension Array where Element == VNRecognizedTextObservation {
    var allText: String {
        return self.compactMap { $0.topCandidates.first?.string }.joined(separator: " ")
    }
}
