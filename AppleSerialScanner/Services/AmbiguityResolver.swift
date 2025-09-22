import Foundation
import os.log
import CoreGraphics

/// Resolves character ambiguities in Apple serial numbers using confusion matrices and Viterbi decoding
@available(iOS 13.0, *)
class AmbiguityResolver {
    // MARK: - Properties
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "AmbiguityResolver")
    private let mlDisambiguator = CharacterDisambiguator()
    
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
    
    /// Resolves character ambiguities using ML CharacterDisambiguator (facade over ML while preserving API)
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
        let bbox = candidate.boundingBox
        let mlResult = disambiguateWithMLSynchronously(text: originalText, boundingBox: bbox)
        
        return ResolvedCandidate(
            originalCandidate: candidate,
            resolvedText: mlResult.resolvedText,
            adjustedConfidence: mlResult.overallConfidence,
            hasAdjustments: !mlResult.corrections.isEmpty,
            corrections: mlResult.corrections
        )
    }
    
    // MARK: - ML Bridge
    private func disambiguateWithMLSynchronously(text: String, boundingBox: CGRect) -> (resolvedText: String, overallConfidence: Float, corrections: [String]) {
        let semaphore = DispatchSemaphore(value: 0)
        var resolvedTextOut = text
        var overallConfidenceOut: Float = 0.0
        var correctionsOut: [String] = []
        
        Task { @MainActor in
            do {
                let ambiguityScore = mlDisambiguator.getAmbiguityScore(for: text)
                let result = try await mlDisambiguator.disambiguateCharacters(
                    text: text,
                    glyphBoundingBoxes: [],
                    croppedGlyphs: nil,
                    ambiguityScore: ambiguityScore
                )
                resolvedTextOut = result.correctedText
                overallConfidenceOut = result.overallConfidence
                correctionsOut = result.corrections.map { corr in
                    "\(corr.originalChar) → \(corr.correctedChar)"
                }
            } catch {
                self.logger.error("ML disambiguation failed: \(error.localizedDescription)")
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1.0)
        return (resolvedTextOut, overallConfidenceOut, correctionsOut)
    }
    
    // Legacy heuristic methods retained for reference but unused; ML path is authoritative now.
    
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
