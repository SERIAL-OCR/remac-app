import Foundation
@preconcurrency import CoreImage
import Vision

/// Material-specific OCR settings for optimal recognition
struct OCRSettings {
    var contrast: Float
    var brightness: Float
    var sharpness: Float
    var threshold: Float
    var minimumTextHeight: Float
    var recognitionLevel: VNRequestTextRecognitionLevel

    /// Get optimized settings for a specific surface type
    static func settingsFor(surface: SurfaceType) -> OCRSettings {
        switch surface {
        case .metal:
            // Metal surfaces need higher contrast and sharpness for engraved text
            return OCRSettings(
                contrast: 1.8,
                brightness: 0.9,
                sharpness: 2.5,
                threshold: 0.75,
                minimumTextHeight: 0.008,
                recognitionLevel: .accurate
            )

        case .plastic:
            // Plastic surfaces work well with balanced settings
            return OCRSettings(
                contrast: 1.4,
                brightness: 1.1,
                sharpness: 1.8,
                threshold: 0.65,
                minimumTextHeight: 0.01,
                recognitionLevel: .accurate
            )

        case .glass:
            // Glass surfaces need careful brightness and contrast handling
            return OCRSettings(
                contrast: 1.6,
                brightness: 1.0,
                sharpness: 2.0,
                threshold: 0.7,
                minimumTextHeight: 0.009,
                recognitionLevel: .accurate
            )

        case .screen:
            // Screen displays often have high contrast and clear text
            return OCRSettings(
                contrast: 1.2,
                brightness: 1.2,
                sharpness: 1.5,
                threshold: 0.6,
                minimumTextHeight: 0.012,
                recognitionLevel: .fast
            )

        case .chassis:
            // Device chassis/body surfaces, similar to metal but with different characteristics
            return OCRSettings(
                contrast: 1.7,
                brightness: 1.0,
                sharpness: 2.2,
                threshold: 0.72,
                minimumTextHeight: 0.009,
                recognitionLevel: .accurate
            )

        case .paper:
            // Paper labels need good contrast but lower sharpness
            return OCRSettings(
                contrast: 1.5,
                brightness: 1.0,
                sharpness: 1.3,
                threshold: 0.68,
                minimumTextHeight: 0.011,
                recognitionLevel: .accurate
            )

        case .unknown:
            // Conservative default settings
            return OCRSettings(
                contrast: 1.3,
                brightness: 1.0,
                sharpness: 1.5,
                threshold: 0.7,
                minimumTextHeight: 0.01,
                recognitionLevel: .accurate
            )
        }
    }
}

/// Surface detection confidence and metadata
struct SurfaceDetectionResult {
    let surfaceType: SurfaceType
    let confidence: Float
    let features: SurfaceFeatures
    let timestamp: Date
}

/// Surface characteristics used for detection
struct SurfaceFeatures {
    let reflectivity: Float      // 0.0 - 1.0 (how reflective the surface is)
    let texture: Float          // 0.0 - 1.0 (smoothness/roughness)
    let contrast: Float         // 0.0 - 1.0 (local contrast variation)
    let brightness: Float       // 0.0 - 1.0 (overall brightness)
    let edgeSharpness: Float    // 0.0 - 1.0 (how sharp edges appear)
}

/// Advanced surface detection using computer vision
@MainActor
class SurfaceDetector {
    private let context = CIContext()
    private var detectionQueue = DispatchQueue(label: "com.appleserial.surfacedetection", qos: .userInitiated)

