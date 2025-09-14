import Foundation
import CoreImage
import Vision

/// Classifies surface type and determines optimal polarity for OCR preprocessing
class SurfacePolarityClassifier {
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    
    /// Analyzes surface type and returns classification with preprocessing hints
    func classifySurface(image: CIImage) -> SurfaceClassificationResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Convert to grayscale for analysis
        guard let grayscaleFilter = CIFilter(name: "CIColorMonochrome") else {
            return createFallbackResult(processingTime: CFAbsoluteTimeGetCurrent() - startTime)
        }
        
        grayscaleFilter.setValue(image, forKey: kCIInputImageKey)
        grayscaleFilter.setValue(CIColor.white, forKey: kCIInputColorKey)
        grayscaleFilter.setValue(1.0, forKey: kCIInputIntensityKey)
        
        guard let grayscaleImage = grayscaleFilter.outputImage else {
            return createFallbackResult(processingTime: CFAbsoluteTimeGetCurrent() - startTime)
        }
        
        // Sample pixels for histogram analysis
        let sampleSize = CGSize(width: 100, height: 100)
        let scaledImage = grayscaleImage.transformed(by: CGAffineTransform(
            scaleX: sampleSize.width / image.extent.width,
            y: sampleSize.height / image.extent.height
        ))
        
        // Analyze image characteristics
        let characteristics = analyzeImageCharacteristics(scaledImage)
        
        // Classify surface type based on characteristics
        let surfaceType = determineSurfaceType(characteristics)
        let polarityRecommendation = determineOptimalPolarity(characteristics, surfaceType: surfaceType)
        let preprocessingRecommendations = generatePreprocessingRecommendations(characteristics, surfaceType: surfaceType)
        
