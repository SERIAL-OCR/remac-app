import Foundation
import CoreImage
import Vision

/// Lighting conditions that can affect OCR accuracy
enum LightingCondition: String, Codable {
    case optimal       // Well-lit, uniform illumination
    case bright        // Very bright, possible glare
    case dim          // Low light, needs enhancement
    case uneven       // Uneven illumination, shadows
    case glare        // Strong glare present
    case mixed        // Mixed lighting sources
    case unknown      // Cannot determine

    /// Human-readable description for UI
    var description: String {
        switch self {
        case .optimal: return "Optimal Lighting"
        case .bright: return "Bright Light"
        case .dim: return "Low Light"
        case .uneven: return "Uneven Lighting"
        case .glare: return "Glare Detected"
        case .mixed: return "Mixed Lighting"
        case .unknown: return "Analyzing..."
        }
    }

    /// Icon name for UI representation
    var iconName: String {
        switch self {
        case .optimal: return "sun.max.fill"
        case .bright: return "sun.max"
        case .dim: return "moon.fill"
        case .uneven: return "lightbulb.fill"
        case .glare: return "sun.haze.fill"
        case .mixed: return "lightbulb.2.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    /// Recommended OCR settings for this lighting condition
    var ocrSettings: OCRSettings {
        switch self {
        case .optimal:
            return OCRSettings(contrast: 1.0, brightness: 0.0, sharpness: 1.0, threshold: 0.5,
                             minimumTextHeight: 20.0, recognitionLevel: .accurate)
        case .bright:
            return OCRSettings(contrast: 1.2, brightness: -0.1, sharpness: 1.0, threshold: 0.6,
                             minimumTextHeight: 20.0, recognitionLevel: .accurate)
        case .dim:
            return OCRSettings(contrast: 1.5, brightness: 0.2, sharpness: 1.2, threshold: 0.4,
                             minimumTextHeight: 25.0, recognitionLevel: .accurate)
        case .uneven:
            return OCRSettings(contrast: 1.3, brightness: 0.1, sharpness: 1.1, threshold: 0.5,
                             minimumTextHeight: 22.0, recognitionLevel: .accurate)
        case .glare:
            return OCRSettings(contrast: 1.4, brightness: -0.2, sharpness: 1.0, threshold: 0.7,
                             minimumTextHeight: 20.0, recognitionLevel: .accurate)
        case .mixed:
            return OCRSettings(contrast: 1.2, brightness: 0.0, sharpness: 1.1, threshold: 0.6,
                             minimumTextHeight: 20.0, recognitionLevel: .accurate)
        case .unknown:
            return OCRSettings(contrast: 1.0, brightness: 0.0, sharpness: 1.0, threshold: 0.5,
                             minimumTextHeight: 20.0, recognitionLevel: .accurate)
        }
    }
}

/// Analysis of glare in an image
struct GlareAnalysis {
    let glareIntensity: Float      // 0.0 (no glare) to 1.0 (severe glare)
    let glareRegions: [CGRect]    // Areas with significant glare
    let glarePercentage: Float     // Percentage of image affected by glare
}

/// Illumination profile of an image
struct IlluminationProfile {
    let averageBrightness: Float
    let brightnessVariance: Float  // Uniformity measure
    let dynamicRange: Float        // Range between darkest and brightest areas
    let shadowRegions: [CGRect]    // Areas with significant shadows
    let highlightRegions: [CGRect] // Areas with significant highlights
}

/// Processing steps for lighting compensation
enum ImageProcessingStep {
    case glareReduction(intensity: Float)
    case shadowCompensation(intensity: Float)
    case illuminationNormalization
    case contrastEnhancement(factor: Float)
    case brightnessAdjustment(delta: Float)
}

/// Advanced lighting analysis and adaptation system
class LightingAnalyzer {

    // MARK: - Shared Resources
    private let context = CIContext()

    // MARK: - Glare Detection

    /// Detect glare in the image
    func detectGlare(in image: CIImage) -> GlareAnalysis {
        let brightness = calculateAverageBrightness(of: image)
        let highlights = detectHighlights(in: image)
        let brightRegions = findBrightRegions(in: image)

        // Break up complex expressions for compiler
        let highlightScore = Double(highlights.count) * 0.1
        let brightRegionScore = Double(brightRegions.count) * 0.05
        let rawGlareIntensity = highlightScore + brightRegionScore
        let glareIntensity = min(1.0, rawGlareIntensity)

        let imageArea = image.extent.width * image.extent.height
        let regionCount = Double(brightRegions.count)
        let glarePercentage = imageArea > 0 ? Float(regionCount / max(1.0, imageArea / 10000.0)) : 0.0

        return GlareAnalysis(
            glareIntensity: Float(glareIntensity),
            glareRegions: brightRegions,
            glarePercentage: glarePercentage
        )
    }

    /// Detect highlight regions that might indicate glare
    private func detectHighlights(in image: CIImage) -> [CGPoint] {
        // Simplified highlight detection
        // In production, this would use more sophisticated algorithms
        let brightness = calculateAverageBrightness(of: image)
        return brightness > 0.8 ? [CGPoint(x: image.extent.midX, y: image.extent.midY)] : []
    }

    /// Find regions that are significantly brighter than average
    private func findBrightRegions(in image: CIImage) -> [CGRect] {
        // Simplified region detection
        // Production would use connected component analysis
        let brightness = calculateAverageBrightness(of: image)
        if brightness > 0.7 {
            return [CGRect(x: image.extent.midX - 50, y: image.extent.midY - 50, width: 100, height: 100)]
        }
        return []
    }

    // MARK: - Illumination Analysis

    /// Analyze the illumination profile of an image
    func analyzeIllumination(in image: CIImage) -> IlluminationProfile {
        let averageBrightness = calculateAverageBrightness(of: image)
        let brightnessVariance = calculateBrightnessVariance(of: image)
        let dynamicRange = calculateDynamicRange(of: image)
        let shadowRegions = detectShadows(in: image)
        let highlightRegions = detectHighlights(in: image).map { point in
            CGRect(x: point.x - 25, y: point.y - 25, width: 50, height: 50)
        }

        return IlluminationProfile(
            averageBrightness: averageBrightness,
            brightnessVariance: brightnessVariance,
            dynamicRange: dynamicRange,
            shadowRegions: shadowRegions,
            highlightRegions: highlightRegions
        )
    }

    /// Calculate brightness variance to measure uniformity
    private func calculateBrightnessVariance(of image: CIImage) -> Float {
        // Simplified variance calculation
        // Production would sample multiple regions
        let centerBrightness = calculateBrightnessInRegion(of: image, region: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        let cornerBrightness = calculateBrightnessInRegion(of: image, region: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1))
        return abs(centerBrightness - cornerBrightness)
    }

    /// Calculate dynamic range
    private func calculateDynamicRange(of image: CIImage) -> Float {
        // Simplified dynamic range calculation
        return 1.0 - calculateBrightnessVariance(of: image)
    }

    /// Detect shadow regions
    private func detectShadows(in image: CIImage) -> [CGRect] {
        let brightness = calculateAverageBrightness(of: image)
        if brightness < 0.3 {
            return [CGRect(x: image.extent.midX - 30, y: image.extent.midY - 30, width: 60, height: 60)]
        }
        return []
    }

    /// Calculate brightness in a specific region
    private func calculateBrightnessInRegion(of image: CIImage, region: CGRect) -> Float {
        let croppedImage = image.cropped(to: region)
        return calculateAverageBrightness(of: croppedImage)
    }

    // MARK: - Lighting Classification

    /// Classify the overall lighting condition
    func classifyLightingCondition(_ profile: IlluminationProfile) -> LightingCondition {
        let glareAnalysis = detectGlare(in: CIImage()) // Would need the actual image

        // Classification logic
        if profile.averageBrightness > 0.8 && glareAnalysis.glareIntensity > 0.3 {
            return .glare
        } else if profile.averageBrightness > 0.7 {
            return .bright
        } else if profile.averageBrightness < 0.3 {
            return .dim
        } else if profile.brightnessVariance > 0.3 {
            return .uneven
        } else if profile.averageBrightness >= 0.4 && profile.averageBrightness <= 0.7 {
            return .optimal
        } else {
            return .mixed
        }
    }

    // MARK: - Compensation Recommendations

    /// Recommend processing steps for a given lighting condition
    func recommendCompensation(for condition: LightingCondition) -> [ImageProcessingStep] {
        switch condition {
        case .optimal:
            return [.contrastEnhancement(factor: 1.1)]

        case .bright:
            return [.brightnessAdjustment(delta: -0.1), .contrastEnhancement(factor: 1.2)]

        case .dim:
            return [.brightnessAdjustment(delta: 0.2), .contrastEnhancement(factor: 1.3)]

        case .uneven:
            return [.illuminationNormalization, .contrastEnhancement(factor: 1.2)]

        case .glare:
            return [.glareReduction(intensity: 0.5), .contrastEnhancement(factor: 1.4)]

        case .mixed:
            return [.illuminationNormalization, .contrastEnhancement(factor: 1.2)]

        case .unknown:
            return [.contrastEnhancement(factor: 1.1)]
        }
    }

    // MARK: - Core Brightness Calculation

    /// Calculate average brightness using efficient Core Image filters
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

        let buffer = pixelData.bindMemory(to: UInt8.self, capacity: 4)
        let r = Float(buffer[0]) / 255.0
        let g = Float(buffer[1]) / 255.0
        let b = Float(buffer[2]) / 255.0

        // Calculate luminance using standard formula
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
}
