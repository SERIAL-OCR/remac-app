import Foundation
import Vision

/// Enhanced serial number validator with character confusion resolution
/// and format enforcement for Apple serial numbers
class EnhancedSerialValidator {
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "SerialValidator")
    
    // Character confusion mapping for common OCR mistakes
    private let confusionMap: [Character: Set<Character>] = [
        "0": ["O"],
        "O": ["0"],
        "1": ["I", "L"],
        "I": ["1", "L"],
        "L": ["1", "I"],
        "5": ["S"],
        "S": ["5"],
        "8": ["B"],
        "B": ["8", "3"],
        "3": ["B", "8"]
    ]
    
    // Validation configuration
    private let serialPatterns: [String]
    private let allowedCharacters: CharacterSet
    private let minimumLength: Int
    private let maximumLength: Int
    
    // Validation cache for performance
    private var validationCache: [String: ValidatorResult] = [:]
    private let cacheLimit = 1000
    
    init() {
        // Initialize with Apple serial number patterns
        self.serialPatterns = [
            "^[A-Z0-9]{12}$",  // Current format
            "^[A-Z0-9]{11}$",  // Legacy format
            "^[A-Z]{1}[A-Z0-9]{10}$"  // Alternative format
        ]
        
        // Set up allowed characters
        var allowed = CharacterSet.alphanumerics
        allowed.remove(charactersIn: "aeiou") // Remove commonly confused vowels
        self.allowedCharacters = allowed
        
        self.minimumLength = 11
        self.maximumLength = 12
    }
    
    /// Validate a serial number with confidence score
    func validateSerial(_ serial: String, confidence: Float) -> ValidatorResult {
        // Check cache first
        if let cached = validationCache[serial] {
            return cached
        }
        
        // Clean and normalize input
        let cleanedSerial = serial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        // Basic format validation
        guard cleanedSerial.count >= minimumLength && cleanedSerial.count <= maximumLength else {
            return .invalid("Invalid length")
        }
        
        // Character set validation
        guard cleanedSerial.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            if let corrected = attemptCharacterCorrection(cleanedSerial) {
                return .corrected(original: cleanedSerial, corrected: corrected)
            }
            return .invalid("Invalid characters")
        }
        
        // Pattern matching
        guard serialPatterns.contains(where: { cleanedSerial.range(of: $0, options: .regularExpression) != nil }) else {
            if let suggestion = suggestCorrection(for: cleanedSerial) {
                return .suggestedCorrection(original: cleanedSerial, suggested: suggestion.corrected, confidence: suggestion.confidence)
            }
            return .invalid("Invalid format")
        }
        
        // Cache successful validation
        let result = ValidatorResult.valid(cleanedSerial)
        cacheValidation(serial: serial, result: result)
        
        return result
    }
    
    // MARK: - Private Methods
    
    private func attemptCharacterCorrection(_ serial: String) -> String? {
        var corrected = serial
        var madeCorrection = false
        
        // Apply confusion map corrections
        for (index, char) in serial.enumerated() {
            if let confused = confusionMap[char] {
                // Check context to determine most likely correction
                let correction = determineContextualCorrection(char: char, confused: confused, position: index, in: serial)
                if correction != char {
                    corrected.replaceSubrange(
                        corrected.index(corrected.startIndex, offsetBy: index)...corrected.index(corrected.startIndex, offsetBy: index),
                        with: String(correction)
                    )
                    madeCorrection = true
                }
            }
        }
        
        return madeCorrection ? corrected : nil
    }
    
    private func determineContextualCorrection(char: Character, confused: Set<Character>, position: Int, in serial: String) -> Character {
        // Apply contextual rules based on position and surrounding characters
        // This is a simplified example - production code would have more sophisticated rules
        
        if position == 0 {
            // First character rules
            return confused.contains("O") && char == "0" ? "O" : char
        } else if position == serial.count - 1 {
            // Last character rules
            return confused.contains("0") && char == "O" ? "0" : char
        }
        
        // Default to most likely correction based on position
        if let prev = serial.index(serial.startIndex, offsetBy: position - 1, limitedBy: serial.endIndex) {
            let prevChar = serial[prev]
            if prevChar.isLetter && confused.contains(where: { $0.isNumber }) {
                return confused.first(where: { $0.isNumber }) ?? char
            } else if prevChar.isNumber && confused.contains(where: { $0.isLetter }) {
                return confused.first(where: { $0.isLetter }) ?? char
            }
        }
        
        return char
    }
    
    private func suggestCorrection(for serial: String) -> (corrected: String, confidence: Float)? {
        // Apply more aggressive correction attempts for suggested corrections
        var bestMatch: (String, Float)?
        
        // Try character substitutions
        for (index, char) in serial.enumerated() {
            if let confused = confusionMap[char] {
                for alternative in confused {
                    var corrected = serial
                    corrected.replaceSubrange(
                        corrected.index(corrected.startIndex, offsetBy: index)...corrected.index(corrected.startIndex, offsetBy: index),
                        with: String(alternative)
                    )
                    
                    // Check if correction matches any pattern
                    if serialPatterns.contains(where: { corrected.range(of: $0, options: .regularExpression) != nil }) {
                        let confidence = calculateCorrectionConfidence(original: serial, corrected: corrected)
                        if confidence > (bestMatch?.1 ?? 0) {
                            bestMatch = (corrected, confidence)
                        }
                    }
                }
            }
        }
        
        return bestMatch
    }
    
    private func calculateCorrectionConfidence(original: String, corrected: String) -> Float {
        // Calculate confidence based on number and type of corrections
        let differences = zip(original, corrected).filter { $0 != $1 }
        let correctionCount = differences.count
        
        // More corrections = lower confidence
        let baseConfidence: Float = 0.9
        let confidenceReduction = Float(correctionCount) * 0.1
        
        return max(0.5, baseConfidence - confidenceReduction)
    }
    
    private func cacheValidation(serial: String, result: ValidatorResult) {
        // Implement LRU cache eviction if needed
        if validationCache.count >= cacheLimit {
            validationCache.removeValue(forKey: validationCache.keys.first!)
        }
        validationCache[serial] = result
    }
}

/// Validation result for serial number validation
enum ValidatorResult {
    case valid(String)
    case corrected(original: String, corrected: String)
    case suggestedCorrection(original: String, suggested: String, confidence: Float)
    case invalid(String)
}