        return SurfaceClassificationResult(
            surfaceType: surfaceType,
            confidence: characteristics.confidence,
            polarityRecommendation: polarityRecommendation,
            processingTime: CFAbsoluteTimeGetCurrent() - startTime,
            characteristics: characteristics,
            preprocessingRecommendations: preprocessingRecommendations
        )
    }
    
    private func analyzeImageCharacteristics(_ image: CIImage) -> ImageCharacteristics {
        // Calculate histogram and statistics
        let histogram = calculateHistogram(image)
        let edgeDensity = calculateEdgeDensity(image)
        let localContrast = calculateLocalContrast(image)
        let brightness = calculateAverageBrightness(histogram)
        
        // Determine contrast spread
        let contrastSpread = calculateContrastSpread(histogram)
        
        return ImageCharacteristics(
            histogram: histogram,
            edgeDensity: edgeDensity,
            localContrast: localContrast,
            brightness: brightness,
            contrastSpread: contrastSpread,
            confidence: calculateConfidence(
                edgeDensity: edgeDensity,
                contrastSpread: contrastSpread,
                brightness: brightness
            )
        )
    }
    
    private func calculateHistogram(_ image: CIImage) -> [Float] {
        // Simplified histogram calculation
        // In a real implementation, you'd use CIAreaHistogram or manual pixel sampling
        var histogram = Array(repeating: Float(0), count: 256)
        
        // For now, return a mock histogram based on image properties
        // This would be replaced with actual pixel sampling
        let avgBrightness = 0.5 // Placeholder
        let peakIndex = Int(avgBrightness * 255)
        histogram[peakIndex] = 1.0
        
        return histogram
    }
    
    private func calculateEdgeDensity(_ image: CIImage) -> Float {
        // Use Sobel edge detection
        guard let sobelFilter = CIFilter(name: "CIEdges") else { return 0.5 }
        
        sobelFilter.setValue(image, forKey: kCIInputImageKey)
        sobelFilter.setValue(1.0, forKey: kCIInputIntensityKey)
        
        // In practice, you'd sample the edge image and count edge pixels
        // Returning estimated value for screen vs chassis
        return 0.7 // Placeholder - screens typically have more edges
    }
    
    private func calculateLocalContrast(_ image: CIImage) -> Float {
        // Calculate local contrast using standard deviation approach
        // This is a simplified version - real implementation would use sliding windows
        return 0.6 // Placeholder
    }
    
    private func calculateAverageBrightness(_ histogram: [Float]) -> Float {
        var weightedSum: Float = 0
        var totalWeight: Float = 0
        
        for (index, value) in histogram.enumerated() {
            weightedSum += Float(index) * value
            totalWeight += value
        }
        
        guard totalWeight > 0 else { return 0.5 }
        return (weightedSum / totalWeight) / 255.0
    }
    
    private func calculateContrastSpread(_ histogram: [Float]) -> Float {
        // Calculate how spread out the histogram is
        var minIndex = 255
        var maxIndex = 0
        
        for (index, value) in histogram.enumerated() {
            if value > 0.01 {
                minIndex = min(minIndex, index)
                maxIndex = max(maxIndex, index)
            }
        }
        
        return Float(maxIndex - minIndex) / 255.0
    }
    
    private func calculateConfidence(edgeDensity: Float, contrastSpread: Float, brightness: Float) -> Float {
        // Higher confidence when characteristics are more distinctive
        let edgeConfidence = abs(edgeDensity - 0.5) * 2 // Distance from neutral
        let contrastConfidence = contrastSpread // Higher spread = more confident
        let brightnessConfidence = min(brightness, 1.0 - brightness) * 2 // Avoid extreme values
        
        return (edgeConfidence + contrastConfidence + brightnessConfidence) / 3.0
    }
    
    private func determineSurfaceType(_ characteristics: ImageCharacteristics) -> SurfaceType {
        // Screen characteristics: high edge density, good contrast spread, moderate brightness
        // Chassis characteristics: lower edge density, variable contrast, often darker or lighter
        
        if characteristics.edgeDensity > 0.6 &&
           characteristics.contrastSpread > 0.4 &&
           characteristics.brightness > 0.3 &&
           characteristics.brightness < 0.8 {
            return .screen
        } else {
            return .chassis
        }
    }
    
    private func determineOptimalPolarity(_ characteristics: ImageCharacteristics, surfaceType: SurfaceType) -> PolarityRecommendation {
        let primaryHint: PolarityRecommendation.PolarityHint
        
        switch surfaceType {
        case .screen:
            // Screens usually have dark text on light background
            primaryHint = characteristics.brightness > 0.5 ? .normal : .inverted
            
        case .chassis:
            // Chassis can have engraved (light text on dark) or printed text
            if characteristics.brightness < 0.4 {
                primaryHint = .inverted // Likely engraved/etched text
            } else if characteristics.brightness > 0.7 {
                primaryHint = .normal // Likely printed dark text
            } else {
                primaryHint = .both // Try both polarities
            }
            
        case .metal:
            // Metal surfaces often have engraved text
            primaryHint = characteristics.brightness < 0.5 ? .inverted : .both
            
        case .plastic:
            // Plastic usually has printed text
            primaryHint = .normal
            
        case .glass:
            // Glass surfaces vary widely
            primaryHint = .both
            
        case .paper:
            // Paper typically has printed text
            primaryHint = .normal
            
        case .unknown:
            primaryHint = .both
        }
        
        return PolarityRecommendation(
            primary: primaryHint,
            shouldTestBoth: characteristics.confidence < 0.8
        )
    }
    
    private func generatePreprocessingRecommendations(_ characteristics: ImageCharacteristics, surfaceType: SurfaceType) -> PreprocessingRecommendations {
        var brightnessAdjustment: Float = 0.0
        var contrastAdjustment: Float = 1.0
        var claheEnabled = false
        var noiseReduction = false
        var sharpenIntensity: Float = 0.0
        
        // Generate recommendations based on characteristics
        if characteristics.localContrast < 0.4 {
            contrastAdjustment = 1.2 // Increase contrast
            claheEnabled = true
        }
        
        if characteristics.brightness < 0.3 {
            brightnessAdjustment = 0.2 // Brighten
        } else if characteristics.brightness > 0.7 {
            brightnessAdjustment = -0.2 // Darken
        }
        
        // Enable noise reduction for low-quality surfaces
        if characteristics.edgeDensity < 0.3 {
            noiseReduction = true
        }
        
        // Apply sharpening for blurry images
        if characteristics.contrastSpread < 0.3 {
            sharpenIntensity = 0.5
        }
        
        return PreprocessingRecommendations(
            brightnessAdjustment: brightnessAdjustment,
            contrastAdjustment: contrastAdjustment,
            claheEnabled: claheEnabled,
            noiseReduction: noiseReduction,
            sharpenIntensity: sharpenIntensity
        )
    }
    
    private func createFallbackResult(processingTime: TimeInterval) -> SurfaceClassificationResult {
        let fallbackCharacteristics = ImageCharacteristics(
            histogram: Array(repeating: 0, count: 256),
            edgeDensity: 0.5,
            localContrast: 0.5,
            brightness: 0.5,
            contrastSpread: 0.5,
            confidence: 0.0
        )
        
        let fallbackPolarityRecommendation = PolarityRecommendation(
            primary: .both,
            shouldTestBoth: true
        )
        
        let fallbackPreprocessingRecommendations = PreprocessingRecommendations(
            brightnessAdjustment: 0.0,
            contrastAdjustment: 1.0,
            claheEnabled: false,
            noiseReduction: false,
            sharpenIntensity: 0.0
        )
        
        return SurfaceClassificationResult(
            surfaceType: .unknown,
            confidence: 0.0,
            polarityRecommendation: fallbackPolarityRecommendation,
            processingTime: processingTime,
            characteristics: fallbackCharacteristics,
            preprocessingRecommendations: fallbackPreprocessingRecommendations
        )
    }
}

// MARK: - Supporting Types - REMOVED DUPLICATES
// All types now imported from SurfaceDetector.swift to avoid ambiguity

// MARK: - Classification Logic
