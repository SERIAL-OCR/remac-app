    import Foundation
    import CoreGraphics

/// Validates Apple serial numbers with strict alphabet and length constraints
class SerialValidator {
    private let mlClassifier = SerialFormatClassifier()
    // Apple serial alphabet (excludes I, O, Q to avoid confusion)
    private static let allowedCharacters = Set("ABCDEFGHJKLMNPRSTUVWXYZ0123456789")
    
    // Apple serial patterns
    private let strictPattern = "^[A-HJ-NP-Z0-9]{12}$"
    private let flexiblePattern = "^[A-HJ-NP-Z0-9]{10,12}$"
    
    private let strictRegex: NSRegularExpression?
    private let flexibleRegex: NSRegularExpression?
    
    // Configuration
    private let useStrictValidation: Bool
    private let minimumLength: Int
    private let maximumLength: Int
    
    init(useStrictValidation: Bool = true) {
        self.useStrictValidation = useStrictValidation
        self.minimumLength = useStrictValidation ? 12 : 10
        self.maximumLength = 12
        
        // Initialize regex patterns
        do {
            strictRegex = try NSRegularExpression(pattern: strictPattern, options: [])
            flexibleRegex = try NSRegularExpression(pattern: flexiblePattern, options: [])
        } catch {
            // Fallback: disable regex-based validation but keep ML path working
            strictRegex = nil
            flexibleRegex = nil
        }
    }
    
    /// Validates a serial number candidate using ML classifier (facade over ML while preserving API)
    func validateSerial(_ text: String) -> SerialValidationResult {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        // Provide a reasonable default bounding box when only text is available
        // Use a horizontal box to avoid divide-by-zero and reflect serial-like geometry
        let defaultBoundingBox = CGRect(x: 0, y: 0, width: 100, height: 10)
        let mlResult = classifyWithMLSynchronously(text: cleanText, boundingBox: defaultBoundingBox)
        
        if mlResult.isValid {
            return SerialValidationResult(
                isValid: true,
                cleanedSerial: cleanText,
                rejectionReason: nil,
                confidence: mlResult.confidence
            )
        } else {
            // Map ML rejection to closest legacy reason for compatibility
            let invalidCharacters = Set(cleanText).subtracting(SerialValidator.allowedCharacters)
            let rejection: RejectionReason = !invalidCharacters.isEmpty
                ? .invalidCharacters(Array(invalidCharacters))
                : (cleanText.count < minimumLength || cleanText.count > maximumLength)
                    ? .invalidLength(cleanText.count)
                    : .patternMismatch
            
            return SerialValidationResult(
                isValid: false,
                cleanedSerial: cleanText,
                rejectionReason: rejection,
                confidence: mlResult.confidence
            )
        }
    }
    
    /// Batch validates multiple candidates via ML classifier and returns the best valid one
    func validateCandidates(_ candidates: [TextCandidate]) -> ValidationResult {
        var validCandidates: [ValidatedCandidate] = []
        var rejectedCandidates: [RejectedCandidate] = []
        
        for candidate in candidates {
            let cleanText = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let mlResult = classifyWithMLSynchronously(text: cleanText, boundingBox: candidate.boundingBox)
            
            let validation = SerialValidationResult(
                isValid: mlResult.isValid,
                cleanedSerial: cleanText,
                rejectionReason: mlResult.isValid ? nil : .patternMismatch,
                confidence: mlResult.confidence
            )
            
            if validation.isValid {
                validCandidates.append(ValidatedCandidate(
                    candidate: candidate,
                    validation: validation,
                    compositeScore: calculateCompositeScore(candidate, validation)
                ))
            } else {
                rejectedCandidates.append(RejectedCandidate(
                    candidate: candidate,
                    validation: validation
                ))
            }
        }
        
        validCandidates.sort { $0.compositeScore > $1.compositeScore }
        
        return ValidationResult(
            bestCandidate: validCandidates.first,
            allValidCandidates: validCandidates,
            rejectedCandidates: rejectedCandidates
        )
    }
    
    private func calculateSerialConfidence(_ serial: String) -> Float {
        var confidence: Float = 0.5 // Base confidence
        
        // Boost confidence for common Apple serial patterns
        
        // 1. Check for typical Apple serial structure patterns
        if serial.count == 12 {
            confidence += 0.2
        }
        
        // 2. Check for balanced character distribution
        let letterCount = serial.filter { $0.isLetter }.count
        let digitCount = serial.filter { $0.isNumber }.count
        
        // Apple serials typically have a mix of letters and numbers
        if letterCount >= 3 && digitCount >= 3 {
            confidence += 0.2
        }
        
        // 3. Check for common Apple prefixes/patterns (simplified)
        let firstThree = String(serial.prefix(3))
        if ["C02", "F17", "C07", "DMP", "C17"].contains(firstThree) {
            confidence += 0.1
        }
        
        return min(confidence, 1.0)
    }
    
    private func calculateCompositeScore(_ candidate: TextCandidate, _ validation: SerialValidationResult) -> Float {
        // Combine OCR confidence with serial pattern confidence
        let ocrWeight: Float = 0.6
        let patternWeight: Float = 0.4
        
        let ocrScore = candidate.confidence
        let patternScore = validation.confidence
        
        // Penalty for inverted text (less likely to be correct)
        let inversionPenalty: Float = candidate.isInverted ? 0.1 : 0.0
        
        // Penalty for alternative candidates (prefer primary OCR results)
        let alternativePenalty: Float = Float(candidate.alternativeRank) * 0.05
        
        let compositeScore = (ocrScore * ocrWeight) + (patternScore * patternWeight) - inversionPenalty - alternativePenalty
        
        return max(0.0, min(1.0, compositeScore))
    }

    /// Reset validator internal caches/state (used by recovery coordinator)
    func reset() {
        // No-op for now; placeholder for future stateful validator caches.
    }
    // MARK: - ML Bridge
    private func classifyWithMLSynchronously(text: String, boundingBox: CGRect) -> (isValid: Bool, confidence: Float) {
        // Bridge async ML classifier to sync API using a semaphore
        let semaphore = DispatchSemaphore(value: 0)
        var resultIsValid = false
        var resultConfidence: Float = 0.0
        
        Task {
            do {
                let classification = try await mlClassifier.classifySerial(
                    text: text,
                    boundingBox: boundingBox,
                    textObservation: nil
                )
                resultIsValid = classification.isAppleSerial
                resultConfidence = classification.confidence
            } catch {
                resultIsValid = false
                resultConfidence = 0.0
            }
            semaphore.signal()
        }
        
        // Wait for completion (with a reasonable timeout to avoid deadlocks)
        _ = semaphore.wait(timeout: .now() + 1.0)
        return (resultIsValid, resultConfidence)
    }
}

// NOTE: ValidationResult is defined in PipelineTypes.swift; by returning that type we align with pipeline expectations.
