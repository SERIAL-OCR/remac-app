import Foundation
import Vision
import CoreImage
import AVFoundation
import os.log

/// Phase 3: Advanced OCR tuning specifically optimized for Apple serial number recognition
/// Implements accurate mode confirmation frames with full-resolution ROI processing
@available(iOS 13.0, *)
class Phase3SerialOCRTuner {
    
    // MARK: - Propersties
    
    private let logger = Logger(subsystem: "com.appleserialscanner.phase3", category: "SerialOCRTuner")
    
    // Phase 3: Dual-mode OCR requests optimized for serial numbers
    private let fastRequest: VNRecognizeTextRequest
    private let accurateConfirmationRequest: VNRecognizeTextRequest
    
    // Phase 3: Full-resolution processing for confirmation
    private let highResolutionRequest: VNRecognizeTextRequest
    
    // ROI processing configuration
    private var currentROI: CGRect = CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.4)
    private let imageScaleFactors: [CGFloat] = [1.0, 1.5, 2.0] // For multi-resolution processing
    
    // Processing queues for different quality levels
    private let fastProcessingQueue = DispatchQueue(label: "com.phase3.fast", qos: .userInteractive)
    private let accurateProcessingQueue = DispatchQueue(label: "com.phase3.accurate", qos: .userInitiated)
    private let confirmationProcessingQueue = DispatchQueue(label: "com.phase3.confirmation", qos: .utility)
    
    // MARK: - Initialization
    
    init() {
        // Phase 3: Configure fast request for real-time scanning
        fastRequest = VNRecognizeTextRequest()
        configureFastRequest()
        
        // Phase 3: Configure accurate request for confirmation frames
        accurateConfirmationRequest = VNRecognizeTextRequest()
        configureAccurateConfirmationRequest()
        
        // Phase 3: Configure high-resolution request for final validation
        highResolutionRequest = VNRecognizeTextRequest()
        configureHighResolutionRequest()
        
        logger.info("Phase 3: Serial OCR tuner initialized with optimized recognition settings")
    }
    
    // MARK: - Phase 3: OCR Request Configuration
    
    /// Configure fast request for real-time preview scanning
    private func configureFastRequest() {
        fastRequest.recognitionLevel = .fast
        fastRequest.usesLanguageCorrection = false // Phase 3: Disabled for serials
        fastRequest.recognitionLanguages = ["en-US"] // Phase 3: Minimal language set
        fastRequest.minimumTextHeight = 0.015 // Optimized for Apple serials
        fastRequest.revision = VNRecognizeTextRequestRevision3
        
        // Phase 3: Serial-specific character set if available
        if #available(iOS 16.0, *) {
            // Use newer APIs for better serial recognition
            fastRequest.automaticallyDetectsLanguage = false
        }
        
        logger.debug("Phase 3: Fast request configured for real-time serial scanning")
    }
    
    /// Phase 3: Configure accurate request for confirmation frames as specified
    private func configureAccurateConfirmationRequest() {
        accurateConfirmationRequest.recognitionLevel = .accurate // Phase 3: Accurate mode
        accurateConfirmationRequest.usesLanguageCorrection = false // Phase 3: No autocorrect on serials
        accurateConfirmationRequest.recognitionLanguages = ["en-US"] // Phase 3: Minimal set as specified
        accurateConfirmationRequest.minimumTextHeight = 0.01 // Lower threshold for accuracy
        accurateConfirmationRequest.revision = VNRecognizeTextRequestRevision3
        
        // Phase 3: Optimize for Apple serial number characteristics
        if #available(iOS 16.0, *) {
            accurateConfirmationRequest.automaticallyDetectsLanguage = false
        }
        
        logger.info("Phase 3: Accurate confirmation request configured with minimal language set")
    }
    
    /// Phase 3: Configure high-resolution request for maximum character fidelity
    private func configureHighResolutionRequest() {
        highResolutionRequest.recognitionLevel = .accurate
        highResolutionRequest.usesLanguageCorrection = false // Phase 3: Critical for serials
        highResolutionRequest.recognitionLanguages = ["en-US"] // Phase 3: English-only
        highResolutionRequest.minimumTextHeight = 0.008 // Very low for high-res processing
        highResolutionRequest.revision = VNRecognizeTextRequestRevision3
        
        // Phase 3: Maximum quality settings
        if #available(iOS 15.0, *) {
            // Use latest Vision features for best accuracy
        }
        
        logger.info("Phase 3: High-resolution request configured for maximum fidelity")
    }
    
    // MARK: - Phase 3: OCR Processing Methods
    
    /// Phase 3: Fast OCR for real-time feedback during scanning
    func performFastOCR(
        on image: CIImage,
        roi: CGRect? = nil,
        completion: @escaping (Phase3OCRResult) -> Void
    ) {
        let processingStartTime = CFAbsoluteTimeGetCurrent()
        
        fastProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Apply ROI if specified
                let processedImage = roi != nil ? image.cropped(to: roi!) : image
                
                let handler = VNImageRequestHandler(ciImage: processedImage, options: [:])
                try handler.perform([self.fastRequest])
                
                let candidates = self.extractSerialCandidates(
                    from: self.fastRequest.results ?? [],
                    processingMode: .fast,
                    processingTime: CFAbsoluteTimeGetCurrent() - processingStartTime
                )
                
                let result = Phase3OCRResult(
                    candidates: candidates,
                    processingMode: .fast,
                    processingTime: CFAbsoluteTimeGetCurrent() - processingStartTime,
                    imageResolution: processedImage.extent.size,
                    roiUsed: roi
                )
                
                DispatchQueue.main.async {
                    completion(result)
                }
                
            } catch {
                self.logger.error("Phase 3: Fast OCR failed: \(error.localizedDescription)")
                let errorResult = Phase3OCRResult.error(error, processingTime: CFAbsoluteTimeGetCurrent() - processingStartTime)
                DispatchQueue.main.async {
                    completion(errorResult)
                }
            }
        }
    }
    
    /// Phase 3: Accurate OCR for confirmation frames as specified in the plan
    func performAccurateConfirmationOCR(
        on image: CIImage,
        roi: CGRect,
        completion: @escaping (Phase3OCRResult) -> Void
    ) {
        let processingStartTime = CFAbsoluteTimeGetCurrent()
        
        accurateProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Phase 3: Use full-res crop inside ROI to maximize character fidelity
                let fullResROIImage = self.extractFullResolutionROI(from: image, roi: roi)
                
                let handler = VNImageRequestHandler(ciImage: fullResROIImage, options: [:])
                try handler.perform([self.accurateConfirmationRequest])
                
                let candidates = self.extractSerialCandidates(
                    from: self.accurateConfirmationRequest.results ?? [],
                    processingMode: .accurateConfirmation,
                    processingTime: CFAbsoluteTimeGetCurrent() - processingStartTime
                )
                
                let result = Phase3OCRResult(
                    candidates: candidates,
                    processingMode: .accurateConfirmation,
                    processingTime: CFAbsoluteTimeGetCurrent() - processingStartTime,
                    imageResolution: fullResROIImage.extent.size,
                    roiUsed: roi
                )
                
                self.logger.info("Phase 3: Accurate confirmation OCR completed - \(candidates.count) candidates found")
                
                DispatchQueue.main.async {
                    completion(result)
                }
                
            } catch {
                self.logger.error("Phase 3: Accurate confirmation OCR failed: \(error.localizedDescription)")
                let errorResult = Phase3OCRResult.error(error, processingTime: CFAbsoluteTimeGetCurrent() - processingStartTime)
                DispatchQueue.main.async {
                    completion(errorResult)
                }
            }
        }
    }
    
    /// Phase 3: High-resolution OCR for final validation with maximum character fidelity
    func performHighResolutionOCR(
        on image: CIImage,
        roi: CGRect,
        completion: @escaping (Phase3OCRResult) -> Void
    ) {
        let processingStartTime = CFAbsoluteTimeGetCurrent()
        
        confirmationProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Phase 3: Multi-scale processing for maximum accuracy
                var allCandidates: [Phase3SerialCandidate] = []
                
                for scaleFactor in self.imageScaleFactors {
                    let scaledImage = self.scaleImageForOptimalOCR(image, roi: roi, scaleFactor: scaleFactor)
                    
                    let handler = VNImageRequestHandler(ciImage: scaledImage, options: [:])
                    try handler.perform([self.highResolutionRequest])
                    
                    let scaleCandidates = self.extractSerialCandidates(
                        from: self.highResolutionRequest.results ?? [],
                        processingMode: .highResolution,
                        processingTime: CFAbsoluteTimeGetCurrent() - processingStartTime,
                        scaleFactor: scaleFactor
                    )
                    
                    allCandidates.append(contentsOf: scaleCandidates)
                }
                
                // Phase 3: Merge and rank candidates from different scales
                let mergedCandidates = self.mergeMultiScaleCandidates(allCandidates)
                
                let result = Phase3OCRResult(
                    candidates: mergedCandidates,
                    processingMode: .highResolution,
                    processingTime: CFAbsoluteTimeGetCurrent() - processingStartTime,
                    imageResolution: image.extent.size,
                    roiUsed: roi
                )
                
                self.logger.info("Phase 3: High-resolution OCR completed with \(mergedCandidates.count) merged candidates")
                
                DispatchQueue.main.async {
                    completion(result)
                }
                
            } catch {
                self.logger.error("Phase 3: High-resolution OCR failed: \(error.localizedDescription)")
                let errorResult = Phase3OCRResult.error(error, processingTime: CFAbsoluteTimeGetCurrent() - processingStartTime)
                DispatchQueue.main.async {
                    completion(errorResult)
                }
            }
        }
    }
    
    // MARK: - Phase 3: Image Processing for Maximum Fidelity
    
    /// Phase 3: Extract full-resolution ROI as specified in the plan
    private func extractFullResolutionROI(from image: CIImage, roi: CGRect) -> CIImage {
        // Convert normalized ROI to image coordinates
        let imageSize = image.extent.size
        let roiRect = CGRect(
            x: roi.origin.x * imageSize.width,
            y: roi.origin.y * imageSize.height,
            width: roi.width * imageSize.width,
            height: roi.height * imageSize.height
        )
        
        // Phase 3: Crop to ROI without downscaling to maximize character fidelity
        let croppedImage = image.cropped(to: roiRect)
        
        // Apply serial number-specific image enhancements
        return enhanceImageForSerialRecognition(croppedImage)
    }
    
    /// Phase 3: Scale image for optimal OCR processing
    private func scaleImageForOptimalOCR(_ image: CIImage, roi: CGRect, scaleFactor: CGFloat) -> CIImage {
        let roiImage = extractFullResolutionROI(from: image, roi: roi)
        
        // Scale image while maintaining aspect ratio
        let transform = CGAffineTransform(scaleX: scaleFactor, y: scaleFactor)
        return roiImage.transformed(by: transform)
    }
    
    /// Phase 3: Enhance image specifically for Apple serial number recognition
    private func enhanceImageForSerialRecognition(_ image: CIImage) -> CIImage {
        // Apply contrast enhancement for better character definition
        let contrastFilter = CIFilter(name: "CIColorControls")!
        contrastFilter.setValue(image, forKey: kCIInputImageKey)
        contrastFilter.setValue(1.2, forKey: kCIInputContrastKey) // Slight contrast boost
        contrastFilter.setValue(1.0, forKey: kCIInputSaturationKey) // Keep saturation
        contrastFilter.setValue(0.05, forKey: kCIInputBrightnessKey) // Slight brightness boost
        
        guard let enhancedImage = contrastFilter.outputImage else { return image }
        
        // Apply sharpening for better character edges
        let sharpenFilter = CIFilter(name: "CISharpenLuminance")!
        sharpenFilter.setValue(enhancedImage, forKey: kCIInputImageKey)
        sharpenFilter.setValue(0.4, forKey: kCIInputSharpnessKey) // Moderate sharpening
        
        return sharpenFilter.outputImage ?? enhancedImage
    }
    
    // MARK: - Phase 3: Serial Candidate Extraction
    
    /// Extract and validate Apple serial number candidates with Phase 3 optimizations
    private func extractSerialCandidates(
        from observations: [VNRecognizedTextObservation],
        processingMode: Phase3ProcessingMode,
        processingTime: TimeInterval,
        scaleFactor: CGFloat = 1.0
    ) -> [Phase3SerialCandidate] {
        
        var candidates: [Phase3SerialCandidate] = []
        
        for observation in observations {
            for (rank, recognizedText) in observation.topCandidates(5).enumerated() {
                let rawText = recognizedText.string
                let cleanedText = cleanTextForAppleSerial(rawText)
                
                // Phase 3: Apply Apple serial validation
                guard isValidAppleSerialPattern(cleanedText) else { continue }
                
                // Phase 3: Calculate confidence with processing mode weighting
                let confidence = calculatePhase3Confidence(
                    text: cleanedText,
                    visionConfidence: recognizedText.confidence,
                    processingMode: processingMode,
                    scaleFactor: scaleFactor
                )
                
                let candidate = Phase3SerialCandidate(
                    text: cleanedText,
                    confidence: confidence,
                    boundingBox: observation.boundingBox,
                    processingMode: processingMode,
                    rank: rank,
                    processingTime: processingTime,
                    scaleFactor: scaleFactor,
                    rawText: rawText
                )
                
                candidates.append(candidate)
            }
        }
        
        // Sort by confidence and return top candidates
        return candidates.sorted { $0.confidence > $1.confidence }
    }
    
    /// Phase 3: Clean text specifically for Apple serial numbers
    private func cleanTextForAppleSerial(_ text: String) -> String {
        return text
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "|", with: "1") // Common OCR error
            .replacingOccurrences(of: "O", with: "0") // Common confusion
            .replacingOccurrences(of: "S", with: "5") // In serial contexts
    }
    
    /// Phase 3: Validate Apple serial patterns with enhanced checking
    private func isValidAppleSerialPattern(_ text: String) -> Bool {
        // Length validation
        guard text.count >= 8 && text.count <= 15 else { return false }
        
        // Alphanumeric only
        let alphanumericSet = CharacterSet.alphanumerics
        guard text.unicodeScalars.allSatisfy({ alphanumericSet.contains($0) }) else { return false }
        
        // Phase 3: Enhanced Apple serial patterns
        let patterns = [
            "^[A-Z]{1,3}[A-Z0-9]{8,12}$",    // General Apple format
            "^[A-Z0-9]{10,12}$",             // Newer format
            "^[0-9A-Z]{10}$",                // Exact 10 chars
            "^[A-Z]{2}[0-9]{8}$",            // Legacy format
            "^[FCDGHJKMNPQRTVWXY].*$"        // Common Apple prefixes
        ]
        
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }
    
    /// Phase 3: Calculate confidence with processing mode weighting
    private func calculatePhase3Confidence(
        text: String,
        visionConfidence: Float,
        processingMode: Phase3ProcessingMode,
        scaleFactor: CGFloat
    ) -> Float {
        var confidence = visionConfidence
        
        // Phase 3: Processing mode confidence adjustment
        switch processingMode {
        case .fast:
            confidence *= 0.9 // Slight penalty for fast mode
        case .accurateConfirmation:
            confidence *= 1.1 // Bonus for accurate mode
        case .highResolution:
            confidence *= 1.2 // Higher bonus for high-res mode
        }
        
        // Scale factor adjustment
        if scaleFactor > 1.0 {
            confidence += Float((scaleFactor - 1.0) * 0.05) // Bonus for higher resolution
        }
        
        // Apple serial pattern bonus
        if text.count == 10 || text.count == 11 || text.count == 12 {
            confidence += 0.1
        }
        
        // Strong pattern bonus
        if text.range(of: "^[A-Z]{1,3}[A-Z0-9]{8,10}$", options: .regularExpression) != nil {
            confidence += 0.15
        }
        
        return min(confidence, 1.0)
    }
    
    /// Phase 3: Merge candidates from multi-scale processing
    private func mergeMultiScaleCandidates(_ candidates: [Phase3SerialCandidate]) -> [Phase3SerialCandidate] {
        var textToCandidate: [String: Phase3SerialCandidate] = [:]
        
        for candidate in candidates {
            if let existing = textToCandidate[candidate.text] {
                // Keep the candidate with higher confidence
                if candidate.confidence > existing.confidence {
                    textToCandidate[candidate.text] = candidate
                }
            } else {
                textToCandidate[candidate.text] = candidate
            }
        }
        
        return Array(textToCandidate.values).sorted { $0.confidence > $1.confidence }
    }
    
    // MARK: - Configuration Updates
    
    /// Update ROI for processing
    func updateROI(_ roi: CGRect) {
        currentROI = roi
        logger.debug("Phase 3: ROI updated to \(roi)")
    }
}

