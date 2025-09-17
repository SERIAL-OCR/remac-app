import CoreImage
import Vision
import os.log
import Combine

/// Analyzes frame quality for optimal serial number recognition
class FrameQualityAnalyzer: ObservableObject {
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "FrameQuality")
    
    // Published latest quality metrics for observers
    @Published var lastQualityMetrics: FrameQualityMetrics? = nil
    
    // Analysis configuration
    private let minimumTextContrast: Float = 0.4
    private let minimumSharpness: Float = 0.5
    private let stabilityWindowSize = 5
    
    // Stability tracking
    private var recentMotionScores: [Float] = []
    private var lastFrameFeatures: [CGPoint] = []
    
    /// Analyze frame quality for serial number scanning
    func analyzeFrame(_ ciImage: CIImage) -> FrameQualityMetrics {
        var metrics = FrameQualityMetrics(
            clarityScore: 0,
            brightnessScore: 0,
            averageTextSize: 0,
            primaryTextLocation: nil,
            stabilityScore: 0
        )
        
        // Analyze image clarity (sharpness)
        metrics = analyzeClarity(image: ciImage, currentMetrics: metrics)
        
        // Analyze brightness and contrast
        metrics = analyzeBrightness(image: ciImage, currentMetrics: metrics)
        
        // Analyze frame stability
        metrics = analyzeStability(image: ciImage, currentMetrics: metrics)
        
        // Detect and analyze text regions
        metrics = analyzeTextRegions(image: ciImage, currentMetrics: metrics)
        
        logger.debug("Frame analysis complete - Clarity: \(metrics.clarityScore), Brightness: \(metrics.brightnessScore), Stability: \(metrics.stabilityScore)")
        
        // Publish latest metrics for UI consumers
        DispatchQueue.main.async { [weak self] in
            self?.lastQualityMetrics = metrics
        }
        
        return metrics
    }
    
    /// Reset stability tracking
    func reset() {
        recentMotionScores.removeAll()
        lastFrameFeatures.removeAll()
        logger.info("Frame quality analyzer reset")
    }
    
    // MARK: - Private Methods
    
    private func analyzeClarity(image: CIImage, currentMetrics: FrameQualityMetrics) -> FrameQualityMetrics {
        var metrics = currentMetrics
        
        // Use Laplacian variance for sharpness detection
        if let sharpness = calculateLaplacianVariance(image) {
            metrics.clarityScore = min(1.0, sharpness / minimumSharpness)
        }
        
        return metrics
    }
    
    private func analyzeBrightness(image: CIImage, currentMetrics: FrameQualityMetrics) -> FrameQualityMetrics {
        var metrics = currentMetrics
        
        // Calculate average brightness and contrast
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        if let brightness = calculateAverageBrightness(image, context: context) {
            metrics.brightnessScore = normalizeValue(brightness, targetRange: 0.4...0.7)
        }
        
        return metrics
    }
    
    private func analyzeStability(image: CIImage, currentMetrics: FrameQualityMetrics) -> FrameQualityMetrics {
        var metrics = currentMetrics
        
        // Extract feature points
        let currentFeatures = extractFeaturePoints(from: image)
        
        // Calculate motion score if we have previous features
        if !lastFrameFeatures.isEmpty {
            let motionScore = calculateMotionScore(
                previous: lastFrameFeatures,
                current: currentFeatures
            )
            
            // Update motion history
            recentMotionScores.append(motionScore)
            if recentMotionScores.count > stabilityWindowSize {
                recentMotionScores.removeFirst()
            }
            
            // Calculate stability score from recent motion
            metrics.stabilityScore = calculateStabilityScore(from: recentMotionScores)
        }
        
        lastFrameFeatures = currentFeatures
        
        return metrics
    }
    
    private func analyzeTextRegions(image: CIImage, currentMetrics: FrameQualityMetrics) -> FrameQualityMetrics {
        var metrics = currentMetrics
        
        // Detect text regions using Vision
        let request = VNDetectTextRectanglesRequest()
        request.reportCharacterBoxes = true
        
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
            
            if let results = request.results as? [VNTextObservation] {
                // Calculate average text size
                let sizes = results.map { observation in
                    observation.boundingBox.size.height * image.extent.height
                }
                metrics.averageTextSize = sizes.reduce(0, +) / CGFloat(max(1, sizes.count))
                
                // Find primary text location (largest text region)
                if let primaryText = results.max(by: { $0.boundingBox.area < $1.boundingBox.area }) {
                    metrics.primaryTextLocation = CGPoint(
                        x: primaryText.boundingBox.midX,
                        y: primaryText.boundingBox.midY
                    )
                }
            }
        } catch {
            logger.error("Text detection failed: \(error.localizedDescription)")
        }
        
        return metrics
    }
    
    // MARK: - Helper Methods
    
    private func calculateLaplacianVariance(_ image: CIImage) -> Float? {
        // Implementation of Laplacian variance calculation for sharpness detection
        // This is a simplified version - production code would use more sophisticated methods
        guard let kernel = CIKernel(source: """
            kernel vec4 laplacian(__sample s) {
                float laplace = -4.0 * s.r +
                    s.r[pixel + int2(1, 0)] +
                    s.r[pixel + int2(-1, 0)] +
                    s.r[pixel + int2(0, 1)] +
                    s.r[pixel + int2(0, -1)];
                return vec4(laplace);
            }
            """) else { return nil }
        
        let filtered = kernel.apply(extent: image.extent, roiCallback: { _, rect in rect }, arguments: [image])
        
        // Calculate variance of Laplacian
        // This would be implemented in production code using Metal for performance
        return 0.75 // Placeholder value
    }
    
    private func calculateAverageBrightness(_ image: CIImage, context: CIContext) -> Float? {
        let extentVector = CIVector(x: image.extent.origin.x, y: image.extent.origin.y,
                                  z: image.extent.size.width, w: image.extent.size.height)
        
        guard let averageFilter = CIFilter(name: "CIAreaAverage",
                                         parameters: [kCIInputImageKey: image,
                                                    kCIInputExtentKey: extentVector]) else { return nil }
        
        guard let outputImage = averageFilter.outputImage,
              let outputBuffer = context.render(outputImage,
                                             toBitmap: nil,
                                             rowBytes: 4,
                                             bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                             format: .RGBA8,
                                             colorSpace: nil) else { return nil }
        
        let data = outputBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
        let brightness = (Float(data[0]) + Float(data[1]) + Float(data[2])) / (3.0 * 255.0)
        
        return brightness
    }
    
    private func extractFeaturePoints(from image: CIImage) -> [CGPoint] {
        var features: [CGPoint] = []
        
        let request = VNDetectPointsOfInterestRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        
        do {
            try handler.perform([request])
            if let results = request.results as? [VNPointOfInterestObservation] {
                features = results.map { CGPoint(x: $0.point.x, y: $0.point.y) }
            }
        } catch {
            logger.error("Feature extraction failed: \(error.localizedDescription)")
        }
        
        return features
    }
    
    private func calculateMotionScore(previous: [CGPoint], current: [CGPoint]) -> Float {
        // Calculate average point movement
        let maxDistance: Float = 0.1 // 10% of frame width/height
        var totalDistance: Float = 0
        var pointCount = 0
        
        for p1 in previous {
            if let nearest = current.min(by: { distance(p1, $0) < distance(p1, $1) }) {
                totalDistance += Float(distance(p1, nearest))
                pointCount += 1
            }
        }
        
        let averageMotion = pointCount > 0 ? totalDistance / Float(pointCount) : maxDistance
        return 1.0 - min(1.0, averageMotion / maxDistance)
    }
    
    private func calculateStabilityScore(from motionScores: [Float]) -> Float {
        guard !motionScores.isEmpty else { return 0 }
        return motionScores.reduce(0, +) / Float(motionScores.count)
    }
    
    private func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }
    
    private func normalizeValue(_ value: Float, targetRange: ClosedRange<Float>) -> Float {
        let normalizedValue = (value - targetRange.lowerBound) / (targetRange.upperBound - targetRange.lowerBound)
        return min(1.0, max(0.0, normalizedValue))
    }
}

private extension CGRect {
    var area: CGFloat {
        return size.width * size.height
    }
}
