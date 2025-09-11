import CoreML
import Vision
import CoreImage
import Accelerate
import os.log

/// Preprocessing service for Core ML models with optimized image enhancement pipeline
@available(iOS 13.0, *)
public final class PreprocessingService {
    
    // MARK: - Singleton
    public static let shared = PreprocessingService()
    
    private let logger = Logger(subsystem: "AppleSerialScanner", category: "PreprocessingService")
    private let ciContext: CIContext
    
    // MARK: - Configuration
    public struct PreprocessingOptions {
        let applyGrayscale: Bool
        let applyContrastEnhancement: Bool
        let applySharpen: Bool
        let applyUpscaling: Bool
        let upscaleFactor: Float
        let contrastStrength: Float
        let sharpenStrength: Float
        let applyGlareMask: Bool
        
        public static let `default` = PreprocessingOptions(
            applyGrayscale: true,
            applyContrastEnhancement: true,
            applySharpen: true,
            applyUpscaling: true,
            upscaleFactor: 1.7,
            contrastStrength: 1.2,
            sharpenStrength: 0.4,
            applyGlareMask: true
        )
        
        public static let minimal = PreprocessingOptions(
            applyGrayscale: false,
            applyContrastEnhancement: false,
            applySharpen: false,
            applyUpscaling: false,
            upscaleFactor: 1.0,
            contrastStrength: 1.0,
            sharpenStrength: 0.0,
            applyGlareMask: false
        )
    }
    
