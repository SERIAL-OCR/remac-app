import CoreML
import Foundation
import UIKit
import Vision

/// Comprehensive ML Model Manager for Apple Serial Scanner
/// Handles loading, configuration, and prediction for all ML models
@available(iOS 13.0, *)
public class MLModelManager: ObservableObject {
    
    // MARK: - Singleton
    public static let shared = MLModelManager()
    
    // MARK: - Published Properties
    @Published public var isInitialized = false
    @Published public var initializationError: String?
    
    // MARK: - Model Instances
    private var serialRegionDetector: MLModel?
    private var serialFormatClassifier: MLModel?
    private var characterDisambiguator: MLModel?
    
    // MARK: - Configuration
    private let configuration: MLModelConfiguration
    
    // MARK: - Initialization
    private init(configuration: MLModelConfiguration = MLModelConfiguration()) {
        self.configuration = configuration
        Task {
            await initializeModels()
        }
    }
    
    // MARK: - Model Initialization
    @MainActor
    private func initializeModels() async {
        do {
            // Load Serial Region Detector
            serialRegionDetector = try await loadModel(named: CoreMLModelDefinitions.serialRegionDetectorName)
            
            // Load Serial Format Classifier
            serialFormatClassifier = try await loadModel(named: CoreMLModelDefinitions.serialFormatClassifierName)
            
            // Load Character Disambiguator
            characterDisambiguator = try await loadModel(named: CoreMLModelDefinitions.characterDisambiguatorName)
            
            isInitialized = true
            initializationError = nil
            
        } catch {
            initializationError = error.localizedDescription
            isInitialized = false
        }
    }
    
    private func loadModel(named name: String) async throws -> MLModel {
        guard let modelURL = Bundle.main.url(forResource: name, withExtension: "mlmodel") else {
            throw MLModelError.modelNotFound(name)
        }
        
        do {
            let model = try await MLModel(contentsOf: modelURL, configuration: configuration.mlConfiguration)
            return model
        } catch {
            throw MLModelError.loadingFailed(name, error)
        }
    }
}

// MARK: - Serial Region Detection
@available(iOS 13.0, *)
extension MLModelManager {
    
    /// Detects serial number regions in an image
    /// - Parameter image: Input image to analyze
    /// - Returns: Array of detected serial regions with bounding boxes and confidence scores
    public func detectSerialRegions(in image: UIImage) async throws -> [SerialRegion] {
        guard let model = serialRegionDetector else {
            throw MLModelError.modelNotFound(CoreMLModelDefinitions.serialRegionDetectorName)
        }
        
        // Prepare input image
        guard let pixelBuffer = image.pixelBuffer(width: CoreMLModelDefinitions.SerialRegionDetector.inputWidth,
                                                 height: CoreMLModelDefinitions.SerialRegionDetector.inputHeight) else {
            throw MLModelError.invalidInput("Failed to convert image to pixel buffer")
        }
        
        // Create input
        let input = SerialRegionDetectorInput(image: pixelBuffer)
        
        do {
            let output = try await model.prediction(from: input)
            return try parseSerialRegionOutput(output)
        } catch {
            throw MLModelError.predictionFailed(CoreMLModelDefinitions.serialRegionDetectorName, error)
        }
    }
    
