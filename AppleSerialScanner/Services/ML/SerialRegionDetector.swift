import CoreML
import Vision
import CoreImage
import os.log

/// Serial Region Detector using Core ML to localize serial number areas on device surfaces
@available(iOS 13.0, *)
public final class SerialRegionDetector: ObservableObject {
    
    // MARK: - Properties
    private let logger = Logger(subsystem: "AppleSerialScanner", category: "SerialRegionDetector")
    private var model: MLModel?
    private let kalmanFilter: KalmanFilter2D
    
    // MARK: - Configuration
    public struct DetectionConfiguration {
        let confidenceThreshold: Float
        let nmsThreshold: Float
        let maxDetections: Int
        let stabilizationFrames: Int
        let expansionFactor: Float
        
        public static let `default` = DetectionConfiguration(
            confidenceThreshold: 0.5,
            nmsThreshold: 0.4,
            maxDetections: 5,
            stabilizationFrames: 3,
            expansionFactor: 0.1
        )
        
        public static let strict = DetectionConfiguration(
            confidenceThreshold: 0.7,
            nmsThreshold: 0.3,
            maxDetections: 3,
            stabilizationFrames: 5,
            expansionFactor: 0.05
        )
    }
    
    @Published public var configuration = DetectionConfiguration.default
    @Published public var isModelLoaded = false
    @Published public var lastDetectionTime: TimeInterval = 0
    
    // MARK: - Detection Results
    public struct DetectionResult {
        let boundingBoxes: [CGRect]
        let confidences: [Float]
        let stabilizedROI: CGRect?
        let detectionTime: TimeInterval
        let frameStability: Float
    }
    
    // MARK: - Private State
    private var recentDetections: [DetectionResult] = []
    private var frameCount: Int = 0
    
    public init() {
        self.kalmanFilter = KalmanFilter2D()
        Task {
            await loadModel()
        }
    }
    
    // MARK: - Model Loading
    
    @MainActor
    private func loadModel() async {
        do {
            self.model = try await MLModelLoader.shared.loadSerialRegionDetector()
            self.isModelLoaded = true
            logger.info("Serial Region Detector model loaded successfully")
        } catch {
            logger.error("Failed to load Serial Region Detector: \(error.localizedDescription)")
            self.isModelLoaded = false
        }
    }
    
    // MARK: - Main Detection Pipeline
    
