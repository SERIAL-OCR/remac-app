import Foundation
import Vision
import CoreImage
import AVFoundation
import os.log

/// Detects screen rectangles in camera frames and provides perspective-rectified ROI
@available(iOS 13.0, *)
class ScreenDetector {
    // MARK: - Properties
    private let rectangleRequest: VNDetectRectanglesRequest
    private var lastDetectedROI: CGRect?
    private var lastDetectedQuad: VNRectangleObservation?
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "ScreenDetector")
    
    // Configuration
    private let minimumConfidence: Float = 0.75
    private let minimumAspectRatio: Float = 1.2
    private let maximumAspectRatio: Float = 2.5
    private let minimumSize: Float = 0.12
    private let safeMargin: CGFloat = 0.05 // 5% margin around detected rectangle
    
    // Performance tracking
    private var detectionHistory: [ScreenDetectionResult] = []
    private let maxHistorySize = 10
    
    // Last detection results for stability analysis
    private var lastDetectionResults: [ScreenDetectionResult] = []
    
    init() {
        rectangleRequest = VNDetectRectanglesRequest()
        configureRectangleRequest()
    }
    
    private func configureRectangleRequest() {
        rectangleRequest.minimumConfidence = minimumConfidence
        rectangleRequest.minimumAspectRatio = VNAspectRatio(minimumAspectRatio)
        rectangleRequest.maximumAspectRatio = VNAspectRatio(maximumAspectRatio)
        rectangleRequest.minimumSize = minimumSize
        rectangleRequest.maximumObservations = 5
        rectangleRequest.quadratureTolerance = 15.0 // Allow slight perspective distortion
    }
    
    /// Detects screen rectangle and returns perspective-rectified ROI
    func detectScreenROI(in pixelBuffer: CVPixelBuffer) -> ScreenDetectionResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        do {
            try requestHandler.perform([rectangleRequest])
            
            guard let observations = rectangleRequest.results,
                  !observations.isEmpty else {
                // No screen detected, use fallback ROI
                return createFallbackResult(processingTime: CFAbsoluteTimeGetCurrent() - startTime)
            }
            
            // Find the best screen candidate
            let bestObservation = findBestScreenCandidate(observations)
            
            // Create rectified ROI
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let rectifiedImage = createPerspectiveRectifiedROI(from: bestObservation, in: ciImage)
            
            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            
            let result = ScreenDetectionResult(
                isScreenDetected: true,
                roi: bestObservation.boundingBox,
                confidence: bestObservation.confidence,
                processingTime: processingTime
            )
            
            // Update tracking
            updateDetectionHistory(result)
            lastDetectedROI = bestObservation.boundingBox
            lastDetectedQuad = bestObservation
            
            logger.debug("Screen detected with confidence: \(bestObservation.confidence)")
            return result
            
        } catch {
            logger.error("Screen detection failed: \(error.localizedDescription)")
            return createFallbackResult(processingTime: CFAbsoluteTimeGetCurrent() - startTime)
        }
    }
    
    private func findBestScreenCandidate(_ observations: [VNRectangleObservation]) -> VNRectangleObservation {
        // Score candidates based on confidence, size, and aspect ratio
        let scoredObservations = observations.compactMap { observation -> (VNRectangleObservation, Float)? in
            let boundingBox = observation.boundingBox
            let aspectRatio = Float(boundingBox.width / boundingBox.height)
            let sizeScore = Float(boundingBox.width * boundingBox.height)
            
            // Calculate aspect score separately
            let aspectScore: Float
            if aspectRatio > 1.3 && aspectRatio < 2.2 {
                aspectScore = 1.0
            } else {
                aspectScore = 0.5
            }
            
            // Calculate composite score
            let confidenceWeight: Float = 0.6
            let sizeWeight: Float = 0.2
            let aspectWeight: Float = 0.2
            let compositeScore = observation.confidence * confidenceWeight + sizeScore * sizeWeight + aspectScore * aspectWeight
            
            return (observation, compositeScore)
        }
        
        // Find the observation with the highest score
        var bestObservation: VNRectangleObservation? = nil
        var bestScore: Float = -1.0
        
        for (observation, score) in scoredObservations {
            if score > bestScore {
                bestScore = score
                bestObservation = observation
            }
        }
        
        return bestObservation ?? observations.first!
    }
    
    private func createPerspectiveRectifiedROI(from observation: VNRectangleObservation, in image: CIImage) -> CIImage? {
        // Get the four corners of the detected rectangle
        let topLeft = observation.topLeft
        let topRight = observation.topRight
        let bottomLeft = observation.bottomLeft
        let bottomRight = observation.bottomRight
        
        // Convert normalized coordinates to image coordinates
        let imageSize = image.extent.size
        let corners = [
            CGPoint(x: topLeft.x * imageSize.width, y: (1 - topLeft.y) * imageSize.height),
            CGPoint(x: topRight.x * imageSize.width, y: (1 - topRight.y) * imageSize.height),
            CGPoint(x: bottomLeft.x * imageSize.width, y: (1 - bottomLeft.y) * imageSize.height),
            CGPoint(x: bottomRight.x * imageSize.width, y: (1 - bottomRight.y) * imageSize.height)
        ]
        
        // Create perspective correction transform
        guard let perspectiveFilter = CIFilter(name: "CIPerspectiveCorrection") else {
            return cropWithMargin(image, roi: observation.boundingBox)
        }
        
        perspectiveFilter.setValue(image, forKey: kCIInputImageKey)
        perspectiveFilter.setValue(CIVector(cgPoint: corners[0]), forKey: "inputTopLeft")
        perspectiveFilter.setValue(CIVector(cgPoint: corners[1]), forKey: "inputTopRight")
        perspectiveFilter.setValue(CIVector(cgPoint: corners[2]), forKey: "inputBottomLeft")
        perspectiveFilter.setValue(CIVector(cgPoint: corners[3]), forKey: "inputBottomRight")
        
        guard let rectifiedImage = perspectiveFilter.outputImage else {
            return cropWithMargin(image, roi: observation.boundingBox)
        }
        
        return rectifiedImage
    }
    
    private func cropWithMargin(_ image: CIImage, roi: CGRect) -> CIImage {
        // Add safe margin around the ROI
        let imageSize = image.extent.size
        let expandedRect = CGRect(
            x: max(0, roi.origin.x * imageSize.width - safeMargin * imageSize.width),
            y: max(0, (1 - roi.origin.y - roi.height) * imageSize.height - safeMargin * imageSize.height),
            width: min(imageSize.width, roi.width * imageSize.width + 2 * safeMargin * imageSize.width),
            height: min(imageSize.height, roi.height * imageSize.height + 2 * safeMargin * imageSize.height)
        )
        
        return image.cropped(to: expandedRect)
    }
    
    private func createFallbackResult(processingTime: TimeInterval) -> ScreenDetectionResult {
        // Use last known ROI or default center ROI
        let fallbackROI = lastDetectedROI ?? CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        
        return ScreenDetectionResult(
            isScreenDetected: false,
            roi: fallbackROI,
            confidence: 0.0,
            processingTime: processingTime
        )
    }
    
    private func updateDetectionHistory(_ result: ScreenDetectionResult) {
        detectionHistory.append(result)
        
        // Maintain history size limit
        if detectionHistory.count > maxHistorySize {
            detectionHistory.removeFirst()
        }
        
        lastDetectionResults.append(result)
        
        // Maintain history size limit
        if lastDetectionResults.count > maxHistorySize {
            lastDetectionResults.removeFirst()
        }
    }
    
    /// Gets detection stability metrics
    func getDetectionStability() -> DetectionStability {
        guard detectionHistory.count >= 3 else {
            return DetectionStability(isStable: false, averageConfidence: 0.0, consecutiveDetections: 0)
        }
        
        let recent = Array(detectionHistory.suffix(5))
        let detectedCount = recent.filter { $0.isScreenDetected }.count
        let averageConfidence = recent.map { $0.confidence }.reduce(0, +) / Float(recent.count)
        
        return DetectionStability(
            isStable: detectedCount >= 3,
            averageConfidence: averageConfidence,
            consecutiveDetections: detectedCount
        )
    }
    
    /// Reset detection state
    func reset() {
        lastDetectionResults.removeAll()
        logger.debug("ScreenDetector reset")
    }
    
    /// Get recent detection confidence for analytics
    func getRecentDetectionConfidence() -> Float {
        guard !lastDetectionResults.isEmpty else { return 0.0 }
        let recentResults = Array(lastDetectionResults.suffix(5))
        let totalConfidence = recentResults.reduce(0) { $0 + $1.confidence }
        return totalConfidence / Float(recentResults.count)
    }
    
    /// Check if detection is stable
    func isDetectionStable() -> Bool {
        guard lastDetectionResults.count >= 3 else { return false }
        let recentResults = Array(lastDetectionResults.suffix(3))
        let allDetected = recentResults.allSatisfy { $0.isScreenDetected }
        let allNotDetected = recentResults.allSatisfy { !$0.isScreenDetected }
        return allDetected || allNotDetected
    }
}

// MARK: - Supporting Types

struct DetectionStability {
    let isStable: Bool
    let averageConfidence: Float
    let consecutiveDetections: Int
}
