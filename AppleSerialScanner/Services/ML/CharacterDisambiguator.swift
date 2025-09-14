import Foundation
import CoreML
import Vision
import CoreImage
import UIKit

/// Character Disambiguator using Core ML to resolve ambiguous characters (0/O, 1/I/L, 5/S)
@MainActor
class CharacterDisambiguator: ObservableObject {
    private let modelLoader = MLModelLoader.shared
    
    // MARK: - Properties
    @Published var isReady = false
    @Published var lastDisambiguationScore: Float = 0.0
    @Published var totalDisambiguations = 0
    
    private let disambiguationThreshold: Float = 0.9
    private let ambiguousCharacters: Set<Character> = ["0", "O", "1", "I", "L", "5", "S", "8", "B"]
    
    // MARK: - Disambiguation Result
    struct DisambiguationResult {
        let originalText: String
        let correctedText: String
        let corrections: [CharacterCorrection]
        let overallConfidence: Float
        let timestamp: Date
        let usedPositionalPriors: Bool
    }
    
    struct CharacterCorrection {
        let position: Int
        let originalChar: Character
        let correctedChar: Character
        let confidence: Float
        let method: CorrectionMethod
    }
    
    enum CorrectionMethod {
        case coreML
        case positionalPrior
        case contextualNGram
        case ensemble
    }
    
    // MARK: - Apple Serial Positional Priors
    private let appleSerialPriors: [Int: [Character: Float]] = [
        // Position-based character likelihood for Apple serials
        0: ["F": 0.8, "G": 0.7, "C": 0.6, "D": 0.5], // Common first letters
        1: ["1": 0.7, "2": 0.6, "3": 0.5, "4": 0.4], // Second position often numeric
        // Add more position-specific priors based on Apple serial patterns
    ]
    
    // MARK: - Initialization
    init() {
        Task {
            await warmUp()
        }
    }
    
    // MARK: - Warm Up
    private func warmUp() async {
        do {
            let model = try await modelLoader.loadCharacterDisambiguator()
            isReady = true
            print("CharacterDisambiguator ready")
        } catch {
            print("CharacterDisambiguator warmup failed: \(error)")
            isReady = false
        }
    }
    
    // MARK: - Main Disambiguation Method
    func disambiguateCharacters(
        text: String,
        glyphBoundingBoxes: [CGRect],
        croppedGlyphs: [CGImage]? = nil,
        ambiguityScore: Float
    ) async throws -> DisambiguationResult {
        
        guard isReady else {
            throw MLDisambiguationError.modelNotReady
        }
        
        guard ambiguityScore > 0.5 else {
            // Low ambiguity, return original
            return DisambiguationResult(
                originalText: text,
                correctedText: text,
                corrections: [],
                overallConfidence: 1.0 - ambiguityScore,
                timestamp: Date(),
                usedPositionalPriors: false
            )
        }
        
        // Step 1: Identify ambiguous character positions
        let ambiguousPositions = identifyAmbiguousPositions(in: text)
        
        guard !ambiguousPositions.isEmpty else {
            return DisambiguationResult(
                originalText: text,
                correctedText: text,
                corrections: [],
                overallConfidence: 1.0,
                timestamp: Date(),
                usedPositionalPriors: false
            )
        }
        
        // Step 2: Process each ambiguous character
        var corrections: [CharacterCorrection] = []
        var correctedText = text
        var usedPriors = false
        
        for position in ambiguousPositions {
            let originalChar = text[text.index(text.startIndex, offsetBy: position)]
            
            // Try different disambiguation methods
            let correction = try await disambiguateCharacter(
                char: originalChar,
                position: position,
                context: text,
                glyphImage: getGlyphImage(at: position, from: croppedGlyphs),
                boundingBox: getBoundingBox(at: position, from: glyphBoundingBoxes)
            )
            
            if let correction = correction {
                corrections.append(correction)
                
                // Apply correction to text
                let index = correctedText.index(correctedText.startIndex, offsetBy: position)
                correctedText.replaceSubrange(index...index, with: String(correction.correctedChar))
                
                if correction.method == .positionalPrior {
                    usedPriors = true
                }
            }
        }
        
        // Step 3: Calculate overall confidence
        let overallConfidence = calculateOverallConfidence(corrections: corrections)
        
        totalDisambiguations += corrections.count
        lastDisambiguationScore = overallConfidence
        
        return DisambiguationResult(
            originalText: text,
            correctedText: correctedText,
            corrections: corrections,
            overallConfidence: overallConfidence,
            timestamp: Date(),
            usedPositionalPriors: usedPriors
        )
    }
    
    // MARK: - Character Position Analysis
    private func identifyAmbiguousPositions(in text: String) -> [Int] {
        var positions: [Int] = []
        
        for (index, char) in text.enumerated() {
            if ambiguousCharacters.contains(char) {
                positions.append(index)
            }
        }
        
        return positions
    }
    