    /// Detect serial regions in the provided image buffer
    public func detectSerialRegions(
        in pixelBuffer: CVPixelBuffer,
        imageSize: CGSize
    ) async throws -> DetectionResult {
        
        guard let model = self.model else {
            throw MLModelError.modelNotFound("SerialRegionDetector not loaded")
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Preprocess image for detection model
        let preprocessedBuffer = try await preprocessImageForDetection(pixelBuffer)
        
        // Run Core ML prediction
        let prediction = try await runDetectionPrediction(model: model, input: preprocessedBuffer)
        
        // Post-process results
        let processedResults = try processDetectionResults(
            prediction: prediction,
            originalImageSize: imageSize
        )
        
        // Apply temporal stabilization
        let stabilizedROI = applyTemporalStabilization(
            newDetections: processedResults.boundingBoxes,
            confidences: processedResults.confidences
        )
        
        let detectionTime = CFAbsoluteTimeGetCurrent() - startTime
        await MainActor.run {
            self.lastDetectionTime = detectionTime
        }
        
        let result = DetectionResult(
            boundingBoxes: processedResults.boundingBoxes,
            confidences: processedResults.confidences,
            stabilizedROI: stabilizedROI,
            detectionTime: detectionTime,
            frameStability: calculateFrameStability()
        )
        
        // Store for temporal analysis
        updateDetectionHistory(result)
        
        logger.debug("Detection completed in \(String(format: "%.1f", detectionTime * 1000))ms")
        return result
    }
    
    /// Fuse detection results with Vision text observations
    public func fuseWithVisionResults(
        detectionResult: DetectionResult,
        visionObservations: [VNRecognizedTextObservation],
        imageSize: CGSize
    ) -> DetectionResult {
        
        var fusedBoxes: [CGRect] = []
        var fusedConfidences: [Float] = []
        
        // Convert Vision observations to CGRect
        let textBoxes = visionObservations.compactMap { observation -> CGRect? in
            let boundingBox = observation.boundingBox
            // Convert from Vision normalized coordinates to pixel coordinates
            return MLUtils.denormalizeRect(
                MLUtils.convertVisionToUIKit(boundingBox, imageHeight: imageSize.height),
                imageSize: imageSize
            )
        }
        
        // Find intersections between ML detections and Vision text
        for (index, detectionBox) in detectionResult.boundingBoxes.enumerated() {
            let confidence = detectionResult.confidences[index]
            
            // Check if detection box intersects with any text observation
            let hasTextIntersection = textBoxes.contains { textBox in
                let iou = MLUtils.calculateIoU(detectionBox, textBox)
                return iou > 0.3 // Minimum intersection threshold
            }
            
            if hasTextIntersection {
                fusedBoxes.append(detectionBox)
                fusedConfidences.append(confidence * 1.2) // Boost confidence for text-intersecting regions
            }
        }
        
        // Apply geometry gates
        let (filteredBoxes, filteredConfidences) = applyGeometryGates(
            boxes: fusedBoxes,
            confidences: fusedConfidences,
            imageSize: imageSize
        )
        
        return DetectionResult(
            boundingBoxes: filteredBoxes,
            confidences: filteredConfidences,
            stabilizedROI: detectionResult.stabilizedROI,
            detectionTime: detectionResult.detectionTime,
            frameStability: detectionResult.frameStability
        )
    }
    
    // MARK: - Private Implementation
    
    private func preprocessImageForDetection(_ pixelBuffer: CVPixelBuffer) async throws -> CVPixelBuffer {
        // Resize to model input size (416x416)
        let targetSize = CGSize(width: 416, height: 416)
        
        guard let resizedBuffer = MLUtils.scalePixelBufferWithLetterboxing(
            pixelBuffer,
            to: targetSize,
            fillColor: CGColor(gray: 0, alpha: 1)
        ) else {
            throw MLModelError.invalidInput("Failed to resize image for detection")
        }
        
        return resizedBuffer
    }
    
    private func runDetectionPrediction(model: MLModel, input: CVPixelBuffer) async throws -> MLFeatureProvider {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let inputFeatures = try MLDictionaryFeatureProvider(dictionary: [
                    CoreMLModelDefinitions.SerialRegionDetector.inputName: MLFeatureValue(pixelBuffer: input)
                ])
                
                let prediction = try model.prediction(from: inputFeatures)
                continuation.resume(returning: prediction)
            } catch {
                continuation.resume(throwing: MLModelError.predictionFailed("SerialRegionDetector", error))
            }
        }
    }
    
    private func processDetectionResults(
        prediction: MLFeatureProvider,
        originalImageSize: CGSize
    ) throws -> (boundingBoxes: [CGRect], confidences: [Float]) {
        
        // Extract model outputs
        guard let boundingBoxesArray = prediction.featureValue(for: CoreMLModelDefinitions.SerialRegionDetector.outputBoundingBoxes)?.multiArrayValue,
              let confidencesArray = prediction.featureValue(for: CoreMLModelDefinitions.SerialRegionDetector.outputConfidences)?.multiArrayValue else {
            throw MLModelError.invalidInput("Invalid detection model output")
        }
        
        // Convert MLMultiArray to Swift arrays
        let boxes = extractBoundingBoxes(from: boundingBoxesArray, imageSize: originalImageSize)
        let confidences = MLUtils.extractFloatArray(from: confidencesArray)
        
        // Apply confidence threshold
        let validIndices = confidences.enumerated().compactMap { index, confidence in
            confidence >= configuration.confidenceThreshold ? index : nil
        }
        
        let filteredBoxes = validIndices.map { boxes[$0] }
        let filteredConfidences = validIndices.map { confidences[$0] }
        
        // Apply Non-Maximum Suppression
        let nmsIndices = MLUtils.nonMaximumSuppression(
            boxes: filteredBoxes,
            scores: filteredConfidences,
            iouThreshold: configuration.nmsThreshold,
            scoreThreshold: configuration.confidenceThreshold
        )
        
        let finalBoxes = nmsIndices.map { filteredBoxes[$0] }
        let finalConfidences = nmsIndices.map { filteredConfidences[$0] }
        
        return (finalBoxes, finalConfidences)
    }
    
    private func extractBoundingBoxes(from multiArray: MLMultiArray, imageSize: CGSize) -> [CGRect] {
        let pointer = UnsafePointer<Float>(OpaquePointer(multiArray.dataPointer))
        let shape = multiArray.shape
        
        guard shape.count >= 2, shape[1].intValue >= 4 else {
            logger.error("Invalid bounding box array shape")
            return []
        }
        
        let numBoxes = shape[0].intValue
        var boxes: [CGRect] = []
        
        for i in 0..<numBoxes {
            let baseIndex = i * 4
            
            // Model outputs normalized coordinates [x_center, y_center, width, height]
            let xCenter = CGFloat(pointer[baseIndex])
            let yCenter = CGFloat(pointer[baseIndex + 1])
            let width = CGFloat(pointer[baseIndex + 2])
            let height = CGFloat(pointer[baseIndex + 3])
            
            // Convert to corner coordinates
            let x = (xCenter - width / 2) * imageSize.width
            let y = (yCenter - height / 2) * imageSize.height
            let w = width * imageSize.width
            let h = height * imageSize.height
            
            let box = CGRect(x: x, y: y, width: w, height: h)
            boxes.append(box)
        }
        
        return boxes
    }
    
    private func applyGeometryGates(
        boxes: [CGRect],
        confidences: [Float],
        imageSize: CGSize
    ) -> ([CGRect], [Float]) {
        
        var validBoxes: [CGRect] = []
        var validConfidences: [Float] = []
        
        for (index, box) in boxes.enumerated() {
            let confidence = confidences[index]
            
            // Calculate normalized dimensions
            let normalizedWidth = box.width / imageSize.width
            let normalizedHeight = box.height / imageSize.height
            let aspectRatio = box.width / box.height
            
            // Apply geometry gates from Phase 2
            let validAspectRatio = aspectRatio >= 7.5 && aspectRatio <= 20.0
            let validHeight = normalizedHeight >= 0.012 && normalizedHeight <= 0.05
            let validSize = box.width > 50 && box.height > 5 // Minimum pixel size
            
            if validAspectRatio && validHeight && validSize {
                validBoxes.append(box)
                validConfidences.append(confidence)
            }
        }
        
        return (validBoxes, validConfidences)
    }
    
    private func applyTemporalStabilization(
        newDetections: [CGRect],
        confidences: [Float]
    ) -> CGRect? {
        
        guard !newDetections.isEmpty else { return nil }
        
        // Find best detection (highest confidence)
        let bestIndex = confidences.enumerated().max { $0.element < $1.element }?.offset ?? 0
        let bestDetection = newDetections[bestIndex]
        
        // Update Kalman filter
        let centerX = bestDetection.midX
        let centerY = bestDetection.midY
        let updatedCenter = kalmanFilter.update(measurement: CGPoint(x: centerX, y: centerY))
        
        // Create stabilized ROI
        let stabilizedROI = CGRect(
            x: updatedCenter.x - bestDetection.width / 2,
            y: updatedCenter.y - bestDetection.height / 2,
            width: bestDetection.width,
            height: bestDetection.height
        )
        
        // Expand slightly for better coverage
        let expandedROI = stabilizedROI.expanded(by: 1.0 + CGFloat(configuration.expansionFactor))
        
        return expandedROI
    }
    
    private func calculateFrameStability() -> Float {
        guard recentDetections.count >= 2 else { return 0.0 }
        
        let recent = Array(recentDetections.suffix(3))
        var totalVariation: Float = 0.0
        
        for i in 1..<recent.count {
            guard let currentROI = recent[i].stabilizedROI,
                  let previousROI = recent[i-1].stabilizedROI else { continue }
            
            let centerVariation = sqrt(
                pow(Float(currentROI.midX - previousROI.midX), 2) +
                pow(Float(currentROI.midY - previousROI.midY), 2)
            )
            
            totalVariation += centerVariation
        }
        
        // Convert to stability score (higher is more stable)
        let avgVariation = totalVariation / Float(recent.count - 1)
        return max(0.0, 1.0 - avgVariation / 100.0) // Normalize to 0-1
    }
    
    private func updateDetectionHistory(_ result: DetectionResult) {
        frameCount += 1
        recentDetections.append(result)
        
        // Keep only recent frames for temporal analysis
        if recentDetections.count > configuration.stabilizationFrames {
            recentDetections.removeFirst()
        }
    }
    
    // MARK: - Public Interface
    
    /// Reset temporal state (call when starting new scan session)
    public func resetTemporalState() {
        recentDetections.removeAll()
        frameCount = 0
        kalmanFilter.reset()
        logger.debug("Temporal state reset")
    }
    
    /// Get performance metrics for analytics
    public func getPerformanceMetrics() -> [String: Any] {
        return [
            "model_loaded": isModelLoaded,
            "frame_count": frameCount,
            "avg_detection_time": lastDetectionTime,
            "recent_detections_count": recentDetections.count,
            "frame_stability": recentDetections.last?.frameStability ?? 0.0
        ]
    }
}