    private func parseSerialRegionOutput(_ output: MLFeatureProvider) throws -> [SerialRegion] {
        guard let boundingBoxes = output.featureValue(for: CoreMLModelDefinitions.SerialRegionDetector.outputBoundingBoxes)?.multiArrayValue,
              let confidences = output.featureValue(for: CoreMLModelDefinitions.SerialRegionDetector.outputConfidences)?.multiArrayValue,
              let classes = output.featureValue(for: CoreMLModelDefinitions.SerialRegionDetector.outputClasses)?.multiArrayValue else {
            throw MLModelError.invalidInput("Missing output features from serial region detector")
        }
        
        var regions: [SerialRegion] = []
        let numDetections = confidences.count
        
        for i in 0..<numDetections {
            let confidence = confidences[i].floatValue
            let classIndex = classes[i].int32Value
            
            // Only include high-confidence detections
            if confidence > 0.5 && classIndex == 0 { // 0 = serial_region class
                let bbox = [
                    boundingBoxes[i * 4].floatValue,     // x
                    boundingBoxes[i * 4 + 1].floatValue, // y
                    boundingBoxes[i * 4 + 2].floatValue, // width
                    boundingBoxes[i * 4 + 3].floatValue  // height
                ]
                
                let region = SerialRegion(
                    boundingBox: CGRect(
                        x: CGFloat(bbox[0]),
                        y: CGFloat(bbox[1]),
                        width: CGFloat(bbox[2]),
                        height: CGFloat(bbox[3])
                    ),
                    confidence: confidence,
                    classIndex: Int(classIndex)
                )
                regions.append(region)
            }
        }
        
        return regions
    }
}

// MARK: - Serial Format Classification
@available(iOS 13.0, *)
extension MLModelManager {
    
    /// Classifies whether detected text is an Apple serial number
    /// - Parameters:
    ///   - textFeatures: Text embedding features (128 dimensions)
    ///   - geometryFeatures: Geometry features (8 dimensions)
    /// - Returns: Classification result with confidence scores
    public func classifySerialFormat(textFeatures: [Float], geometryFeatures: [Float]) async throws -> SerialFormatClassification {
        guard let model = serialFormatClassifier else {
            throw MLModelError.modelNotFound(CoreMLModelDefinitions.serialFormatClassifierName)
        }
        
        // Create input arrays
        guard let textArray = try? MLMultiArray(shape: [1, 128], dataType: .float32),
              let geometryArray = try? MLMultiArray(shape: [1, 8], dataType: .float32) else {
            throw MLModelError.invalidInput("Failed to create input arrays")
        }
        
        // Fill text features
        for (index, value) in textFeatures.enumerated() {
            textArray[index] = NSNumber(value: value)
        }
        
        // Fill geometry features
        for (index, value) in geometryFeatures.enumerated() {
            geometryArray[index] = NSNumber(value: value)
        }
        
        // Create input
        let input = SerialFormatClassifierInput(
            text_features: textArray,
            geometry_features: geometryArray
        )
        
        do {
            let output = try await model.prediction(from: input)
            return try parseSerialFormatOutput(output)
        } catch {
            throw MLModelError.predictionFailed(CoreMLModelDefinitions.serialFormatClassifierName, error)
        }
    }
    
    private func parseSerialFormatOutput(_ output: MLFeatureProvider) throws -> SerialFormatClassification {
        guard let classificationScore = output.featureValue(for: "classificationScore")?.doubleValue else {
            throw MLModelError.invalidInput("Missing classification score from format classifier")
        }
        
        let appleSerialProbability = Float(classificationScore)
        let otherTextProbability = 1.0 - appleSerialProbability
        
        return SerialFormatClassification(
            appleSerialProbability: appleSerialProbability,
            otherTextProbability: otherTextProbability,
            isAppleSerial: appleSerialProbability > 0.5
        )
    }
}

// MARK: - Character Disambiguation
@available(iOS 13.0, *)
extension MLModelManager {
    
    /// Disambiguates individual characters in detected text
    /// - Parameter characterImage: 32x32 character image
    /// - Returns: Character prediction with confidence scores
    public func disambiguateCharacter(_ characterImage: UIImage) async throws -> CharacterPrediction {
        guard let model = characterDisambiguator else {
            throw MLModelError.modelNotFound(CoreMLModelDefinitions.characterDisambiguatorName)
        }
        
        // Prepare input image
        guard let pixelBuffer = characterImage.pixelBuffer(width: CoreMLModelDefinitions.CharacterDisambiguator.inputWidth,
                                                          height: CoreMLModelDefinitions.CharacterDisambiguator.inputHeight) else {
            throw MLModelError.invalidInput("Failed to convert character image to pixel buffer")
        }
        
        // Create input
        let input = CharacterDisambiguatorInput(character_image: pixelBuffer)
        
        do {
            let output = try await model.prediction(from: input)
            return try parseCharacterDisambiguationOutput(output)
        } catch {
            throw MLModelError.predictionFailed(CoreMLModelDefinitions.characterDisambiguatorName, error)
        }
    }
    
