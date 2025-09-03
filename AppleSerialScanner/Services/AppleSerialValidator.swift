import Foundation

// MARK: - Validation Result
struct ValidationResult {
    let serial: String
    let confidence: Float
    let level: ValidationLevel
    let corrections: [String]
    let notes: String?
}

enum ValidationLevel {
    case ACCEPT
    case BORDERLINE
    case REJECT
}

// MARK: - Apple Serial Validator
class AppleSerialValidator {
    
    // MARK: - Validation Configuration
    private let minConfidence: Float = 0.7
    private let highConfidence: Float = 0.9
    private let borderlineConfidence: Float = 0.8
    
    // MARK: - Apple Serial Patterns
    private let serialPatterns = [
        // Standard 12-character alphanumeric
        "^[A-Z0-9]{12}$",
        // With possible separators
        "^[A-Z0-9]{4}[- ]?[A-Z0-9]{4}[- ]?[A-Z0-9]{4}$",
        // Some Apple products have different patterns
        "^[A-Z]{2}[0-9]{2}[A-Z0-9]{8}$",
        "^[A-Z0-9]{3}[A-Z]{1}[0-9]{8}$"
    ]
    
    // MARK: - Common Character Confusions
    private let characterConfusions: [Character: [Character]] = [
        "0": ["O", "D"],
        "1": ["I", "L"],
        "2": ["Z"],
        "5": ["S"],
        "6": ["G"],
        "8": ["B"],
        "A": ["4"],
        "B": ["8", "R"],
        "D": ["0", "O"],
        "E": ["3"],
        "G": ["6", "9"],
        "I": ["1", "L"],
        "L": ["1", "I"],
        "O": ["0", "D"],
        "Q": ["O", "0"],
        "R": ["B"],
        "S": ["5"],
        "Z": ["2"]
    ]
    
    // MARK: - Main Validation Method
    func validate_with_corrections(_ input: String, _ confidence: Float) -> ValidationResult {
        let cleaned = cleanInput(input)
        let corrections = generateCorrections(cleaned)
        
        // Check if any correction matches Apple serial patterns
        var bestSerial = cleaned
        var bestConfidence = confidence
        var bestLevel = ValidationLevel.REJECT
        
        // First check the original input
        if isValidAppleSerial(cleaned) {
            bestSerial = cleaned
            bestLevel = determineValidationLevel(confidence)
        } else {
            // Check corrections
            for correction in corrections {
                if isValidAppleSerial(correction) {
                    bestSerial = correction
                    bestConfidence = max(confidence - 0.1, 0.0) // Slight confidence penalty for corrections
                    bestLevel = determineValidationLevel(bestConfidence)
                    break
                }
            }
        }
        
        let notes = generateNotes(original: input, corrected: bestSerial, confidence: bestConfidence)
        
        return ValidationResult(
            serial: bestSerial,
            confidence: bestConfidence,
            level: bestLevel,
            corrections: corrections,
            notes: notes
        )
    }
    
    // MARK: - Input Cleaning
    private func cleanInput(_ input: String) -> String {
        return input
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Pattern Validation
    private func isValidAppleSerial(_ serial: String) -> Bool {
        for pattern in serialPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(location: 0, length: serial.utf16.count)
                if regex.firstMatch(in: serial, range: range) != nil {
                    return true
                }
            }
        }
        return false
    }
    
    // MARK: - Correction Generation
    private func generateCorrections(_ input: String) -> [String] {
        var corrections: [String] = []
        
        // Single character substitutions
        for (index, char) in input.enumerated() {
            if let confusions = characterConfusions[char] {
                for confusion in confusions {
                    var corrected = input
                    corrected.replaceSubrange(corrected.index(corrected.startIndex, offsetBy: index)...corrected.index(corrected.startIndex, offsetBy: index), with: String(confusion))
                    corrections.append(corrected)
                }
            }
        }
        
        // Common OCR errors
        let commonErrors = [
            ("I", "1"),
            ("O", "0"),
            ("S", "5"),
            ("Z", "2"),
            ("G", "6"),
            ("B", "8")
        ]
        
        for (wrong, correct) in commonErrors {
            let corrected = input.replacingOccurrences(of: wrong, with: correct)
            if corrected != input {
                corrections.append(corrected)
            }
        }
        
        return Array(Set(corrections)) // Remove duplicates
    }
    
    // MARK: - Validation Level Determination
    private func determineValidationLevel(_ confidence: Float) -> ValidationLevel {
        if confidence >= highConfidence {
            return .ACCEPT
        } else if confidence >= borderlineConfidence {
            return .BORDERLINE
        } else if confidence >= minConfidence {
            return .BORDERLINE
        } else {
            return .REJECT
        }
    }
    
    // MARK: - Notes Generation
    private func generateNotes(original: String, corrected: String, confidence: Float) -> String? {
        var notes: [String] = []
        
        if original != corrected {
            notes.append("Corrected from '\(original)' to '\(corrected)'")
        }
        
        if confidence < highConfidence {
            notes.append("Low confidence: \(Int(confidence * 100))%")
        }
        
        if notes.isEmpty {
            return nil
        }
        
        return notes.joined(separator: "; ")
    }
    
    // MARK: - Additional Validation Methods
    
    /// Validate a serial number without corrections
    func validate(_ serial: String, _ confidence: Float) -> ValidationResult {
        let cleaned = cleanInput(serial)
        let level = determineValidationLevel(confidence)
        
        return ValidationResult(
            serial: cleaned,
            confidence: confidence,
            level: level,
            corrections: [],
            notes: nil
        )
    }
    
    /// Check if a string looks like an Apple serial number
    func isLikelyAppleSerial(_ input: String) -> Bool {
        let cleaned = cleanInput(input)
        
        // Check length
        guard cleaned.count >= 10 && cleaned.count <= 15 else { return false }
        
        // Check character set
        let validChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        guard cleaned.unicodeScalars.allSatisfy({ validChars.contains($0) }) else { return false }
        
        // Check if it matches any pattern
        return isValidAppleSerial(cleaned)
    }
    
    /// Get all possible corrections for a serial number
    func getAllCorrections(_ input: String) -> [String] {
        let cleaned = cleanInput(input)
        return generateCorrections(cleaned)
    }
}