// MARK: - Kalman Filter for Temporal Stabilization

private class KalmanFilter2D {
    private var stateX: Float = 0  // x position
    private var stateY: Float = 0  // y position
    private var velocityX: Float = 0
    private var velocityY: Float = 0
    
    private let processNoise: Float = 0.1
    private let measurementNoise: Float = 1.0
    private var estimateErrorX: Float = 1.0
    private var estimateErrorY: Float = 1.0
    
    func update(measurement: CGPoint) -> CGPoint {
        // Simplified 2D Kalman filter
        let measurementX = Float(measurement.x)
        let measurementY = Float(measurement.y)
        
        // Prediction step
        stateX += velocityX
        stateY += velocityY
        estimateErrorX += processNoise
        estimateErrorY += processNoise
        
        // Update step
        let kalmanGainX = estimateErrorX / (estimateErrorX + measurementNoise)
        let kalmanGainY = estimateErrorY / (estimateErrorY + measurementNoise)
        
        stateX += kalmanGainX * (measurementX - stateX)
        stateY += kalmanGainY * (measurementY - stateY)
        
        estimateErrorX *= (1 - kalmanGainX)
        estimateErrorY *= (1 - kalmanGainY)
        
        // Update velocity (simple difference)
        velocityX = kalmanGainX * (measurementX - stateX)
        velocityY = kalmanGainY * (measurementY - stateY)
        
        return CGPoint(x: CGFloat(stateX), y: CGFloat(stateY))
    }
    
    func reset() {
        stateX = 0
        stateY = 0
        velocityX = 0
        velocityY = 0
        estimateErrorX = 1.0
        estimateErrorY = 1.0
    }
}