    private func parseCharacterDisambiguationOutput(_ output: MLFeatureProvider) throws -> CharacterPrediction {
        guard let confidences = output.featureValue(for: "confidences")?.multiArrayValue,
              let characterPredictions = output.featureValue(for: "characterPredictions")?.multiArrayValue else {
            throw MLModelError.invalidInput("Missing output features from character disambiguator")
        }
        
        // Get character labels
        let characterLabels = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
                             "A", "B", "C", "D", "E", "F", "G", "H", "I", "J",
                             "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T",
                             "U", "V", "W", "X", "Y", "Z"]
        
        var characterProbabilities: [String: Float] = [:]
        var maxConfidence: Float = 0
        var topPrediction = ""
        
        for i in 0..<confidences.count {
            let confidence = confidences[i].floatValue
            let characterIndex = characterPredictions[i].int32Value
            
            if characterIndex >= 0 && characterIndex < characterLabels.count {
                let character = characterLabels[Int(characterIndex)]
                characterProbabilities[character] = confidence
                
                if confidence > maxConfidence {
                    maxConfidence = confidence
                    topPrediction = character
                }
            }
        }
        
        return CharacterPrediction(
            characterProbabilities: characterProbabilities,
            topPrediction: topPrediction,
            confidence: maxConfidence
        )
    }
}

// MARK: - Data Models
@available(iOS 13.0, *)
public struct SerialRegion {
    public let boundingBox: CGRect
    public let confidence: Float
    public let classIndex: Int
}

@available(iOS 13.0, *)
public struct SerialFormatClassification {
    public let appleSerialProbability: Float
    public let otherTextProbability: Float
    public let isAppleSerial: Bool
}

@available(iOS 13.0, *)
public struct CharacterPrediction {
    public let characterProbabilities: [String: Float]
    public let topPrediction: String
    public let confidence: Float
}

// MARK: - Model Input Classes
@available(iOS 13.0, *)
public class SerialRegionDetectorInput: MLFeatureProvider {
    public var featureNames: Set<String> = ["image"]
    
    private let image: CVPixelBuffer
    
    public init(image: CVPixelBuffer) {
        self.image = image
    }
    
    public func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "image" {
            return MLFeatureValue(pixelBuffer: image)
        }
        return nil
    }
}

@available(iOS 13.0, *)
public class SerialFormatClassifierInput: MLFeatureProvider {
    public var featureNames: Set<String> = ["text_features", "geometry_features"]
    
    private let textFeatures: MLMultiArray
    private let geometryFeatures: MLMultiArray
    
    public init(text_features: MLMultiArray, geometry_features: MLMultiArray) {
        self.textFeatures = text_features
        self.geometryFeatures = geometry_features
    }
    
    public func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "text_features":
            return MLFeatureValue(multiArray: textFeatures)
        case "geometry_features":
            return MLFeatureValue(multiArray: geometryFeatures)
        default:
            return nil
        }
    }
}

@available(iOS 13.0, *)
public class CharacterDisambiguatorInput: MLFeatureProvider {
    public var featureNames: Set<String> = ["character_image"]
    
    private let characterImage: CVPixelBuffer
    
    public init(character_image: CVPixelBuffer) {
        self.characterImage = character_image
    }
    
    public func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "character_image" {
            return MLFeatureValue(pixelBuffer: characterImage)
        }
        return nil
    }
}

// MARK: - UIImage Extension for Pixel Buffer Conversion
@available(iOS 13.0, *)
extension UIImage {
    func pixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        defer { CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0)) }
        
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(data: pixelData,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                    space: rgbColorSpace,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            return nil
        }
        
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)
        
        UIGraphicsPushContext(context)
        self.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        
        return buffer
    }
}