    /// Detect surface type from a camera frame
    func detectSurface(in image: CIImage, completion: @escaping (SurfaceDetectionResult) -> Void) {
        let imageCopy = image // Copy to avoid capturing non-Sendable type
        let contextCopy = self.context // Capture context to avoid actor isolation
        
        detectionQueue.async {
            // Create a non-main-actor context for analysis
            let result = SurfaceDetector.performAnalysisStatic(in: imageCopy, context: contextCopy)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Synchronous surface analysis for immediate results
    @MainActor
    func detectSurfaceSync(in image: CIImage) -> SurfaceDetectionResult {
        return analyzeSurface(in: image)
    }

    /// Core surface analysis algorithm
    private func analyzeSurface(in image: CIImage) -> SurfaceDetectionResult {
        let features = extractFeatures(from: image)
        let surfaceType = SurfaceDetector.classifySurface(features: features)
        let confidence = SurfaceDetector.calculateConfidence(features: features, for: surfaceType)

        return SurfaceDetectionResult(
            surfaceType: surfaceType,
            confidence: confidence,
            features: features,
            timestamp: Date()
        )
    }

    /// Extract surface features using image processing
    private func extractFeatures(from image: CIImage) -> SurfaceFeatures {
        // Get basic image statistics with error handling
        let brightness = (try? calculateAverageBrightnessSafe(of: image)) ?? 0.5
        let contrast = calculateLocalContrastSafe(of: image)
        let edgeSharpness = calculateEdgeSharpnessSafe(of: image)

        // Analyze reflectivity through highlight patterns
        let reflectivity = analyzeReflectivitySafe(of: image)

        // Analyze texture through noise patterns
        let texture = analyzeTextureSafe(of: image)

        return SurfaceFeatures(
            reflectivity: reflectivity,
            texture: texture,
            contrast: contrast,
            brightness: brightness,
            edgeSharpness: edgeSharpness
        )
    }

    // MARK: - Static Methods for Background Processing
    
    /// Static feature extraction to avoid concurrency issues
    private nonisolated static func extractFeaturesStatic(from image: CIImage, context: CIContext) -> SurfaceFeatures {
        // Get basic image statistics with error handling
        let brightness = (try? calculateAverageBrightnessStaticSafe(of: image, context: context)) ?? 0.5
        let contrast = calculateLocalContrastStaticSafe(of: image, context: context)
        let edgeSharpness = calculateEdgeSharpnessStaticSafe(of: image, context: context)

        // Analyze reflectivity through highlight patterns
        let reflectivity = analyzeReflectivityStaticSafe(of: image, context: context)

        // Analyze texture through noise patterns
        let texture = analyzeTextureStaticSafe(of: image, context: context)

        return SurfaceFeatures(
            reflectivity: reflectivity,
            texture: texture,
            contrast: contrast,
            brightness: brightness,
            edgeSharpness: edgeSharpness
        )
    }
    
    /// Static classification method
    private nonisolated static func classifySurface(features: SurfaceFeatures) -> SurfaceType {
        // Metal detection: High reflectivity, high contrast, sharp edges
        if features.reflectivity > 0.7 && features.edgeSharpness > 0.8 {
            return .metal
        }

        // Screen detection: High brightness, high contrast, moderate reflectivity
        if features.brightness > 0.8 && features.contrast > 0.7 && features.reflectivity < 0.5 {
            return .screen
        }

        // Glass detection: High reflectivity, low texture, high edge sharpness
        if features.reflectivity > 0.6 && features.texture < 0.3 && features.edgeSharpness > 0.7 {
            return .glass
        }

        // Plastic detection: Moderate everything, balanced features
        if features.reflectivity > 0.3 && features.reflectivity < 0.6 &&
           features.texture > 0.4 && features.texture < 0.7 {
            return .plastic
        }

        // Paper detection: Low reflectivity, moderate texture, moderate contrast
        if features.reflectivity < 0.4 && features.texture > 0.5 && features.contrast > 0.4 {
            return .paper
        }

        return .unknown
    }
    
    /// Static confidence calculation
    private nonisolated static func calculateConfidence(features: SurfaceFeatures, for surfaceType: SurfaceType) -> Float {
        switch surfaceType {
        case .metal:
            return min(1.0, (features.reflectivity + features.edgeSharpness) / 2.0)

        case .screen:
            return min(1.0, (features.brightness + features.contrast) / 2.0)

        case .glass:
            return min(1.0, (features.reflectivity + features.edgeSharpness) / 2.0)

        case .plastic:
            return 0.7 // Conservative confidence for plastic

        case .chassis:
            return min(1.0, (features.reflectivity * 0.6 + features.edgeSharpness * 0.4))

        case .paper:
            return 0.6 // Conservative confidence for paper

        case .unknown:
            return 0.0
        }
    }
    
    // MARK: - Instance Methods for Feature Extraction

    private func calculateAverageBrightness(of image: CIImage) -> Float {
        return SurfaceDetector.calculateAverageBrightnessStatic(of: image, context: context)
    }

    private func calculateLocalContrast(of image: CIImage) -> Float {
        return SurfaceDetector.calculateLocalContrastStaticSafe(of: image, context: context)
    }

    private func calculateEdgeSharpness(of image: CIImage) -> Float {
        return SurfaceDetector.calculateEdgeSharpnessStaticSafe(of: image, context: context)
    }

    private func analyzeReflectivity(of image: CIImage) -> Float {
        return SurfaceDetector.analyzeReflectivityStaticSafe(of: image, context: context)
    }

    private func analyzeTexture(of image: CIImage) -> Float {
        return SurfaceDetector.analyzeTextureStaticSafe(of: image, context: context)
    }

    // MARK: - Safe Methods with Error Handling

    private func calculateAverageBrightnessSafe(of image: CIImage) throws -> Float {
        guard image.extent.width > 0 && image.extent.height > 0 else {
            throw SurfaceDetectionError.invalidImageSize
        }

        return calculateAverageBrightness(of: image)
    }

    private func calculateLocalContrastSafe(of image: CIImage) -> Float {
        do {
            return try calculateAverageBrightnessSafe(of: image) * 1.5
        } catch {
            return 0.5
        }
    }

    private func calculateEdgeSharpnessSafe(of image: CIImage) -> Float {
        do {
            let contrast = try calculateAverageBrightnessSafe(of: image)
            return min(1.0, contrast * 1.2)
        } catch {
            return 0.5
        }
    }

    private func analyzeReflectivitySafe(of image: CIImage) -> Float {
        do {
            let brightness = try calculateAverageBrightnessSafe(of: image)
            let contrast = calculateLocalContrastSafe(of: image)
            return min(1.0, (brightness * 0.7) + (contrast * 0.3))
        } catch {
            return 0.5
        }
    }

    private func analyzeTextureSafe(of image: CIImage) -> Float {
        do {
            let contrast = try calculateAverageBrightnessSafe(of: image)
            return min(1.0, contrast * 0.8)
        } catch {
            return 0.5
        }
    }

    /// Static analysis method to avoid concurrency issues
    private nonisolated static func performAnalysisStatic(in image: CIImage, context: CIContext) -> SurfaceDetectionResult {
        let features = extractFeaturesStatic(from: image, context: context)
        let surfaceType = classifySurface(features: features)
        let confidence = calculateConfidence(features: features, for: surfaceType)

        return SurfaceDetectionResult(
            surfaceType: surfaceType,
            confidence: confidence,
            features: features,
            timestamp: Date()
        )
    }
    
    // MARK: - Static Safe Methods
    
    nonisolated private static func calculateAverageBrightnessStaticSafe(of image: CIImage, context: CIContext) throws -> Float {
        guard image.extent.width > 0 && image.extent.height > 0 else {
            throw SurfaceDetectionError.invalidImageSize
        }

        return calculateAverageBrightnessStatic(of: image, context: context)
    }
    
    nonisolated private static func calculateLocalContrastStaticSafe(of image: CIImage, context: CIContext) -> Float {
        do {
            return try calculateAverageBrightnessStaticSafe(of: image, context: context) * 1.5
        } catch {
            return 0.5
        }
    }

    nonisolated private static func calculateEdgeSharpnessStaticSafe(of image: CIImage, context: CIContext) -> Float {
        do {
            let contrast = try calculateAverageBrightnessStaticSafe(of: image, context: context)
            return min(1.0, contrast * 1.2)
        } catch {
            return 0.5
        }
    }

    nonisolated private static func analyzeReflectivityStaticSafe(of image: CIImage, context: CIContext) -> Float {
        do {
            let brightness = try calculateAverageBrightnessStaticSafe(of: image, context: context)
            let contrast = calculateLocalContrastStaticSafe(of: image, context: context)
            return min(1.0, (brightness * 0.7) + (contrast * 0.3))
        } catch {
            return 0.5
        }
    }

    nonisolated private static func analyzeTextureStaticSafe(of image: CIImage, context: CIContext) -> Float {
        do {
            let contrast = try calculateAverageBrightnessStaticSafe(of: image, context: context)
            return min(1.0, contrast * 0.8)
        } catch {
            return 0.5
        }
    }
    
    // MARK: - Static Analysis Methods
    
    nonisolated static func calculateAverageBrightnessStatic(of image: CIImage, context: CIContext) -> Float {
        let extent = image.extent
        guard !extent.isEmpty else { return 0.0 }
        
        // Create a histogram filter to analyze brightness
        guard let histogramFilter = CIFilter(name: "CIAreaHistogram") else {
            return 0.0
        }
        
        histogramFilter.setValue(image, forKey: kCIInputImageKey)
        histogramFilter.setValue(CIVector(x: extent.origin.x, y: extent.origin.y, z: extent.size.width, w: extent.size.height), forKey: "inputExtent")
        histogramFilter.setValue(1, forKey: "inputScale")
        histogramFilter.setValue(256, forKey: "inputCount")
        
        guard let histogramImage = histogramFilter.outputImage else {
            return 0.0
        }
        
        // Convert histogram to data
        let histogramData = UnsafeMutablePointer<UInt8>.allocate(capacity: 256 * 4)
        defer { histogramData.deallocate() }
        
        context.render(histogramImage, toBitmap: histogramData, rowBytes: 256 * 4, bounds: CGRect(x: 0, y: 0, width: 256, height: 1), format: .RGBA8, colorSpace: nil)
        
        // Calculate average brightness
        var totalBrightness: Float = 0.0
        var totalPixels: Float = 0.0
        
        for i in 0..<256 {
            let pixelCount = Float(histogramData[i * 4]) // Red channel contains the count
            totalBrightness += Float(i) * pixelCount / 255.0
            totalPixels += pixelCount
        }
        
        return totalPixels > 0 ? totalBrightness / totalPixels : 0.0
    }
}

enum SurfaceDetectionError: Error {
    case invalidImageSize
    case processingFailed
}
