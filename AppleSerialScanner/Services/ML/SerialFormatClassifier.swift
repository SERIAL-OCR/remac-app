import Foundation
import CoreML
import Vision
import CoreImage
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Serial Format Classifier using Core ML to validate 12-character Apple serial format
@MainActor
class SerialFormatClassifier: ObservableObject {
    private let modelLoader = MLModelLoader.shared
    
    // MARK: - Properties
    @Published var isReady = false
    @Published var lastClassificationScore: Float = 0.0
    
    private let minimumScore: Float = 0.80
    private let stabilizedMinimumScore: Float = 0.75
    
    // MARK: - Classification Result
    struct ClassificationResult {
        let text: String
        let isAppleSerial: Bool
        let confidence: Float
        let features: SerialFeatures
        let timestamp: Date
    }
    
    // MARK: - Serial Features
    struct SerialFeatures {
        let length: Int
        let characterDistribution: CharacterDistribution
        let aspectRatio: Float
        let contrast: Float
        let digitCount: Int
        let letterCount: Int
        let hasValidPattern: Bool
    }
    
    struct CharacterDistribution {
        let digits: Int
        let letters: Int
        let specialChars: Int
        let ambiguousChars: Int // I, O, l, 0, 1
    }
    
    // MARK: - Initialization
    init() {
        Task {
            await warmUp()
        }
    }
    
    // MARK: - Warm Up
    private func warmUp() async {
        do {
            let model = try await modelLoader.loadSerialFormatClassifier()
            isReady = true
            print("SerialFormatClassifier ready")
        } catch {
            print("SerialFormatClassifier warmup failed: \(error)")
            isReady = false
        }
    }
    
    // MARK: - Main Classification Method
    func classifySerial(
        text: String,
        boundingBox: CGRect,
        textObservation: VNTextObservation? = nil
    ) async throws -> ClassificationResult {
        
        guard isReady else {
            throw MLClassificationError.modelNotReady
        }
        
        // Step 1: Extract features from the text and visual properties
        let features = extractSerialFeatures(
            text: text,
            boundingBox: boundingBox,
            textObservation: textObservation
        )
        
        // Step 2: Quick regex validation
        guard passesBasicValidation(text: text, features: features) else {
            return ClassificationResult(
                text: text,
                isAppleSerial: false,
                confidence: 0.0,
                features: features,
                timestamp: Date()
            )
        }
        
        // Step 3: Run Core ML classification
        let confidence = try await runClassification(text: text, features: features)
        
        // Step 4: Apply confidence thresholds
        let isValid = confidence >= minimumScore
        
        lastClassificationScore = confidence
        
        return ClassificationResult(
            text: text,
            isAppleSerial: isValid,
            confidence: confidence,
            features: features,
            timestamp: Date()
        )
    }
    
    // MARK: - Feature Extraction
    private func extractSerialFeatures(
        text: String,
        boundingBox: CGRect,
        textObservation: VNTextObservation?
    ) -> SerialFeatures {
        
        let charDistribution = analyzeCharacterDistribution(text)
        
        return SerialFeatures(
            length: text.count,
            characterDistribution: charDistribution,
            aspectRatio: Float(boundingBox.width / boundingBox.height),
            contrast: calculateContrast(from: textObservation),
            digitCount: charDistribution.digits,
            letterCount: charDistribution.letters,
            hasValidPattern: hasAppleSerialPattern(text)
        )
    }
    
    private func analyzeCharacterDistribution(_ text: String) -> CharacterDistribution {
        var digits = 0
        var letters = 0
        var specialChars = 0
        var ambiguousChars = 0
        
        let ambiguousSet: Set<Character> = ["I", "O", "l", "0", "1"]
        
        for char in text {
            if char.isNumber {
                digits += 1
            } else if char.isLetter {
                letters += 1
            } else {
                specialChars += 1
            }
            
            if ambiguousSet.contains(char) {
                ambiguousChars += 1
            }
        }
        
        return CharacterDistribution(
            digits: digits,
            letters: letters,
            specialChars: specialChars,
            ambiguousChars: ambiguousChars
        )
    }
    
    private func calculateContrast(from textObservation: VNTextObservation?) -> Float {
        // Extract contrast from text observation confidence
        guard let observation = textObservation else { return 0.5 }
        return observation.confidence
    }
    
    private func hasAppleSerialPattern(_ text: String) -> Bool {
        // Apple serial patterns (simplified)
        let patterns = [
            "^[A-Z0-9]{12}$",           // Standard 12-char
            "^[A-Z]{1}[0-9]{3}[A-Z0-9]{8}$", // Letter + 3 digits + 8 chars
            "^[A-Z0-9]{2}[0-9]{3}[A-Z0-9]{7}$" // Various Apple patterns
        ]
        
        return patterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }
    
