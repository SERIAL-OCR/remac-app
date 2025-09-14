import Foundation
import CoreImage
import Vision
import os.log

/// Preprocesses images for optimal OCR based on surface type and polarity
@available(iOS 13.0, *)
class ImagePreprocessor {
    // MARK: - Properties
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "ImagePreprocessor")
    
    // Processing cache
    private var processingCache: [String: PreprocessingResult] = [:]
    private let maxCacheSize = 30
    
    init() {
        logger.debug("ImagePreprocessor initialized")
    }
    
    /// Preprocesses image based on surface classification
    func preprocessImage(
        _ image: CIImage,
        classification: SurfaceClassificationResult
    ) -> PreprocessingResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Check cache
        let cacheKey = createCacheKey(image: image, classification: classification)
        if let cachedResult = processingCache[cacheKey] {
            logger.debug("Using cached preprocessing result")
            return cachedResult
        }
        
        var processedImages: [ProcessedImage] = []
        let recommendations = classification.preprocessingRecommendations
        let polarityRec = classification.polarityRecommendation
        
        // Process based on polarity recommendation
        if polarityRec.shouldTestBoth {
            // Process both normal and inverted versions
            if let normalProcessed = applyPreprocessing(
                image,
                recommendations: recommendations,
                inverted: false
            ) {
                processedImages.append(ProcessedImage(
                    image: normalProcessed,
                    isInverted: false,
                    processingMethod: "normal_\(classification.surfaceType.rawValue)"
                ))
            }
            
            if let invertedProcessed = applyPreprocessing(
                image,
                recommendations: recommendations,
                inverted: true
            ) {
                processedImages.append(ProcessedImage(
                    image: invertedProcessed,
                    isInverted: true,
                    processingMethod: "inverted_\(classification.surfaceType.rawValue)"
                ))
            }
        } else {
            // Process only primary polarity
            let useInverted = polarityRec.primary == .inverted
            let polarityString = polarityRec.primary == .normal ? "normal" : "inverted"
            if let processed = applyPreprocessing(
                image,
                recommendations: recommendations,
                inverted: useInverted
            ) {
                processedImages.append(ProcessedImage(
                    image: processed,
                    isInverted: useInverted,
                    processingMethod: "\(polarityString)_\(classification.surfaceType.rawValue)"
                ))
            }
        }
        
        // Track applied filters for the result
        var appliedFilters: [String] = []
        if recommendations.brightnessAdjustment != 0.0 { appliedFilters.append("brightness") }
        if recommendations.contrastAdjustment != 1.0 { appliedFilters.append("contrast") }
        if recommendations.claheEnabled { appliedFilters.append("clahe") }
        if recommendations.noiseReduction { appliedFilters.append("noise_reduction") }
        if recommendations.sharpenIntensity > 0.0 { appliedFilters.append("sharpening") }
        appliedFilters.append("gamma_correction")
        
        let result = PreprocessingResult(
            processedImages: processedImages,
            appliedFilters: appliedFilters,
            processingTime: CFAbsoluteTimeGetCurrent() - startTime
        )
        
        // Cache result
        cacheResult(key: cacheKey, result: result)
        
        logger.debug("Preprocessed \(processedImages.count) images for \(classification.surfaceType.rawValue)")
        return result
    }
    
    private func applyPreprocessing(
        _ image: CIImage,
        recommendations: PreprocessingRecommendations,
        inverted: Bool
    ) -> CIImage? {
        var processedImage = image
        
        do {
            // Step 1: Apply inversion if needed
            if inverted {
                processedImage = try applyInversion(processedImage)
            }
            
            // Step 2: Apply brightness adjustment
            if recommendations.brightnessAdjustment != 0.0 {
                processedImage = try applyBrightnessAdjustment(
                    processedImage,
                    adjustment: recommendations.brightnessAdjustment
                )
            }
            
            // Step 3: Apply contrast adjustment
            if recommendations.contrastAdjustment != 1.0 {
                processedImage = try applyContrastAdjustment(
                    processedImage,
                    contrast: recommendations.contrastAdjustment
                )
            }
            
            // Step 4: Apply CLAHE if enabled
            if recommendations.claheEnabled {
                processedImage = try applyCLAHE(processedImage)
            }
            
            // Step 5: Apply noise reduction if enabled
            if recommendations.noiseReduction {
                processedImage = try applyNoiseReduction(processedImage)
            }
            
            // Step 6: Apply sharpening
            if recommendations.sharpenIntensity > 0.0 {
                processedImage = try applySharpening(
                    processedImage,
                    intensity: recommendations.sharpenIntensity
                )
            }
            
            // Step 7: Final gamma correction for OCR optimization
            processedImage = try applyGammaCorrection(processedImage)
            
            return processedImage
            
        } catch {
            logger.error("Preprocessing failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func applyInversion(_ image: CIImage) throws -> CIImage {
        guard let invertFilter = CIFilter(name: "CIColorInvert") else {
            throw PreprocessingError.filterCreationFailed("CIColorInvert")
        }
        
        invertFilter.setValue(image, forKey: kCIInputImageKey)
        
        guard let output = invertFilter.outputImage else {
            throw PreprocessingError.filterProcessingFailed("CIColorInvert")
        }
        
        return output
    }
    
    private func applyBrightnessAdjustment(_ image: CIImage, adjustment: Float) throws -> CIImage {
        guard let brightnessFilter = CIFilter(name: "CIColorControls") else {
            throw PreprocessingError.filterCreationFailed("CIColorControls")
        }
        
        brightnessFilter.setValue(image, forKey: kCIInputImageKey)
        brightnessFilter.setValue(adjustment, forKey: kCIInputBrightnessKey)
        
        guard let output = brightnessFilter.outputImage else {
            throw PreprocessingError.filterProcessingFailed("CIColorControls")
        }
        
        return output
    }
    
    private func applyContrastAdjustment(_ image: CIImage, contrast: Float) throws -> CIImage {
        guard let contrastFilter = CIFilter(name: "CIColorControls") else {
            throw PreprocessingError.filterCreationFailed("CIColorControls")
        }
        
        contrastFilter.setValue(image, forKey: kCIInputImageKey)
        contrastFilter.setValue(contrast, forKey: kCIInputContrastKey)
        
        guard let output = contrastFilter.outputImage else {
            throw PreprocessingError.filterProcessingFailed("CIColorControls")
        }
        
        return output
    }
    
    private func applyCLAHE(_ image: CIImage) throws -> CIImage {
        // Simulate CLAHE using highlight/shadow adjustment
        guard let claheFilter = CIFilter(name: "CIHighlightShadowAdjust") else {
            throw PreprocessingError.filterCreationFailed("CIHighlightShadowAdjust")
        }
        
        claheFilter.setValue(image, forKey: kCIInputImageKey)
        claheFilter.setValue(0.3, forKey: "inputHighlightAmount")
        claheFilter.setValue(0.4, forKey: "inputShadowAmount")
        
        guard let output = claheFilter.outputImage else {
            throw PreprocessingError.filterProcessingFailed("CIHighlightShadowAdjust")
        }
        
        return output
    }
    
    private func applyNoiseReduction(_ image: CIImage) throws -> CIImage {
        guard let noiseFilter = CIFilter(name: "CINoiseReduction") else {
            throw PreprocessingError.filterCreationFailed("CINoiseReduction")
        }
        
        noiseFilter.setValue(image, forKey: kCIInputImageKey)
        noiseFilter.setValue(0.02, forKey: "inputNoiseLevel")
        noiseFilter.setValue(0.40, forKey: "inputSharpness")
        
        guard let output = noiseFilter.outputImage else {
            throw PreprocessingError.filterProcessingFailed("CINoiseReduction")
        }
        
        return output
    }
    
    private func applySharpening(_ image: CIImage, intensity: Float) throws -> CIImage {
        guard let sharpenFilter = CIFilter(name: "CIUnsharpMask") else {
            throw PreprocessingError.filterCreationFailed("CIUnsharpMask")
        }
        
        sharpenFilter.setValue(image, forKey: kCIInputImageKey)
        sharpenFilter.setValue(2.5, forKey: kCIInputRadiusKey)
        sharpenFilter.setValue(intensity, forKey: kCIInputIntensityKey)
        
        guard let output = sharpenFilter.outputImage else {
            throw PreprocessingError.filterProcessingFailed("CIUnsharpMask")
        }
        
        return output
    }
    
    private func applyGammaCorrection(_ image: CIImage) throws -> CIImage {
        guard let gammaFilter = CIFilter(name: "CIGammaAdjust") else {
            throw PreprocessingError.filterCreationFailed("CIGammaAdjust")
        }
        
        gammaFilter.setValue(image, forKey: kCIInputImageKey)
        gammaFilter.setValue(0.8, forKey: "inputPower") // Slightly increase contrast for OCR
        
        guard let output = gammaFilter.outputImage else {
            throw PreprocessingError.filterProcessingFailed("CIGammaAdjust")
        }
        
        return output
    }
    
    private func createCacheKey(image: CIImage, classification: SurfaceClassificationResult) -> String {
        let extent = image.extent
        let surfaceType = classification.surfaceType.rawValue
        let polarityString = classification.polarityRecommendation.primary == .normal ? "normal" : "inverted"
        return "\(Int(extent.width))x\(Int(extent.height))_\(surfaceType)_\(polarityString)"
    }
    
    private func cacheResult(key: String, result: PreprocessingResult) {
        processingCache[key] = result
        
        if processingCache.count > maxCacheSize {
            let oldestKey = processingCache.keys.first!
            processingCache.removeValue(forKey: oldestKey)
        }
    }
    
    /// Clear preprocessing cache
    func clearCache() {
        processingCache.removeAll()
        logger.debug("Preprocessing cache cleared")
    }
}

// MARK: - Supporting Types - REMOVED DUPLICATES
// All types now imported from PipelineTypes.swift to avoid ambiguity

enum PreprocessingError: Error, LocalizedError {
    case filterCreationFailed(String)
    case filterProcessingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .filterCreationFailed(let filterName):
            return "Failed to create \(filterName) filter"
        case .filterProcessingFailed(let filterName):
            return "Failed to process with \(filterName) filter"
        }
    }
}