// MARK: - Phase 3: Supporting Types

enum Phase3ProcessingMode: String, CaseIterable {
    case fast = "fast"
    case accurateConfirmation = "accurate_confirmation"
    case highResolution = "high_resolution"
}

struct Phase3SerialCandidate {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
    let processingMode: Phase3ProcessingMode
    let rank: Int
    let processingTime: TimeInterval
    let scaleFactor: CGFloat
    let rawText: String
}

struct Phase3OCRResult {
    let candidates: [Phase3SerialCandidate]
    let processingMode: Phase3ProcessingMode
    let processingTime: TimeInterval
    let imageResolution: CGSize
    let roiUsed: CGRect?
    let error: Error?
    
    init(
        candidates: [Phase3SerialCandidate],
        processingMode: Phase3ProcessingMode,
        processingTime: TimeInterval,
        imageResolution: CGSize,
        roiUsed: CGRect?
    ) {
        self.candidates = candidates
        self.processingMode = processingMode
        self.processingTime = processingTime
        self.imageResolution = imageResolution
        self.roiUsed = roiUsed
        self.error = nil
    }
    
    static func error(_ error: Error, processingTime: TimeInterval) -> Phase3OCRResult {
        return Phase3OCRResult(
            candidates: [],
            processingMode: .fast,
            processingTime: processingTime,
            imageResolution: .zero,
            roiUsed: nil,
            error: error
        )
    }
    
    var isSuccess: Bool {
        return error == nil && !candidates.isEmpty
    }
    
    var bestCandidate: Phase3SerialCandidate? {
        return candidates.first
    }
}