    private init() {
        // Create high-performance CIContext for image processing
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device)
        } else {
            ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
    }
    
    // MARK: - Main Processing Pipeline
    
    /// Process image with full preprocessing pipeline
    public func processImage(
        _ inputBuffer: CVPixelBuffer,
        options: PreprocessingOptions = .default
    ) async throws -> CVPixelBuffer {
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Convert to CIImage for processing
        let ciImage = CIImage(cvPixelBuffer: inputBuffer)
        var processedImage = ciImage
        
        // Apply preprocessing steps in optimal order
        if options.applyGrayscale {
            processedImage = applyGrayscale(processedImage)
        }
        
        if options.applyGlareMask {
            processedImage = try applyGlareMask(processedImage)
        }
        
        if options.applyContrastEnhancement {
            processedImage = applyContrastEnhancement(processedImage, strength: options.contrastStrength)
        }
        
        if options.applySharpen {
            processedImage = applySharpen(processedImage, strength: options.sharpenStrength)
        }
        
        if options.applyUpscaling && options.upscaleFactor > 1.0 {
            processedImage = applyUpscaling(processedImage, factor: options.upscaleFactor)
        }
        
        // Convert back to CVPixelBuffer
        let outputBuffer = try await createPixelBuffer(from: processedImage)
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        logger.debug("Image preprocessing completed in \(String(format: "%.1f", processingTime * 1000))ms")
        
        return outputBuffer
    }
    
    /// Process ROI region specifically for OCR enhancement
    public func processROI(
        _ inputBuffer: CVPixelBuffer,
        roi: CGRect,
        options: PreprocessingOptions = .default
    ) async throws -> CVPixelBuffer {
        
        // Extract ROI
        let ciImage = CIImage(cvPixelBuffer: inputBuffer)
        let imageSize = ciImage.extent.size
        
        // Convert normalized ROI to pixel coordinates
        let roiRect = CGRect(
            x: roi.origin.x * imageSize.width,
            y: (1.0 - roi.origin.y - roi.height) * imageSize.height, // Flip Y coordinate
            width: roi.width * imageSize.width,
            height: roi.height * imageSize.height
        )
        
        let croppedImage = ciImage.cropped(to: roiRect)
        
        // Process the cropped ROI
        var processedImage = croppedImage
        
        if options.applyGrayscale {
            processedImage = applyGrayscale(processedImage)
        }
        
        if options.applyGlareMask {
            processedImage = try applyGlareMask(processedImage)
        }
        
        // Enhanced contrast for ROI (stronger than full frame)
        if options.applyContrastEnhancement {
            processedImage = applyContrastEnhancement(processedImage, strength: options.contrastStrength * 1.3)
        }
        
        // Enhanced sharpening for text
        if options.applySharpen {
            processedImage = applyTextSharpen(processedImage, strength: options.sharpenStrength)
        }
        
        if options.applyUpscaling && options.upscaleFactor > 1.0 {
            processedImage = applyUpscaling(processedImage, factor: options.upscaleFactor)
        }
        
        return try await createPixelBuffer(from: processedImage)
    }
    
    // MARK: - Individual Processing Steps
    
    private func applyGrayscale(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey) // Remove color
        return filter.outputImage ?? image
    }
    
    private func applyContrastEnhancement(_ image: CIImage, strength: Float) -> CIImage {
        // CLAHE-like local contrast enhancement
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(strength, forKey: kCIInputContrastKey)
        filter.setValue(0.1, forKey: kCIInputBrightnessKey) // Slight brightness boost
        
        let enhancedImage = filter.outputImage ?? image
        
        // Apply unsharp mask for additional local contrast
        guard let unsharpFilter = CIFilter(name: "CIUnsharpMask") else { return enhancedImage }
        unsharpFilter.setValue(enhancedImage, forKey: kCIInputImageKey)
        unsharpFilter.setValue(0.5, forKey: kCIInputRadiusKey)
        unsharpFilter.setValue(0.3, forKey: kCIInputIntensityKey)
        
        return unsharpFilter.outputImage ?? enhancedImage
    }
    
    private func applySharpen(_ image: CIImage, strength: Float) -> CIImage {
        guard let filter = CIFilter(name: "CISharpenLuminance") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(strength, forKey: kCIInputSharpnessKey)
        return filter.outputImage ?? image
    }
    
    private func applyTextSharpen(_ image: CIImage, strength: Float) -> CIImage {
        // Enhanced sharpening specifically for text recognition
        guard let filter = CIFilter(name: "CIConvolution3X3") else { return image }
        
        // Text-optimized sharpening kernel
        let sharpenKernel: [CGFloat] = [
            0, -CGFloat(strength), 0,
            -CGFloat(strength), 1 + 4 * CGFloat(strength), -CGFloat(strength),
            0, -CGFloat(strength), 0
        ]
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(values: sharpenKernel, count: 9), forKey: kCIInputWeightsKey)
        filter.setValue(1.0, forKey: kCIInputBiasKey)
        
        return filter.outputImage ?? image
    }
    
    private func applyUpscaling(_ image: CIImage, factor: Float) -> CIImage {
        let transform = CGAffineTransform(scaleX: CGFloat(factor), y: CGFloat(factor))
        return image.transformed(by: transform)
    }
    
    private func applyGlareMask(_ image: CIImage) throws -> CIImage {
        // Detect and reduce glare/highlights
        guard let thresholdFilter = CIFilter(name: "CIColorThreshold") else { return image }
        thresholdFilter.setValue(image, forKey: kCIInputImageKey)
        thresholdFilter.setValue(0.85, forKey: "inputThreshold") // Detect bright areas
        
        guard let mask = thresholdFilter.outputImage else { return image }
        
        // Apply morphological operations to smooth the mask
        guard let morphologyFilter = CIFilter(name: "CIMorphologyMaximum") else { return image }
        morphologyFilter.setValue(mask, forKey: kCIInputImageKey)
        morphologyFilter.setValue(2.0, forKey: kCIInputRadiusKey)
        
        guard let smoothMask = morphologyFilter.outputImage else { return image }
        
        // Reduce intensity in glare areas
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { return image }
        
        // Create a darkened version of the image
        guard let darkenFilter = CIFilter(name: "CIColorControls") else { return image }
        darkenFilter.setValue(image, forKey: kCIInputImageKey)
        darkenFilter.setValue(0.7, forKey: kCIInputBrightnessKey) // Darken
        darkenFilter.setValue(1.2, forKey: kCIInputContrastKey) // Increase contrast
        
        guard let darkenedImage = darkenFilter.outputImage else { return image }
        
        blendFilter.setValue(image, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(darkenedImage, forKey: kCIInputImageKey)
        blendFilter.setValue(smoothMask, forKey: kCIInputMaskImageKey)
        
        return blendFilter.outputImage ?? image
    }
    
    // MARK: - Utility Methods
    
    private func createPixelBuffer(from ciImage: CIImage) async throws -> CVPixelBuffer {
        return try await withCheckedThrowingContinuation { continuation in
            let width = Int(ciImage.extent.width)
            let height = Int(ciImage.extent.height)
            
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                nil,
                &pixelBuffer
            )
            
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                continuation.resume(throwing: MLModelError.invalidInput("Failed to create pixel buffer"))
                return
            }
            
            ciContext.render(ciImage, to: buffer)
            continuation.resume(returning: buffer)
        }
    }
    
    /// Create preview image for debugging
    public func createPreviewImage(from pixelBuffer: CVPixelBuffer) -> CIImage? {
        return CIImage(cvPixelBuffer: pixelBuffer)
    }
    
    /// Analyze image characteristics for adaptive preprocessing
    public func analyzeImageCharacteristics(_ image: CIImage) -> ImageCharacteristics {
        // Calculate brightness, contrast, and glare metrics
        let extent = image.extent
        let averageBrightness = calculateAverageBrightness(image)
        let contrastLevel = calculateContrast(image)
        let glareLevel = calculateGlareLevel(image)
        
        return ImageCharacteristics(
            brightness: averageBrightness,
            contrast: contrastLevel,
            glareLevel: glareLevel,
            imageSize: extent.size,
            recommendedOptions: getRecommendedOptions(
                brightness: averageBrightness,
                contrast: contrastLevel,
                glare: glareLevel
            )
        )
    }
    
    private func calculateAverageBrightness(_ image: CIImage) -> Float {
        guard let filter = CIFilter(name: "CIAreaAverage") else { return 0.5 }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)
        
        guard let outputImage = filter.outputImage else { return 0.5 }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        
        return Float(bitmap[0]) / 255.0
    }
    
    private func calculateContrast(_ image: CIImage) -> Float {
        // Simplified contrast calculation based on standard deviation
        guard let filter = CIFilter(name: "CIColorControls") else { return 0.5 }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey) // Grayscale
        
        // This is a simplified calculation - in production, you'd want more sophisticated metrics
        return 0.5 // Placeholder
    }
    
    private func calculateGlareLevel(_ image: CIImage) -> Float {
        guard let filter = CIFilter(name: "CIColorThreshold") else { return 0.0 }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.9, forKey: "inputThreshold")
        
        // Calculate percentage of bright pixels
        // This is a simplified calculation
        return 0.1 // Placeholder
    }
    
    private func getRecommendedOptions(brightness: Float, contrast: Float, glare: Float) -> PreprocessingOptions {
        var options = PreprocessingOptions.default
        
        // Adapt based on image characteristics
        if brightness < 0.3 {
            // Dark image - increase contrast and brightness
            options = PreprocessingOptions(
                applyGrayscale: true,
                applyContrastEnhancement: true,
                applySharpen: true,
                applyUpscaling: true,
                upscaleFactor: 1.7,
                contrastStrength: 1.5,
                sharpenStrength: 0.6,
                applyGlareMask: false
            )
        } else if glare > 0.3 {
            // High glare - apply glare reduction
            options = PreprocessingOptions(
                applyGrayscale: true,
                applyContrastEnhancement: true,
                applySharpen: true,
                applyUpscaling: true,
                upscaleFactor: 1.7,
                contrastStrength: 1.0,
                sharpenStrength: 0.4,
                applyGlareMask: true
            )
        }
        
        return options
    }
}

// MARK: - Supporting Types

public struct ImageCharacteristics {
    public let brightness: Float
    public let contrast: Float
    public let glareLevel: Float
    public let imageSize: CGSize
    public let recommendedOptions: PreprocessingService.PreprocessingOptions
}