    // MARK: - Single Character Disambiguation
    private func disambiguateCharacter(
        char: Character,
        position: Int,
        context: String,
        glyphImage: CGImage?,
        boundingBox: CGRect?
    ) async throws -> CharacterCorrection? {
        
        var bestCorrection: CharacterCorrection?
        var bestConfidence: Float = 0.0
        
        // Method 1: Core ML Classification
        if let glyphImage = glyphImage {
            let mlResult = try await runCoreMLDisambiguation(
                char: char,
                glyphImage: glyphImage,
                position: position
            )
            
            if mlResult.confidence >= disambiguationThreshold {
                bestCorrection = CharacterCorrection(
                    position: position,
                    originalChar: char,
                    correctedChar: mlResult.predictedChar,
                    confidence: mlResult.confidence,
                    method: .coreML
                )
                bestConfidence = mlResult.confidence
            }
        }
        
        // Method 2: Positional Priors
        if let priorResult = applyPositionalPriors(char: char, position: position) {
            if priorResult.confidence > bestConfidence {
                bestCorrection = CharacterCorrection(
                    position: position,
                    originalChar: char,
                    correctedChar: priorResult.predictedChar,
                    confidence: priorResult.confidence,
                    method: .positionalPrior
                )
                bestConfidence = priorResult.confidence
            }
        }
        
        // Method 3: Contextual N-gram
        let ngramResult = applyContextualNGram(char: char, position: position, context: context)
        if ngramResult.confidence > bestConfidence {
            bestCorrection = CharacterCorrection(
                position: position,
                originalChar: char,
                correctedChar: ngramResult.predictedChar,
                confidence: ngramResult.confidence,
                method: .contextualNGram
            )
            bestConfidence = ngramResult.confidence
        }
        
        // Method 4: Ensemble (if multiple methods agree)
        if let ensembleResult = createEnsembleResult(
            char: char,
            position: position,
            methods: [bestCorrection].compactMap { $0 }
        ) {
            if ensembleResult.confidence > bestConfidence {
                bestCorrection = ensembleResult
            }
        }
        
        return bestCorrection
    }
    
    // MARK: - Core ML Disambiguation
    private func runCoreMLDisambiguation(
        char: Character,
        glyphImage: CGImage,
        position: Int
    ) async throws -> (predictedChar: Character, confidence: Float) {
        let model = try await modelLoader.loadCharacterDisambiguator()
        let processedImage = try preprocessGlyphImage(glyphImage)
        // Prepare input as a dictionary for the generic Core ML API
        let inputFeatures: [String: Any] = [
            "glyphImage": processedImage,
            "originalChar": String(char),
            "position": Int64(position)
        ]
        let input = try MLDictionaryFeatureProvider(dictionary: inputFeatures)
        let output = try await model.prediction(from: input)
        // Example assumes output contains 'characterPredictions' ([String]) and 'confidences' ([Double] or [Float])
        guard let predictionsValue = output.featureValue(for: "characterPredictions")?.multiArrayValue,
              let confidencesValue = output.featureValue(for: "confidences")?.multiArrayValue else {
            throw MLDisambiguationError.noValidPredictions
        }
        // Convert MLMultiArray to [String] and [Float]
        let predictions = (0..<predictionsValue.count).compactMap { i in
            predictionsValue[i].stringValue
        }
        let confidences = (0..<confidencesValue.count).compactMap { i in
            Float(truncating: confidencesValue[i])
        }
        // Find the best prediction
        guard let maxIndex = confidences.enumerated().max(by: { $0.element < $1.element })?.offset,
              maxIndex < predictions.count else {
            return (char, 0.0)
        }
        let predictedChar = Character(predictions[maxIndex])
        let confidence = confidences[maxIndex]
        return (predictedChar, confidence)
    }
    
    private func preprocessGlyphImage(_ image: CGImage) throws -> CVPixelBuffer {
        // Resize to model input size (e.g., 32x32)
        let targetSize = CGSize(width: 32, height: 32)
        
        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(targetSize.width),
            Int(targetSize.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw MLDisambiguationError.imageProcessingFailed
        }
        
        // Render image into pixel buffer
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        
        context?.draw(image, in: CGRect(origin: .zero, size: targetSize))
        
        return buffer
    }
    
    // MARK: - Positional Priors
    private func applyPositionalPriors(
        char: Character,
        position: Int
    ) -> (predictedChar: Character, confidence: Float)? {
        
        guard let priors = appleSerialPriors[position] else { return nil }
        
        // Common substitutions based on Apple serial patterns
        let substitutions: [Character: Character] = [
            "O": "0",  // O to 0 is common in serials
            "I": "1",  // I to 1 is common
            "L": "1",  // L to 1
            "S": "5",  // S to 5
            "B": "8"   // B to 8
        ]
        
        if let substitute = substitutions[char],
           let confidence = priors[substitute] {
            return (substitute, confidence)
        }
        
        return nil
    }
    