    // MARK: - Basic Validation
    private func passesBasicValidation(text: String, features: SerialFeatures) -> Bool {
        // Length check
        guard features.length == 12 else { return false }
        
        // Character composition check
        guard features.digitCount >= 3 && features.letterCount >= 3 else { return false }
        
        // No special characters allowed
        guard features.characterDistribution.specialChars == 0 else { return false }
        
        // Alphanumeric only
        let alphanumericSet = CharacterSet.alphanumerics
        guard text.unicodeScalars.allSatisfy(alphanumericSet.contains) else { return false }
        
        return true
    }
    
    // MARK: - Core ML Classification
    private func runClassification(text: String, features: SerialFeatures) async throws -> Float {
        let model = try await modelLoader.loadSerialFormatClassifier()
        // Create feature vector for the model
        let featureVector = createFeatureVector(text: text, features: features)
        // Prepare input as a dictionary for the generic Core ML API
        let inputFeatures: [String: Any] = [
            "featureVector": featureVector
        ]
        let input = try MLDictionaryFeatureProvider(dictionary: inputFeatures)
        let output = try await model.prediction(from: input)
        // Extract confidence score
        return extractConfidenceScore(from: output)
    }
    
    private func createFeatureVector(text: String, features: SerialFeatures) -> MLMultiArray {
        // Create a feature vector combining text and visual features
        let featureCount = 50 // Adjust based on model requirements
        
        // Attempt allocation; if it fails, provide a zero-initialized fallback to avoid crashes
        let multiArray: MLMultiArray
        if let allocated = try? MLMultiArray(shape: [NSNumber(value: featureCount)], dataType: .float32) {
            multiArray = allocated
        } else {
            // Fallback path: attempt an alternative initializer; if still failing, return a safe zero array via forced try
            multiArray = try! MLMultiArray(shape: [NSNumber(value: featureCount)], dataType: .double)
            for idx in 0..<featureCount {
                multiArray[idx] = 0
            }
        }
        
        var index = 0
        
        // Text-based features (0-39)
        for char in text.prefix(12) {
            if char.isNumber {
                multiArray[index] = NSNumber(value: Float(char.wholeNumberValue ?? 0) / 9.0)
            } else if char.isLetter {
                multiArray[index] = NSNumber(value: Float(char.asciiValue ?? 65 - 65) / 25.0)
            }
            index += 1
        }
        
        // Pad remaining character slots
        while index < 40 {
            multiArray[index] = NSNumber(value: 0.0)
            index += 1
        }
        
        // Statistical features (40-49)
        multiArray[40] = NSNumber(value: Float(features.digitCount) / 12.0)
        multiArray[41] = NSNumber(value: Float(features.letterCount) / 12.0)
        multiArray[42] = NSNumber(value: features.aspectRatio / 20.0) // Normalize by max expected ratio
        multiArray[43] = NSNumber(value: features.contrast)
        multiArray[44] = NSNumber(value: Float(features.characterDistribution.ambiguousChars) / 12.0)
        multiArray[45] = NSNumber(value: features.hasValidPattern ? 1.0 : 0.0)
        
        // Reserved for future features
        multiArray[46] = NSNumber(value: 0.0)
        multiArray[47] = NSNumber(value: 0.0)
        multiArray[48] = NSNumber(value: 0.0)
        multiArray[49] = NSNumber(value: 0.0)
        
        return multiArray
    }
    
    private func extractConfidenceScore(from output: MLFeatureProvider) -> Float {
        // Extract the confidence score from model output
        if let score = output.featureValue(for: "classificationScore")?.doubleValue {
            return Float(score)
        }
        return 0.0
    }
    
    // MARK: - Public Interface
    func classifyWithStabilization(
        text: String,
        boundingBox: CGRect,
        frameHistory: [ClassificationResult]
    ) async throws -> ClassificationResult {
        
        let result = try await classifySerial(text: text, boundingBox: boundingBox)
        
        // If we have stable history, allow lower threshold
        if frameHistory.count >= 3 {
            let avgConfidence = frameHistory.map { $0.confidence }.reduce(0, +) / Float(frameHistory.count)
            if avgConfidence >= stabilizedMinimumScore && result.confidence >= stabilizedMinimumScore {
                return ClassificationResult(
                    text: result.text,
                    isAppleSerial: true,
                    confidence: result.confidence,
                    features: result.features,
                    timestamp: result.timestamp
                )
            }
        }
        
        return result
    }
    
    func getMinimumScore(stabilized: Bool = false) -> Float {
        return stabilized ? stabilizedMinimumScore : minimumScore
    }
    
    func updateThresholds(minimum: Float, stabilized: Float) {
        // Allow runtime threshold adjustments
        if minimum > 0.5 && minimum <= 1.0 {
            // Update thresholds through published properties or configuration
        }
    }
}

// MARK: - Model Input/Output Types
struct SerialFormatClassifierInput {
    let features: MLMultiArray
}

struct SerialFormatClassifierOutput {
    let classificationScore: Float
    let featureImportance: [Float]?
}

// MARK: - Errors
enum MLClassificationError: Error {
    case modelNotReady
    case invalidInput
    case classificationFailed
    case featureExtractionFailed
}
