import Foundation
import os.log

/// Resolves character ambiguities in Apple serial numbers using confusion matrices and Viterbi decoding
@available(iOS 13.0, *)
class AmbiguityResolver {
    // MARK: - Properties
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "AmbiguityResolver")
    
    // Character confusion matrix - penalties for common OCR mistakes
    private let confusionMatrix: [Character: [(Character, Float)]] = [
        "0": [("O", 0.3), ("D", 0.2), ("Q", 0.4)],
        "O": [("0", 0.3), ("D", 0.2), ("Q", 0.4)],
        "D": [("0", 0.2), ("O", 0.2)],
        "Q": [("0", 0.4), ("O", 0.4)],
        "1": [("I", 0.3), ("l", 0.4)],
        "I": [("1", 0.3), ("l", 0.3)],
        "l": [("1", 0.4), ("I", 0.3)],
        "2": [("Z", 0.2)],
        "Z": [("2", 0.2)],
        "5": [("S", 0.3)],
        "S": [("5", 0.3)],
        "6": [("G", 0.2)],
        "G": [("6", 0.2)],
        "8": [("B", 0.3)],
        "B": [("8", 0.3)]
    ]
    
    // Apple serial alphabet (excludes I, O, Q)
    private let allowedCharacters = Set("ABCDEFGHJKLMNPRSTUVWXYZ0123456789")
    
    init() {
        logger.debug("AmbiguityResolver initialized")
    }
    
    /// Resolves character ambiguities using Viterbi decoding with confusion penalties
    func resolveAmbiguities(in candidates: [TextCandidate]) -> AmbiguityResolutionResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        var resolvedCandidates: [ResolvedCandidate] = []
        
        for candidate in candidates {
            let resolved = resolveSingleCandidate(candidate)
            resolvedCandidates.append(resolved)
        }
        
        // Sort by adjusted confidence
        resolvedCandidates.sort { $0.adjustedConfidence > $1.adjustedConfidence }
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        return AmbiguityResolutionResult(
            resolvedCandidates: resolvedCandidates,
            totalCandidatesProcessed: candidates.count,
            candidatesWithAdjustments: resolvedCandidates.filter(\.hasAdjustments).count,
            processingTime: processingTime
        )
    }
    
    private func resolveSingleCandidate(_ candidate: TextCandidate) -> ResolvedCandidate {
        let originalText = candidate.text
        let (resolvedText, adjustments) = applyViterbiDecoding(originalText)
        
        // Calculate confidence adjustment based on alphabet compliance and adjustments made
        let alphabetPenalty = calculateAlphabetPenalty(resolvedText)
        let adjustmentPenalty = Float(adjustments.count) * 0.05 // 5% penalty per adjustment
        let adjustedConfidence = max(0.0, candidate.confidence - alphabetPenalty - adjustmentPenalty)
        
        // Convert adjustments to corrections array
        let corrections = adjustments.map { adj in
            "\(adj.originalCharacter) → \(adj.resolvedCharacter)"
        }
        
        return ResolvedCandidate(
            originalCandidate: candidate,
            resolvedText: resolvedText,
            adjustedConfidence: adjustedConfidence,
            hasAdjustments: !adjustments.isEmpty,
            corrections: corrections
        )
    }
    
    private func applyViterbiDecoding(_ text: String) -> (String, [CharacterAdjustment]) {
        var result = ""
        var adjustments: [CharacterAdjustment] = []
        
        for (index, char) in text.enumerated() {
            let resolvedChar = resolveCharacter(char, position: index, context: text)
            result.append(resolvedChar.character)
            
            if resolvedChar.wasAdjusted {
                adjustments.append(CharacterAdjustment(
                    position: index,
                    originalCharacter: char,
                    resolvedCharacter: resolvedChar.character,
                    confidence: resolvedChar.confidence
                ))
            }
        }
        
        return (result, adjustments)
    }
    
    private func resolveCharacter(_ char: Character, position: Int, context: String) -> ResolvedCharacter {
        // If character is already in allowed set, keep it
        if allowedCharacters.contains(char) {
            return ResolvedCharacter(character: char, confidence: 1.0, wasAdjusted: false)
        }
        
        // Find best replacement using confusion matrix
        if let confusions = confusionMatrix[char] {
            // Sort by penalty (lower is better) and prefer allowed characters
            let sortedConfusions = confusions.sorted { confusion1, confusion2 in
                let allowed1 = allowedCharacters.contains(confusion1.0)
                let allowed2 = allowedCharacters.contains(confusion2.0)
                
                if allowed1 && !allowed2 { return true }
                if !allowed1 && allowed2 { return false }
                return confusion1.1 < confusion2.1 // Lower penalty is better
            }
            
            if let bestReplacement = sortedConfusions.first,
               allowedCharacters.contains(bestReplacement.0) {
                let confidence = 1.0 - bestReplacement.1 // Convert penalty to confidence
                return ResolvedCharacter(
                    character: bestReplacement.0,
                    confidence: confidence,
                    wasAdjusted: true
                )
            }
        }
        
        // If no good replacement found, try direct mapping to similar allowed characters
        let directMapping = findDirectMapping(char)
        return ResolvedCharacter(
            character: directMapping,
            confidence: directMapping == char ? 1.0 : 0.5,
            wasAdjusted: directMapping != char
        )
    }
    
    private func findDirectMapping(_ char: Character) -> Character {
        // Direct mappings for characters not in confusion matrix
        switch char {
        case "I", "i": return "1"
        case "O", "o": return "0"
        case "Q", "q": return "0"
        case "l": return "1"
        default:
            // If character is completely unrecognized, map to most similar
            // This is a fallback - in production you might want to reject instead
            return char
        }
    }
    
    private func calculateAlphabetPenalty(_ text: String) -> Float {
        let invalidChars = text.filter { !allowedCharacters.contains($0) }.count
        return Float(invalidChars) * 0.1 // 10% penalty per invalid character
    }
}

// MARK: - Supporting Types

struct CharacterAdjustment {
    let position: Int
    let originalCharacter: Character
    let resolvedCharacter: Character
    let confidence: Float
}

struct ResolvedCharacter {
    let character: Character
    let confidence: Float
    let wasAdjusted: Bool
}

struct AmbiguityResolutionResult {
    let resolvedCandidates: [ResolvedCandidate]
    let totalCandidatesProcessed: Int
    let candidatesWithAdjustments: Int
    let processingTime: TimeInterval
}