    // MARK: - Contextual N-gram
    private func applyContextualNGram(
        char: Character,
        position: Int,
        context: String
    ) -> (predictedChar: Character, confidence: Float) {
        
        // Simple n-gram based on Apple serial patterns
        let commonPatterns: [String: Float] = [
            "F1": 0.8,  // F1 is common start
            "G1": 0.7,  // G1 is common start
            "10": 0.6,  // 10 pattern
            "01": 0.5   // 01 pattern
        ]
        
        // Check 2-gram patterns
        if position > 0 {
            let prevChar = context[context.index(context.startIndex, offsetBy: position - 1)]
            let pattern = String(prevChar) + String(char)
            
            if let confidence = commonPatterns[pattern] {
                // Return most likely substitution
                let substitutions: [Character: Character] = ["O": "0", "I": "1", "L": "1"]
                if let substitute = substitutions[char] {
                    return (substitute, confidence)
                }
            }
        }
        
        // Default: prefer digits over letters in later positions
        if position > 2 {
            let substitutions: [Character: Character] = ["O": "0", "I": "1", "L": "1", "S": "5"]
            if let substitute = substitutions[char] {
                return (substitute, 0.6)
            }
        }
        
        return (char, 0.3) // Low confidence, keep original
    }
    
    // MARK: - Ensemble Method
    private func createEnsembleResult(
        char: Character,
        position: Int,
        methods: [CharacterCorrection]
    ) -> CharacterCorrection? {
        
        guard methods.count >= 2 else { return nil }
        
        // Check if multiple methods agree
        let groupedByChar = Dictionary(grouping: methods) { $0.correctedChar }
        
        if let (agreedChar, agreements) = groupedByChar.max(by: { $0.value.count < $1.value.count }),
           agreements.count >= 2 {
            
            let avgConfidence = agreements.map { $0.confidence }.reduce(0, +) / Float(agreements.count)
            let ensembleConfidence = min(0.95, avgConfidence * 1.1) // Boost for agreement
            
            return CharacterCorrection(
                position: position,
                originalChar: char,
                correctedChar: agreedChar,
                confidence: ensembleConfidence,
                method: .ensemble
            )
        }
        
        return nil
    }
    
    // MARK: - Helper Methods
    private func getGlyphImage(at position: Int, from glyphs: [CGImage]?) -> CGImage? {
        guard let glyphs = glyphs, position < glyphs.count else { return nil }
        return glyphs[position]
    }
    
    private func getBoundingBox(at position: Int, from boxes: [CGRect]) -> CGRect? {
        guard position < boxes.count else { return nil }
        return boxes[position]
    }
    
    private func calculateOverallConfidence(corrections: [CharacterCorrection]) -> Float {
        guard !corrections.isEmpty else { return 1.0 }
        
        let avgConfidence = corrections.map { $0.confidence }.reduce(0, +) / Float(corrections.count)
        return avgConfidence
    }
    
    private func parseDisambiguationOutput(
        _ output: CharacterDisambiguatorOutput,
        originalChar: Character
    ) -> (predictedChar: Character, confidence: Float) {
        
        let predictions = output.characterPredictions
        let confidences = output.confidences
        
        guard let maxIndex = confidences.enumerated().max(by: { $0.element < $1.element })?.offset,
              maxIndex < predictions.count else {
            return (originalChar, 0.0)
        }
        
        let predictedChar = Character(predictions[maxIndex])
        let confidence = confidences[maxIndex]
        
        return (predictedChar, confidence)
    }
    
    // MARK: - Public Interface
    func getAmbiguityScore(for text: String) -> Float {
        let ambiguousCount = text.filter { ambiguousCharacters.contains($0) }.count
        return Float(ambiguousCount) / Float(text.count)
    }
    
    func isCharacterAmbiguous(_ char: Character) -> Bool {
        return ambiguousCharacters.contains(char)
    }
    
    func resetStatistics() {
        totalDisambiguations = 0
        lastDisambiguationScore = 0.0
    }
}

// MARK: - Model Input/Output Types
struct CharacterDisambiguatorInput {
    let glyphImage: CVPixelBuffer
    let originalChar: String
    let position: Int
}

struct CharacterDisambiguatorOutput {
    let characterPredictions: [String]
    let confidences: [Float]
}

// MARK: - Errors
enum MLDisambiguationError: Error {
    case modelNotReady
    case invalidInput
    case disambiguationFailed
    case imageProcessingFailed
    case noValidPredictions
}
