import Foundation
import CoreImage
import Vision

/// Surface types that can be detected for optimized OCR settings
enum SurfaceType: String, Codable {
    case metal      // Reflective, etched/engraved serials (MacBooks, iPads)
    case plastic    // Smooth, printed/molded serials (chargers, cases)
    case glass      // Transparent surfaces (screen protectors, displays)
    case screen     // Digital displays (device screens, monitors)
    case paper      // Printed labels, documentation
    case unknown    // Cannot determine surface type

    /// Human-readable description for UI display
    var description: String {
        switch self {
        case .metal: return "Metal Surface"
        case .plastic: return "Plastic Surface"
        case .glass: return "Glass Surface"
        case .screen: return "Screen Display"
        case .paper: return "Paper Label"
        case .unknown: return "Analyzing..."
        }
    }

    /// Icon name for UI representation
    var iconName: String {
        switch self {
        case .metal: return "cylinder.fill"
        case .plastic: return "square.stack.3d.up.fill"
        case .glass: return "circle.hexagonpath.fill"
        case .screen: return "display"
        case .paper: return "doc.text.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

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
        detectionQueue.async { [weak self] in
            guard let self = self else { return }

            let result = self.analyzeSurface(in: image)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Synchronous surface analysis for immediate results
    func detectSurfaceSync(in image: CIImage) -> SurfaceDetectionResult {
        return analyzeSurface(in: image)
    }

    /// Core surface analysis algorithm
    private func analyzeSurface(in image: CIImage) -> SurfaceDetectionResult {
        let features = extractFeatures(from: image)
        let surfaceType = classifySurface(features: features)
        let confidence = calculateConfidence(features: features, for: surfaceType)

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

    /// Classify surface type based on extracted features
    private func classifySurface(features: SurfaceFeatures) -> SurfaceType {
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

    /// Calculate confidence score for the classification
    private func calculateConfidence(features: SurfaceFeatures, for surfaceType: SurfaceType) -> Float {
        switch surfaceType {
        case .metal:
            return min(1.0, (features.reflectivity + features.edgeSharpness) / 2.0)

        case .screen:
            return min(1.0, (features.brightness + features.contrast) / 2.0)

        case .glass:
            return min(1.0, (features.reflectivity + features.edgeSharpness) / 2.0)

        case .plastic:
            return 0.7 // Conservative confidence for plastic

        case .paper:
            return 0.6 // Conservative confidence for paper

        case .unknown:
            return 0.0
        }
    }

    // MARK: - Feature Extraction Methods

    private func calculateAverageBrightness(of image: CIImage) -> Float {
        // Use CIAreaAverage filter for much better performance
        guard let averageFilter = CIFilter(name: "CIAreaAverage") else {
            return 0.5
        }

        averageFilter.setValue(image, forKey: kCIInputImageKey)

        guard let outputImage = averageFilter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return 0.5
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(data: nil,
                                    width: 1,
                                    height: 1,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo) else {
            return 0.5
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        guard let pixelData = context.data else {
            return 0.5
        }

        let r = Float(pixelData[0]) / 255.0
        let g = Float(pixelData[1]) / 255.0
        let b = Float(pixelData[2]) / 255.0

        // Calculate luminance using standard formula
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    private func calculateLocalContrast(of image: CIImage) -> Float {
        // Simplified local contrast calculation
        // In a real implementation, this would use more sophisticated algorithms
        let brightness = calculateAverageBrightness(of: image)

        // Estimate contrast based on brightness variation
        // This is a simplified version - production would use edge detection
        return min(1.0, brightness * 1.5)
    }

    private func calculateEdgeSharpness(of image: CIImage) -> Float {
        // Simplified edge sharpness calculation
        // Production implementation would use Sobel/Canny edge detection
        let contrast = calculateLocalContrast(of: image)
        return min(1.0, contrast * 1.2)
    }

    private func analyzeReflectivity(of image: CIImage) -> Float {
        let brightness = calculateAverageBrightness(of: image)
        let contrast = calculateLocalContrast(of: image)

        // High brightness with high contrast often indicates reflectivity
        return min(1.0, (brightness * 0.7) + (contrast * 0.3))
    }

    private func analyzeTexture(of image: CIImage) -> Float {
        // Simplified texture analysis
        // Production would use GLCM or wavelet analysis
        let contrast = calculateLocalContrast(of: image)
        return min(1.0, contrast * 0.8)
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
}

enum SurfaceDetectionError: Error {
    case invalidImageSize
    case processingFailed
}
